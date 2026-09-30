import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alliswell/src/core/kv/local_kv.dart';
import 'package:alliswell/src/features/tasks/data/task_scope.dart';
import 'package:alliswell/src/features/tasks/data/task_store.dart';
import 'package:alliswell/src/sync/db/database.dart';

const unitA = '01WSUNITAAAAAAAAAAAAAAAAAA';
const unitB = '01WSUNITBBBBBBBBBBBBBBBBBB';
const me = '01USERMEAAAAAAAAAAAAAAAAAA';
const colleague = '01USERCOLLEAGUEAAAAAAAAAAA';
String id(String prefix) => prefix.padRight(26, '0');

/// EE-296 — what "my work" is, in an organisation's workspaces.
///
/// Home is the person's own list, not a shared view of a unit: the tasks they
/// are on, and the ones they made that nobody has taken. A task a request is
/// worked through belongs to whoever is on the request.
void main() {
  late AwDatabase db;
  late TaskStore store;

  var seq = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // `localKv` keeps the instance it opened first, so a fresh mock alone
    // would still answer with the previous test's value.
    await localKv.remove(kTaskScopePrefKey);
    db = AwDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    store = TaskStore(db, () {}, userId: me);
  });

  tearDown(() => db.close());

  Future<void> task(
    String tid,
    String unit, {
    String? createdBy,
    List<String> on = const [],
  }) async {
    await db
        .into(db.tasks)
        .insert(
          TasksCompanion.insert(
            id: id(tid),
            workspaceId: unit,
            title: 'Görev $tid',
            createdBy: Value(createdBy),
          ),
        );
    for (final person in on) {
      await db
          .into(db.taskAssignments)
          .insert(
            TaskAssignmentsCompanion.insert(
              id: id('A${seq++}'),
              workspaceId: unit,
              taskId: id(tid),
              userId: person,
            ),
          );
    }
  }

  Future<Set<String>> openIds(TaskScope scope) async => {
    for (final t in await store.watchOpenIn(scope).first) t.id,
  };

  group('my work', () {
    test('assigned to me, or made by me and taken by nobody', () async {
      await task('ON-ME', unitA, createdBy: colleague, on: [me]);
      await task('WITH-ME', unitB, createdBy: colleague, on: [colleague, me]);
      await task('MADE', unitB, createdBy: me);
      await task('GIVEN', unitA, createdBy: me, on: [colleague]);
      await task('THEIRS', unitA, createdBy: colleague);
      await task('LEGACY', unitA);

      expect(await openIds(TaskScope.mine([unitA, unitB], me)), {
        id('ON-ME'),
        id('WITH-ME'),
        id('MADE'),
      });
    });

    test("a request's work task is never mine for having made it", () async {
      // The service identity makes these, but a task a person made and then
      // linked is the same case: the request decides whose it is.
      await task('WORK', unitA, createdBy: me);
      await db
          .into(db.tickets)
          .insert(
            TicketsCompanion.insert(
              id: id('K1'),
              workspaceId: unitA,
              subject: 'Yazıcı',
              status: 'new',
              priority: 'normal',
              source: 'portal',
              number: const Value(41),
              workTaskId: Value(id('WORK')),
            ),
          );

      expect(await openIds(TaskScope.mine([unitA], me)), isEmpty);

      await db
          .into(db.taskAssignments)
          .insert(
            TaskAssignmentsCompanion.insert(
              id: id('AWORK'),
              workspaceId: unitA,
              taskId: id('WORK'),
              userId: me,
            ),
          );
      expect(await openIds(TaskScope.mine([unitA], me)), {id('WORK')});
    });

    test('a unit outside the scope contributes nothing', () async {
      await task('ON-ME-B', unitB, on: [me]);
      expect(await openIds(TaskScope.mine([unitA], me)), isEmpty);
    });

    test('the list follows an assignment as it is made and released', () async {
      await task('T', unitA, createdBy: colleague);
      final scope = TaskScope.mine([unitA], me);
      final seen = <Set<String>>[];
      final sub = store
          .watchOpenIn(scope)
          .listen((rows) => seen.add({for (final t in rows) t.id}));
      addTearDown(sub.cancel);
      await pumpEventQueue();

      await db
          .into(db.taskAssignments)
          .insert(
            TaskAssignmentsCompanion.insert(
              id: id('AT'),
              workspaceId: unitA,
              taskId: id('T'),
              userId: me,
            ),
          );
      await pumpEventQueue();
      await (db.delete(
        db.taskAssignments,
      )..where((a) => a.id.equals(id('AT')))).go();
      await pumpEventQueue();

      expect(seen, [
        <String>{},
        {id('T')},
        <String>{},
      ]);
    });

    test('on one\'s own: every task of the one workspace, as before', () async {
      await task('A', unitA, createdBy: colleague, on: [colleague]);
      await task('B', unitA);
      await task('ELSEWHERE', unitB);
      expect(await openIds(TaskScope.workspace(unitA)), {id('A'), id('B')});
    });
  });

  group('the scope left for the background turn', () {
    test('comes back as it was left, with whose it is', () async {
      await rememberTaskScope(TaskScope.mine([unitA, unitB], me), userId: me);

      final back = await recallTaskScope(syncedWorkspaceIds: [unitA, unitB]);

      expect(back!.scope, TaskScope.mine([unitB, unitA], me));
      expect(back.userId, me);
    });

    test('keeps only the workspaces this replica still syncs', () async {
      await rememberTaskScope(TaskScope.mine([unitA, unitB], me), userId: me);

      expect(
        (await recallTaskScope(syncedWorkspaceIds: [unitB]))!.scope,
        TaskScope.mine([unitB], me),
      );
      expect(await recallTaskScope(syncedWorkspaceIds: ['01WSOTHER']), isNull);
    });

    test('one workspace of one\'s own round-trips too', () async {
      await rememberTaskScope(TaskScope.workspace(unitA), userId: me);
      expect(
        (await recallTaskScope(syncedWorkspaceIds: [unitA]))!.scope,
        TaskScope.workspace(unitA),
      );
    });

    test('nothing, or something unreadable, is no scope', () async {
      expect(await recallTaskScope(syncedWorkspaceIds: [unitA]), isNull);
      await localKv.set(kTaskScopePrefKey, '{not json');
      expect(await recallTaskScope(syncedWorkspaceIds: [unitA]), isNull);
      await localKv.set(kTaskScopePrefKey, '{"userId":"$me","scope":{}}');
      expect(await recallTaskScope(syncedWorkspaceIds: [unitA]), isNull);
    });
  });
}
