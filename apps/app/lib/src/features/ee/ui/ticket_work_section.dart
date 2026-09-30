import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api_exception.dart';
import '../../../core/error_messages.dart';
import '../../../core/reachability.dart';
import '../../../i18n/i18n.dart';
import '../../../sync/providers.dart';
import '../../../theme/tokens.dart';
import '../../workspaces/workspaces.dart';
import '../ticket_work_providers.dart';
import '../ticket_write_providers.dart';
import '../tickets_providers.dart' show ticketAssigneesForProvider;
import 'ticket_detail_screen.dart' show awOpenTicket;

/// Opens the request [work] is for, in its own unit (EE-297).
///
/// The request's screen acts in the unit on screen — its permissions, its
/// roster, its moves — and a task on Home may come from any unit the person is
/// in, so the unit is selected first (the "Birimlerim" door does the same).
Future<void> openTicketOfWork(
  BuildContext context,
  WidgetRef ref,
  TicketWork work,
) async {
  final here = ref.read(currentWorkspaceProvider).value?.id;
  if (work.workspaceId != here) {
    await ref
        .read(selectedWorkspaceIdProvider.notifier)
        .select(work.workspaceId);
  }
  if (!context.mounted) return;
  awOpenTicket(context, work.ticketId);
}

/// The request, under a task row's title: which one this work is, and the
/// way to it.
class AwTicketWorkChip extends ConsumerWidget {
  const AwTicketWorkChip({super.key, required this.work});

  final TicketWork work;

  @override
  Widget build(BuildContext context, WidgetRef ref) => TextButton.icon(
    key: Key('ticket-work-chip-${work.ticketId}'),
    // The row's own unmute button sets the measure: compact inside a list
    // row, still a real target.
    style: TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: AwSpace.x2),
      minimumSize: const Size(0, 32),
    ),
    onPressed: () => openTicketOfWork(context, ref, work),
    icon: const Icon(Icons.support_agent_outlined, size: 16),
    label: Text('ee.ticketWork.chip'.tr(args: {'ref': work.reference})),
  );
}

/// The task detail's "Request" card (EE-297): what this work is for, how to
/// get there, and — for the person on it — how to give it back.
///
/// Giving it back is done on the REQUEST: its people are this task's people,
/// so leaving the task alone would be a change the next sync takes back. It is
/// a server door (the desk's own rules decide it), so it waits for a
/// connection and says so before it is pressed (DESIGN §22).
class AwTicketWorkSection extends ConsumerStatefulWidget {
  const AwTicketWorkSection({super.key, required this.work});

  final TicketWork work;

  @override
  ConsumerState<AwTicketWorkSection> createState() =>
      _AwTicketWorkSectionState();
}

class _AwTicketWorkSectionState extends ConsumerState<AwTicketWorkSection> {
  bool _busy = false;

  TicketWork get work => widget.work;

  Future<void> _release(String assignmentId) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.maybeOf(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(eeTicketWriteApiProvider)
          .release(work.ticketId, assignmentId);
      // The task leaves this person's list once the unit's copy arrives; ask
      // for it now rather than at the next scheduled pull.
      unawaited(ref.read(syncEnginesProvider)[work.workspaceId]?.syncNow());
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'ee.ticketWork.released'.tr(args: {'ref': work.reference}),
          ),
        ),
      );
      // It is no longer their work: staying on it would be standing in a
      // colleague's task.
      if (router != null && router.canPop()) {
        router.pop();
      } else {
        router?.go('/');
      }
    } on ApiException catch (failure) {
      if (failure.code == 'NETWORK_ERROR') {
        ref.read(serverReachabilityProvider.notifier).unreachable();
      }
      messenger.showSnackBar(SnackBar(content: Text(localizedError(failure))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final me = ref.watch(currentUserIdProvider);
    final mine =
        (ref.watch(ticketAssigneesForProvider(work.ticketId)).value ?? const [])
            .where((a) => a.userId == me)
            .firstOrNull;
    // Unknown is not offline (`ServerReachability`): only a failed answer
    // greys the door out.
    final offline = ref.watch(serverReachabilityProvider) == false;
    String? unit;
    for (final w in ref.watch(workspacesProvider).value ?? const []) {
      if (w.id == work.workspaceId) unit = w.name;
    }
    final status =
        AwI18n.instance.maybeTranslate('ee.tickets.status.${work.status}') ??
        work.status;

    return Card(
      key: const Key('ticket-work-section'),
      child: Padding(
        padding: const EdgeInsets.all(AwSpace.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.support_agent_outlined, color: scheme.primary),
                const SizedBox(width: AwSpace.x2),
                Expanded(
                  child: Text(
                    '${work.reference} · ${work.subject}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AwSpace.x1),
            Text(
              [?unit, status].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AwSpace.x2),
            Text(
              'ee.ticketWork.explain'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AwSpace.x3),
            Wrap(
              spacing: AwSpace.x2,
              runSpacing: AwSpace.x2,
              children: [
                FilledButton.tonalIcon(
                  key: const Key('ticket-work-open'),
                  onPressed: () => openTicketOfWork(context, ref, work),
                  icon: const Icon(Icons.open_in_new),
                  label: Text('ee.ticketWork.open'.tr()),
                ),
                if (mine != null)
                  OutlinedButton.icon(
                    key: const Key('ticket-work-release'),
                    onPressed: offline || _busy
                        ? null
                        : () => _release(mine.assignmentId),
                    icon: const Icon(Icons.person_remove_outlined),
                    label: Text('ee.ticketWork.release'.tr()),
                  ),
              ],
            ),
            if (mine != null && offline) ...[
              const SizedBox(height: AwSpace.x2),
              Text(
                'ee.ticketWork.releaseOffline'.tr(),
                key: const Key('ticket-work-release-offline'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
