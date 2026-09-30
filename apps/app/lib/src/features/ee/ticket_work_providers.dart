import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/db/database.dart';
import '../../sync/providers.dart';

/// The request a task is the work of (EE-297, ADR-0019).
///
/// Somebody put on a request finds it on their Home as a task: one task per
/// request, in the request's own unit, carrying the request's people. The
/// server keeps the two in step from both ends; what the device needs is the
/// link — `tickets.work_task_id` — to draw the request on the task's row, to
/// send the person to it, and to take away what the request owns (delete,
/// project, parent, repeat, cancel).
class TicketWork {
  const TicketWork({
    required this.ticketId,
    required this.workspaceId,
    required this.subject,
    required this.status,
    this.number,
  });

  factory TicketWork.of(TicketRecord row) => TicketWork(
    ticketId: row.id,
    workspaceId: row.workspaceId,
    subject: row.subject,
    status: row.status,
    number: row.number,
  );

  final String ticketId;
  final String workspaceId;
  final String subject;
  final String status;
  final int? number;

  /// What people say out loud about a request: its number, else its words.
  String get reference => number == null ? subject : '#$number';

  @override
  bool operator ==(Object other) =>
      other is TicketWork &&
      other.ticketId == ticketId &&
      other.workspaceId == workspaceId &&
      other.subject == subject &&
      other.status == status &&
      other.number == number;

  @override
  int get hashCode =>
      Object.hash(ticketId, workspaceId, subject, status, number);
}

/// Every task that is a request's work, by task id, across the workspaces this
/// device syncs — ONE stream for a whole list, read by each row through
/// `select` (the assignees provider's shape), so a request changing does not
/// rebuild every other row.
///
/// Empty on a build with no overlay: nobody's requests reach the replica, so
/// no row draws anything and no screen has to ask whether the feature exists.
final workTicketsByTaskProvider = StreamProvider<Map<String, TicketWork>>((
  ref,
) {
  final workspaceIds = ref.watch(syncWorkspaceIdsProvider);
  if (workspaceIds.isEmpty) return Stream.value(const {});
  final db = ref.watch(databaseProvider);
  return (db.select(db.tickets)..where(
        (t) => t.workspaceId.isIn(workspaceIds) & t.workTaskId.isNotNull(),
      ))
      .watch()
      .map(
        (rows) => {for (final row in rows) row.workTaskId!: TicketWork.of(row)},
      );
});

/// The request [taskId] is the work of, or null — the task detail's view.
final ticketWorkOfTaskProvider = StreamProvider.family<TicketWork?, String>((
  ref,
  taskId,
) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.tickets)..where((t) => t.workTaskId.equals(taskId)))
      .watch()
      .map((rows) => rows.isEmpty ? null : TicketWork.of(rows.first));
});
