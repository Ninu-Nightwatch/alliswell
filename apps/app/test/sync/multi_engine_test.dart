import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/features/auth/providers.dart';
import 'package:alliswell/src/features/workspaces/workspaces.dart';
import 'package:alliswell/src/sync/db/database.dart';
import 'package:alliswell/src/sync/providers.dart';

import '../features/auth/test_support.dart';

const _own = '01WSOWNAAAAAAAAAAAAAAAAAAA';
const _unitA = '01WSUNITAAAAAAAAAAAAAAAAAA';
const _unitB = '01WSUNITBBBBBBBBBBBBBBBBBB';

WorkspaceSummary _ws(String id, {required bool owned, bool? reported}) =>
    WorkspaceSummary(
      id: id,
      name: id.substring(4, 9),
      slug: id.toLowerCase(),
      colorRgb: '#2563EB',
      role: owned ? 'owner' : 'member',
      // `reported: false` is a server from before `owned`: the field is absent
      // and the role stands in for it.
      owned: reported == false ? null : owned,
    );

/// The list `/me` answers, changeable mid-test.
class _Workspaces extends Notifier<List<WorkspaceSummary>> {
  _Workspaces(this._initial);
  final List<WorkspaceSummary> _initial;

  @override
  List<WorkspaceSummary> build() => _initial;

  void set(List<WorkspaceSummary> next) => state = next;
}

/// Every pull the device made, as `workspace@sinceRevision`.
class _Server {
  final List<String> pulls = [];

  Future<ResponseBody> handle(
    RequestOptions options,
    Map<String, dynamic>? body,
  ) async {
    final path = options.uri.path;
    if (path == '/api/v1/sync/pull') {
      final ws = options.uri.queryParameters['workspaceId']!;
      final since = options.uri.queryParameters['sinceRevision']!;
      pulls.add('$ws@$since');
      return jsonBody(200, {
        'workspaceId': ws,
        'fromRevision': int.parse(since),
        'toRevision': int.parse(since),
        'hasMore': false,
        'changes': const [],
      });
    }
    if (path == '/api/v1/sync/push') {
      return jsonBody(200, {
        'workspaceId': body?['workspaceId'],
        'toRevision': 0,
        'results': const [],
      });
    }
    return jsonBody(404, {'code': 'NOT_FOUND', 'message': path});
  }
}

/// EE-296 — a member of an organisation syncs every unit they are in.
void main() {
  late AwDatabase db;
  late _Server server;
  late NotifierProvider<_Workspaces, List<WorkspaceSummary>> list;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // `localKv` keeps the instance it opened first, so a fresh mock alone
    // would still hold the markers an earlier test left.
    for (final id in [_own, _unitA, _unitB]) {
      await localKv.remove('$kCreatedByRepullPrefix$id');
    }
    db = AwDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    server = _Server();
  });

  tearDown(() => db.close());

  ProviderContainer containerWith(List<WorkspaceSummary> workspaces) {
    list = NotifierProvider<_Workspaces, List<WorkspaceSummary>>(
      () => _Workspaces(workspaces),
    );
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        apiClientProvider.overrideWithValue(
          fakeDio(FakeHttpClientAdapter(server.handle)),
        ),
        syncPullIntervalProvider.overrideWithValue(null),
        syncDebounceProvider.overrideWithValue(Duration.zero),
        currentUserIdProvider.overrideWithValue('user-1'),
        workspacesProvider.overrideWith((ref) async => ref.watch(list)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Lets the engines' first rounds (and any probe) run to the end.
  Future<void> settle(ProviderContainer container) async {
    await container.read(workspacesProvider.future);
    container.listen(syncEnginesProvider, (_, _) {});
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  test('one engine per unit of the organisation, and none for the '
      "account's own workspace", () async {
    final container = containerWith([
      _ws(_own, owned: true),
      _ws(_unitA, owned: false),
      _ws(_unitB, owned: false),
    ]);
    await settle(container);

    expect(container.read(syncEnginesProvider).keys, {_unitA, _unitB});
    // Both units pulled in the first rounds; the drafts drawer is the
    // courier's (EE-225), not an engine's.
    expect(server.pulls.map((p) => p.split('@').first).toSet(), {
      _unitA,
      _unitB,
    });
    // The engine on screen is the first unit's.
    expect(container.read(syncEngineProvider)?.workspaceId, _unitA);
  });

  test('on one\'s own: one engine, the one workspace, as before', () async {
    final container = containerWith([_ws(_own, owned: true)]);
    await settle(container);

    expect(container.read(syncEnginesProvider).keys, {_own});
    expect(server.pulls.map((p) => p.split('@').first).toSet(), {_own});
  });

  test('a unit that leaves the list gets one last round before its engine '
      'goes', () async {
    final container = containerWith([
      _ws(_own, owned: true),
      _ws(_unitA, owned: false),
      _ws(_unitB, owned: false),
    ]);
    await settle(container);
    final before = server.pulls.where((p) => p.startsWith(_unitB)).length;

    container.read(list.notifier).set([
      _ws(_own, owned: true),
      _ws(_unitA, owned: false),
    ]);
    await settle(container);

    expect(container.read(syncEnginesProvider).keys, {_unitA});
    // The probe: when access is really gone, the server's refusal to that
    // pull is what drops the replica (EE-058).
    expect(server.pulls.where((p) => p.startsWith(_unitB)).length, before + 1);
  });

  group('the one pull from the beginning (createdBy)', () {
    Future<void> cursorAt(String workspaceId, int revision) => db
        .into(db.syncStates)
        .insert(
          SyncStatesCompanion.insert(
            workspaceId: workspaceId,
            clientId: 'C1',
            lastRevision: Value(revision),
          ),
        );

    test('a unit already on the device is pulled once from revision 0, '
        'then incrementally again', () async {
      await cursorAt(_unitA, 40);
      final container = containerWith([
        _ws(_own, owned: true),
        _ws(_unitA, owned: false),
      ]);
      await settle(container);
      expect(server.pulls, contains('$_unitA@0'));

      // A second start — the next app launch — pulls from where it was.
      await (db.update(db.syncStates)
            ..where((s) => s.workspaceId.equals(_unitA)))
          .write(const SyncStatesCompanion(lastRevision: Value(41)));
      server.pulls.clear();
      container.invalidate(syncEngineForProvider(_unitA));
      await settle(container);
      expect(server.pulls, ['$_unitA@41']);
    });

    test('a server that does not send `owned` does not spend it', () async {
      await cursorAt(_unitA, 40);
      final container = containerWith([
        _ws(_own, owned: true, reported: false),
        _ws(_unitA, owned: false, reported: false),
      ]);
      await settle(container);
      expect(server.pulls, ['$_unitA@40']);
    });

    test("one's own workspace is never pulled again for it", () async {
      await cursorAt(_own, 40);
      final container = containerWith([_ws(_own, owned: true)]);
      await settle(container);
      expect(server.pulls, ['$_own@40']);
    });
  });
}
