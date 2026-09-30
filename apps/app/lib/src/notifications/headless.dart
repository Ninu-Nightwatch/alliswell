import 'package:dio/dio.dart';

import '../core/app_liveness.dart';
import '../core/kv/local_kv.dart';
import '../core/server_url.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/data/models.dart';
import '../features/auth/data/auth_api.dart';
import '../features/auth/data/token_storage.dart';
import '../features/auth/data/secure_secret_store.dart';
import '../features/auth/data/auth_interceptor.dart';
import '../features/tasks/data/task_scope.dart';
import '../features/widgets/widget_bridge.dart';
import '../features/widgets/widget_host.dart';
import '../i18n/i18n.dart';
import '../sync/db/connection.dart';
import '../sync/db/database.dart';
import '../sync/sync_api.dart';
import '../sync/sync_engine.dart';
import 'gateway.dart';
import 'gateway_local.dart';
import 'planner.dart';
import 'reminder_store.dart';
import 'scheduler.dart';

/// One background turn: sync, then re-arm the OS alarms (OPH-321), then redraw
/// the home-screen widget from the replica (OPH-334).
///
/// ── WHY THERE IS NO PROVIDER CONTAINER HERE ───────────────────────────────
///
/// Building one was the obvious move and it is rejected on purpose. The graph
/// is UI-shaped: long-lived streams, a pull timer, an `AppLifecycleListener`
/// that binds to `WidgetsBinding`, a router — and `currentWorkspaceProvider`
/// makes a NETWORK call, so a container built at 3 a.m. offline would resolve
/// to "no workspace" and this turn would schedule nothing while believing it
/// had done its job. Three objects by hand say what they depend on; a
/// container hides it.
///
/// ── AND WHY THE ORDER IS THE ORDER ────────────────────────────────────────
///
/// Every step below was chosen because the obvious alternative is wrong here,
/// not because it reads nicely:
///
/// 1. [AwI18n.boot] is MANDATORY and first. A notification's text goes through
///    `.tr()`, and an unbooted catalogue renders keys — so the identity a
///    notification is scheduled under would differ from the one the live app
///    produces, and the same alarm would be scheduled twice under two ids.
/// 2. The workspaces come from `sync_states` — every row, one per workspace
///    the app keeps in sync (a member of an organisation syncs all of their
///    units) — never from `/me`: that is a network call, and offline it fails
///    into "sync nothing". WHOSE alarms and widget come from the scope the app
///    last built its lists from ([recallTaskScope]); a replica no build of
///    that kind has run on yet is read the way the build before it read it,
///    one workspace, whole.
/// 3. The base URL is read from [localKv] DIRECTLY. `PersistedChoice` answers
///    its fallback synchronously and hydrates after — in a process this short
///    that fallback IS the answer, and a self-hoster would be sent to the
///    hosted API with their own token.
/// 4. No session means exit, silently. A signed-out install has nothing to
///    sync and nothing to schedule.
/// 5. `syncNow()`, not `start()`: `start` installs a pull timer this process
///    will never live to fire.
Future<void> runHeadlessRefresh({
  AwDatabase Function()? openDatabase,
  AppLiveness? liveness,
  NotificationsGateway Function()? openGateway,
  WidgetHost? widgetHost,
}) async {
  // The app is in front of the user and already doing this, continuously
  // (OPH-318). WAL makes the overlap survivable; not overlapping is cheaper.
  if (await (liveness ?? appLiveness).isForeground(DateTime.now())) return;

  await AwI18n.instance.boot();

  final db = openDatabase?.call() ?? AwDatabase(openAwConnection());
  try {
    final synced = [
      for (final state in await db.select(db.syncStates).get())
        state.workspaceId,
    ];
    if (synced.isEmpty) return;
    final remembered = await recallTaskScope(syncedWorkspaceIds: synced);
    TaskScope? scope = remembered?.scope ?? TaskScope.workspace(synced.first);

    try {
      final baseUrl =
          await localKv.get(kServerUrlPrefKey) ?? compiledApiBaseUrl;

      final repository = AuthRepository(
        api: AuthApi(Dio(BaseOptions(baseUrl: baseUrl))),
        storage: TokenStorage(defaultSecretStore()),
      );
      // A Keychain that cannot be read is not an error here, it is an answer:
      // iOS stores the session under `kSecAttrAccessibleWhenUnlocked`, so a
      // wake on a locked phone reads nothing (ADR-0038 §8). Treating that as
      // "signed out" is what makes this turn a no-op instead of a crash loop.
      AuthSession? session;
      try {
        session = await repository.restore();
      } on Object {
        session = null;
      }
      if (session == null) return;
      if (remembered != null && remembered.userId != session.user.id) {
        // Left by an account that is no longer the one signed in. Its lists
        // are not this person's: nothing is scheduled or drawn from them, and
        // the app builds this person's own the next time it runs.
        scope = null;
        return;
      }

      final dio = Dio(BaseOptions(baseUrl: baseUrl));
      dio.interceptors.add(
        AuthInterceptor(
          getAccessToken: () => repository.accessToken,
          refreshAccessToken: repository.refreshAccessToken,
        ),
      );

      final api = SyncApi(dio);
      for (final workspaceId in synced) {
        final engine = SyncEngine(db: db, api: api, workspaceId: workspaceId);
        try {
          await engine.syncNow();
        } on Object {
          // Offline, or the server said no. The replica still holds whatever
          // it held, and scheduling from stale rows beats scheduling nothing:
          // this turn exists because the app has not run, so those rows may
          // be the only ones the device will have until it does. One
          // workspace failing is not a reason to leave the next one stale.
        } finally {
          engine.dispose();
        }
      }

      final alarms = await ReminderStore(db, () {}).readAlarmsIn(scope);
      final scheduler = NotificationScheduler(
        gateway: openGateway?.call() ?? LocalNotificationsGateway(),
        // Nothing streams here; the set is read once and applied once.
        alarms: const Stream<List<AlarmInput>>.empty(),
        privacyMode: await _flag('notification_privacy'),
      );
      await scheduler.applyOnce(alarms);
      scheduler.dispose();
    } finally {
      // OPH-334: every path past this point — no session (a locked iPhone reads
      // no Keychain), offline, a server that said no — ends by redrawing the
      // widget from the replica. The rows may be stale; the DAY is not, and at
      // midnight the day is what moved. Never throws (see the function).
      if (scope != null) {
        await publishWidgetFromReplica(
          db,
          scope: scope,
          now: DateTime.now(),
          host: widgetHost,
        );
      }
    }
  } finally {
    // Always: a background isolate that leaves the file open is the second
    // writer the WAL work (OPH-318) was about.
    await db.close();
  }
}

Future<bool> _flag(String key) async => (await localKv.get(key)) == 'true';
