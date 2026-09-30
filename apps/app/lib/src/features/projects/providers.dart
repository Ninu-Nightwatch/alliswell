import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/providers.dart';
import '../auth/providers.dart';
import '../workspaces/workspaces.dart';
import 'data/project.dart';
import 'data/project_store.dart';

/// Projects list toggle: show the active projects or the archived ones
/// (OPH-110). Archived projects are hidden from the default view.
class ProjectsShowArchived extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final projectsShowArchivedProvider =
    NotifierProvider<ProjectsShowArchived, bool>(ProjectsShowArchived.new);

/// Local-first store (OPH-054): reads watch the drift replica, writes are
/// optimistic + outbox'd.
final projectStoreProvider = Provider<ProjectStore>(
  (ref) => ProjectStore(
    ref.watch(databaseProvider),
    () => pokeSync(ref),
  ),
);

/// Projects of the current workspace (sort_order, created_at) — live from the
/// local replica; the sync engine converges with the server in the background.
final projectsControllerProvider =
    StreamNotifierProvider<ProjectsController, List<Project>>(
      ProjectsController.new,
    );

/// Projects keyed by id, for O(1) name+color lookups on task rows — the
/// project badge (OPH-104) resolves a task's project without a per-row query —
/// and for the widget's colours and lists (OPH-336).
///
/// Every project of every synced workspace, not only the one selected: in an
/// organisation a row on Home may come from any unit the person is in, and its
/// badge must resolve there too. On one's own it is the same one workspace.
final projectsByIdProvider = Provider<Map<String, Project>>((ref) {
  final projects = ref.watch(listedProjectsProvider).value ?? const [];
  return {for (final project in projects) project.id: project};
});

/// The projects of ONE workspace — what a task's own project field offers: a
/// task opened from Home may live in a unit other than the one selected, and
/// a project from another workspace cannot be its project (EE-296).
final workspaceProjectsProvider = StreamProvider.family<List<Project>, String>(
  (ref, workspaceId) => ref.watch(projectStoreProvider).watchAll(workspaceId),
);

/// The projects behind [projectsByIdProvider], in list order.
final listedProjectsProvider = StreamProvider<List<Project>>((ref) {
  final workspaceIds = ref.watch(syncWorkspaceIdsProvider);
  if (workspaceIds.isEmpty) return Stream.value(const <Project>[]);
  return ref.watch(projectStoreProvider).watchAllIn(workspaceIds);
});

class ProjectsController extends StreamNotifier<List<Project>> {
  @override
  Stream<List<Project>> build() async* {
    ref.watch(syncEngineProvider);
    final workspaceId = await ref.watch(activeWorkspaceIdProvider.future);
    if (workspaceId == null) {
      yield const [];
      return;
    }
    yield* ref.watch(projectStoreProvider).watchAll(workspaceId);
  }

  Future<String> _workspaceId() async {
    final workspaceId = await ref.read(activeWorkspaceIdProvider.future);
    if (workspaceId == null) throw StateError('No workspace available');
    return workspaceId;
  }

  /// Returns the new project's id so callers (the picker's inline create,
  /// OPH-163) can select it immediately.
  Future<String> createProject(Map<String, dynamic> body) async {
    return ref.read(projectStoreProvider).create(await _workspaceId(), body);
  }

  Future<void> updateProject(String id, Map<String, dynamic> patch) =>
      ref.read(projectStoreProvider).update(id, patch);

  Future<void> toggleFavorite(Project project) =>
      updateProject(project.id, {'isFavorite': !project.isFavorite});

  Future<void> deleteProject(String id) =>
      ref.read(projectStoreProvider).delete(id);

  /// Archive/unarchive (OPH-110). With no cascade it is a plain optimistic
  /// status flip through the outbox (works offline). WITH a cascade it is a
  /// multi-entity server transaction, so it goes over REST and we pull to
  /// converge the replica — hence it needs a connection.
  Future<void> archiveProject(
    String id, {
    bool includeTasks = false,
    bool includeNotes = false,
  }) => _transition(
    id,
    endpoint: 'archive',
    status: 'archived',
    includeTasks: includeTasks,
    includeNotes: includeNotes,
  );

  Future<void> unarchiveProject(
    String id, {
    bool includeTasks = false,
    bool includeNotes = false,
  }) => _transition(
    id,
    endpoint: 'unarchive',
    status: 'active',
    includeTasks: includeTasks,
    includeNotes: includeNotes,
  );

  Future<void> _transition(
    String id, {
    required String endpoint,
    required String status,
    required bool includeTasks,
    required bool includeNotes,
  }) async {
    if (!includeTasks && !includeNotes) {
      await updateProject(id, {'status': status});
      return;
    }
    await ref
        .read(apiClientProvider)
        .post(
          '/api/v1/projects/$id/$endpoint',
          data: {'includeTasks': includeTasks, 'includeNotes': includeNotes},
        );
    await ref.read(syncEngineProvider)?.syncNow();
  }
}
