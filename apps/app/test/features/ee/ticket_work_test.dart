import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:alliswell/src/core/reachability.dart';
import 'package:alliswell/src/features/ee/assignments_providers.dart';
import 'package:alliswell/src/features/ee/data/ticket_write_api.dart';
import 'package:alliswell/src/features/ee/ticket_work_providers.dart';
import 'package:alliswell/src/features/ee/ticket_write_providers.dart';
import 'package:alliswell/src/features/ee/tickets_providers.dart';
import 'package:alliswell/src/i18n/i18n.dart';
import 'package:alliswell/src/router.dart';
import 'package:alliswell/src/widgets/swipe_actions.dart';

import '../projects/fake_api.dart';
import '../settings/settings_groups_test.dart' show app;

const _ticketId = '01TICKETAAAAAAAAAAAAAAAAAA';

/// Records the one door this screen uses; everything else is not in the test.
class _RecordingWriteApi extends Fake implements EeTicketWriteApi {
  final released = <(String, String)>[];

  @override
  Future<void> release(String ticketId, String assignmentId) async {
    released.add((ticketId, assignmentId));
  }
}

/// A server that has never answered: the release door is shut, and says so.
class _Offline extends ServerReachability {
  @override
  bool? build() => false;

  // The app's own traffic in this test is answered by a fake server; the
  // point here is the state a phone with no signal is in, so it stays.
  @override
  void answered() {}
}

/// EE-297 — a request somebody is put on is a task on their list.
///
/// What the task's surfaces owe the person: which request it is and the way to
/// it, and none of the controls the request owns — deleting, cancelling, the
/// project, the repeat. Giving the work back is done on the request.
void main() {
  setUp(() => AwI18n.instance.setActiveCached(const Locale('en')));

  GoRouter routerOf() => GoRouter.of(awRootNavigatorKey.currentContext!);

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<(FakeApi, Map<String, dynamic>, _RecordingWriteApi)> pumpWork(
    WidgetTester tester, {
    bool offline = false,
    bool imOnIt = true,
  }) async {
    tall(tester);
    final api = FakeApi();
    final task = api.seedTask(title: '#41 · Pres İki yağ kaçırıyor');
    final work = TicketWork(
      ticketId: _ticketId,
      workspaceId: api.workspaceId,
      subject: 'Pres İki yağ kaçırıyor',
      status: 'in_progress',
      number: 41,
    );
    final writes = _RecordingWriteApi();
    await tester.pumpWidget(
      await app(
        api,
        extra: [
          workTicketsByTaskProvider.overrideWith(
            (ref) => Stream.value({task['id'] as String: work}),
          ),
          ticketWorkOfTaskProvider.overrideWith(
            (ref, taskId) => Stream.value(taskId == task['id'] ? work : null),
          ),
          ticketAssigneesForProvider.overrideWith(
            (ref, ticketId) => Stream.value([
              if (imOnIt)
                const Assignee(assignmentId: 'A-ME', userId: 'user-1'),
            ]),
          ),
          eeTicketWriteApiProvider.overrideWithValue(writes),
          if (offline) serverReachabilityProvider.overrideWith(_Offline.new),
        ],
      ),
    );
    await tester.pumpAndSettle();
    return (api, task, writes);
  }

  testWidgets('the row names the request, and cannot be swiped away', (
    tester,
  ) async {
    final (_, task, _) = await pumpWork(tester);

    expect(
      find.text('ee.ticketWork.chip'.tr(args: {'ref': '#41'})),
      findsOneWidget,
    );
    // A request's work is given back on the request, never deleted.
    expect(
      find.byWidgetPredicate((w) => w is AwSwipeToDelete && w.id == task['id']),
      findsNothing,
    );
  });

  testWidgets('the detail carries the request, and none of what it owns', (
    tester,
  ) async {
    final (_, task, _) = await pumpWork(tester);
    routerOf().push('/tasks/${task['id']}');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ticket-work-section')), findsOneWidget);
    expect(find.text('#41 · Pres İki yağ kaçırıyor'), findsWidgets);
    // The section right below the removed controls is built — so an absent
    // control is absent, not merely unbuilt.
    expect(find.text('task.checklist'.tr()), findsOneWidget);
    expect(find.byKey(const Key('task-delete')), findsNothing);
    expect(find.byKey(const Key('detail-project')), findsNothing);
    expect(find.byKey(const Key('repeat-switch')), findsNothing);
  });

  testWidgets('giving the request back releases MY assignment on it', (
    tester,
  ) async {
    final (_, task, writes) = await pumpWork(tester);
    routerOf().push('/tasks/${task['id']}');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ticket-work-release')));
    await tester.pumpAndSettle();

    expect(writes.released, [(_ticketId, 'A-ME')]);
    expect(
      find.text('ee.ticketWork.released'.tr(args: {'ref': '#41'})),
      findsOneWidget,
    );
  });

  testWidgets('offline, the door is shut and says why', (tester) async {
    final (_, task, writes) = await pumpWork(tester, offline: true);
    routerOf().push('/tasks/${task['id']}');
    await tester.pumpAndSettle();

    final button = tester.widget<OutlinedButton>(
      find.byKey(const Key('ticket-work-release')),
    );
    expect(button.onPressed, isNull);
    expect(
      find.byKey(const Key('ticket-work-release-offline')),
      findsOneWidget,
    );
    expect(writes.released, isEmpty);
  });

  testWidgets('somebody not on the request is offered the way to it only', (
    tester,
  ) async {
    final (_, task, _) = await pumpWork(tester, imOnIt: false);
    routerOf().push('/tasks/${task['id']}');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ticket-work-open')), findsOneWidget);
    expect(find.byKey(const Key('ticket-work-release')), findsNothing);
  });

  testWidgets('an ordinary task keeps every control it had', (tester) async {
    tall(tester);
    final api = FakeApi();
    final task = api.seedTask(title: 'Kendi işim');
    await tester.pumpWidget(await app(api));
    await tester.pumpAndSettle();
    routerOf().push('/tasks/${task['id']}');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ticket-work-section')), findsNothing);
    expect(find.byKey(const Key('task-delete')), findsOneWidget);
    expect(find.byKey(const Key('detail-project')), findsOneWidget);
    expect(find.byKey(const Key('repeat-switch')), findsOneWidget);
  });
}
