import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/providers.dart';
import '../workspaces/workspaces.dart';
import 'data/external_event.dart';

export 'data/external_event.dart' show ExternalEvent;

/// The user's own calendar, from the replica (OPH-083). Read-only by
/// construction — the store has no write path.
final externalEventStoreProvider = Provider<ExternalEventStore>(
  (ref) => ExternalEventStore(ref.watch(databaseProvider)),
);

/// Every synced calendar event of the workspace. Empty when no calendar is
/// connected, which is exactly what the views should show in that case.
final externalEventsProvider = StreamProvider<List<ExternalEvent>>((
  ref,
) async* {
  ref.watch(syncEngineProvider); // keep background sync alive, like tasks do
  final workspaceId = await ref.watch(activeWorkspaceIdProvider.future);
  // A connected calendar is a person's own, and an organisation's workspaces
  // are shared: a calendar connected there would reach everyone in the
  // workspace, so none is drawn (or offered — see the integrations screen).
  if (workspaceId == null || ref.watch(inSharedWorkspacesProvider)) {
    yield const [];
    return;
  }
  yield* ref.watch(externalEventStoreProvider).watchAll(workspaceId);
});
