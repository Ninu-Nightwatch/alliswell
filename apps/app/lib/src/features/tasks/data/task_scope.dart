import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/kv/local_kv.dart';
import '../../../sync/db/database.dart';

/// Which tasks a person's OWN lists show — Home, the Board, Completed, the
/// Inbox, and what their alarms and home-screen widget are built from.
///
/// Two shapes, one question:
///
///   * a person on their own — every task of their one workspace, which is
///     all their work by definition;
///   * a member of an organisation — their work across EVERY workspace they
///     are in: the tasks they are on, and the ones they made that nobody has
///     taken. Home is that person's list, not a shared view: a colleague's
///     task sits in the same workspace and never on this Home. A task a
///     request is worked through belongs to whoever is on the request, so the
///     "made it" half never claims one of those.
class TaskScope {
  TaskScope.workspace(String workspaceId)
    : workspaceIds = [workspaceId],
      mineFor = null;

  TaskScope.mine(List<String> workspaceIds, String userId)
    : workspaceIds = List.unmodifiable(workspaceIds),
      mineFor = userId;

  final List<String> workspaceIds;

  /// Set for a member of an organisation: whose work.
  final String? mineFor;

  @override
  bool operator ==(Object other) =>
      other is TaskScope &&
      other.mineFor == mineFor &&
      other.workspaceIds.length == workspaceIds.length &&
      other.workspaceIds.every(workspaceIds.contains);

  @override
  int get hashCode => Object.hash(mineFor, Object.hashAllUnordered(workspaceIds));

  Map<String, Object?> toJson() => {
    'workspaceIds': workspaceIds,
    if (mineFor != null) 'mineFor': mineFor,
  };

  /// Null for anything that is not a scope this build wrote.
  static TaskScope? fromJson(Object? json) {
    if (json is! Map) return null;
    final ids = json['workspaceIds'];
    if (ids is! List || ids.isEmpty || ids.any((id) => id is! String)) {
      return null;
    }
    final workspaceIds = ids.cast<String>();
    final me = json['mineFor'];
    if (me is String) return TaskScope.mine(workspaceIds, me);
    return workspaceIds.length == 1
        ? TaskScope.workspace(workspaceIds.single)
        : null;
  }
}

/// Where the app leaves the scope its lists were last built from.
///
/// For the background turn (`runHeadlessRefresh`), which has none of the three
/// things the live graph builds a scope from: no provider graph, no `/me` (a
/// network call, and the turn often runs offline), and on a locked iPhone not
/// even the Keychain that says who is signed in. Without this the turn could
/// only guess, and its guess — "every task of a workspace" — is a colleague's
/// alarm ringing on this phone.
const kTaskScopePrefKey = 'alliswell_task_scope';

/// Records [scope] as [userId]'s. Never throws ([localKv] does not).
Future<void> rememberTaskScope(TaskScope scope, {required String userId}) =>
    localKv.set(
      kTaskScopePrefKey,
      jsonEncode({'userId': userId, 'scope': scope.toJson()}),
    );

/// The scope [rememberTaskScope] left and whose it is, narrowed to the
/// workspaces this replica still syncs ([syncedWorkspaceIds]) — rows of any
/// other cannot be here, and a scope with none of them left is not this
/// replica's. The caller compares [userId] with whoever it finds signed in.
Future<({TaskScope scope, String userId})?> recallTaskScope({
  required List<String> syncedWorkspaceIds,
}) async {
  final raw = await localKv.get(kTaskScopePrefKey);
  if (raw == null) return null;
  final Object? stored;
  try {
    stored = jsonDecode(raw);
  } on FormatException {
    return null;
  }
  if (stored is! Map) return null;
  final userId = stored['userId'];
  final scope = TaskScope.fromJson(stored['scope']);
  if (userId is! String || scope == null) return null;
  final kept = [
    for (final id in scope.workspaceIds)
      if (syncedWorkspaceIds.contains(id)) id,
  ];
  if (kept.isEmpty) return null;
  final me = scope.mineFor;
  return (
    scope: me != null ? TaskScope.mine(kept, me) : TaskScope.workspace(kept.single),
    userId: userId,
  );
}

/// The rows [scope] covers, as a condition on the tasks table.
///
/// Subqueries rather than joins: a join to assignments would repeat a task
/// once per person on it, and every list here pages and counts TASKS. Drift
/// watches the subqueries' tables too, so a list re-emits when somebody is put
/// on a task or taken off it.
Expression<bool> taskScopeFilter(
  AwDatabase db,
  $TasksTable t,
  TaskScope scope,
) {
  final inScope = t.workspaceId.isIn(scope.workspaceIds);
  final me = scope.mineFor;
  if (me == null) return inScope;
  final onIt = existsQuery(
    db.select(db.taskAssignments)
      ..where((a) => a.taskId.equalsExp(t.id) & a.userId.equals(me)),
  );
  final nobodyOnIt = notExistsQuery(
    db.select(db.taskAssignments)..where((a) => a.taskId.equalsExp(t.id)),
  );
  final notARequestsWork = notExistsQuery(
    db.select(db.tickets)..where((k) => k.workTaskId.equalsExp(t.id)),
  );
  return inScope &
      (onIt | (t.createdBy.equals(me) & nobodyOnIt & notARequestsWork));
}
