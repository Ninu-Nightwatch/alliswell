import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/providers.dart';
import '../workspaces/workspaces.dart';
import 'data/quick_access_store.dart';
import 'data/quick_link.dart';

/// OPH-198 — the Quick Access rail's local-first machinery (ADR-0018).
final quickAccessStoreProvider = Provider<QuickAccessStore>(
  (ref) => QuickAccessStore(
    ref.watch(databaseProvider),
    onMutation: () => pokeSync(ref),
  ),
);

/// The signed-in user's rail, joined to its targets' live state. Empty while
/// signed out or before the first workspace arrives — every surface renders
/// "no shortcuts" rather than waiting.
final quickAccessRowsProvider = StreamProvider<List<QuickAccessRow>>((
  ref,
) async* {
  ref.watch(syncEngineProvider);
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) {
    yield const [];
    return;
  }
  final workspaceId = await ref.watch(activeWorkspaceIdProvider.future);
  if (workspaceId == null) {
    yield const [];
    return;
  }
  yield* ref.read(quickAccessStoreProvider).watchMine(workspaceId, userId);
});

/// Whether a given target already sits on the rail — what the entity menus
/// read to render "add" vs "remove" (OPH-201).
final quickAccessSavedProvider =
    Provider.family<QuickAccessRow?, (QuickKind, String)>((ref, target) {
      final rows = ref.watch(quickAccessRowsProvider).value ?? const [];
      for (final row in rows) {
        if (row.link.kind == target.$1 && row.link.targetId == target.$2) {
          return row;
        }
      }
      return null;
    });
