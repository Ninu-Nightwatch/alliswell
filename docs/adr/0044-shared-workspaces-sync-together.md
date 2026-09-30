# ADR-0044 — Shared workspaces sync together; a person's lists are their own work

- **Status:** Accepted
- **Date:** 2026-09-30
- **Related task:** EE-296, EE-297 (the core seams and the app's scope)

## Context

Until now the app kept exactly one workspace in sync — the one selected — and read its task
lists from `workspaces.first`, the first row of an unordered `/me`. For a person on their own
that is their one workspace, and nothing below changes for them. For an account that works in
workspaces somebody else owns (an organisation's, ADR-0008's units) it was wrong three ways:

1. **Home showed the wrong list.** `workspaces.first` was whichever workspace the database
   happened to return first; work assigned to the person in any other workspace never reached
   their Home, and a colleague's tasks in the first one did.
2. **The replica lied quietly.** A workspace that was not selected was not pulled, so anything
   written to it waited on the device until somebody happened to switch to it.
3. **Alarms rang for the room.** The scheduler armed every task of the selected workspace, and
   the server pushed a due reminder to every member's devices — a colleague's reminder rang on
   everybody's phone.

The overlay also needed to keep a record in step with a task from inside the task's own write
(ADR-0002), which surfaced two gaps in the seam: an observer that had to refuse a write could
only fail the whole push, and a task's deletion was never described to observers at all.

## Decision

### 1. `/me` says which workspace the account owns

Every row carries `owned` (`owner_id === me`), and the list is ordered by id. The app decides
which space is the person's own from that flag, never from the role (an organisation's owner may
hold `owner` in its workspaces) and never from the order.

### 2. Shared workspaces sync together

When an account has workspaces it does not own, the app keeps **every one of them** in sync:
one `SyncEngine` per workspace, the selected one on the usual cadence, the others five times
slower and on the socket's `sync:changed`. A workspace that leaves the list gets one last
round — a real loss of access is answered with the refusal that drops the replica. A write pokes
every engine; each drains only its own outbox. The notification centre and its badge read every
synced workspace. On one's own, the one workspace syncs exactly as before.

### 3. A person's lists are their work; content screens are the selected workspace

`TaskScope`: on one's own, every task of the one workspace. In shared workspaces, the tasks the
person is on, and the ones they made that nobody is on — from every synced workspace. Home, the
Board, Completed, the Inbox, search, the alarms, the background turn and the home-screen widget
all read the same scope (the background turn reads the last one the app left, since it has no
provider graph, no `/me` and on a locked phone no Keychain). Notes, projects, files, tags, quick
access and the create sheet read the **selected** workspace (`activeWorkspaceIdProvider`), and
a task created from Home in a shared workspace is assigned to its author. The workspace the
account owns is not offered by the switcher when shared ones exist. A task opened from Home
edits against its own workspace's projects, tags and roster. Calendar integrations connect to a
person's own account and are not offered in shared workspaces.

Tasks carry `createdBy` (read-only on the pull; replica v37). Rows pulled before v37 lack it, so
each shared workspace is pulled once from revision 0 — only against a server that sends `owned`,
the release that also sends `createdBy`.

### 4. The seam, three additions

- **`syncRefusal(code)`** — an observer refusing a write from inside its transaction. The write
  rolls back as any throw does; the refusal is REPORTED: REST answers 409 with the code, the
  push records the mutation as `rejected` and answers with the row's real state (`rebase`).
- **Deletions and edits are described.** `deleteTaskTree` (the REST delete and the push's
  delete are that one function) tells observers about every task it deletes, with the row as it
  was; `PATCH` and the MCP update describe both sides of the row, status included.
  `createTask`/`updateTask`/`applyStatusTransition` accept a caller's transaction.
- **`registerReminderAudience`** — whose devices a due reminder is pushed to, narrowed per task.
  An answer is intersected with the workspace's members; it can narrow, never widen; a resolver
  that throws narrows nothing.

## Alternatives considered

- **Keep one engine and switch it** — the engine followed the selection, and the lists it fed
  were only ever as complete as the last unit somebody looked at.
- **One engine pulling several workspaces** — the protocol's cursor, outbox and revocation are
  per workspace; merging them would be a protocol change for what several small engines do.
- **Scope by role** — `owner` is not ownership in an organisation's workspaces.
- **A post-commit hook for derived records** — `entity:changed` fires after the commit, so a
  derived record and the change it describes could disagree whenever a process died between them.

## Consequences

- A member's device carries every workspace they are in: more to pull, bounded by what each
  workspace already keeps (archives, pruning). The first start after the upgrade pulls each
  shared workspace once in full.
- Tests that pump a screen with a hand-set current workspace must say the rest of the world too:
  the workspace list (`workspacesProvider`) and, where a scope is read, who is signed in.
- The owned workspace in shared mode is a drawer nobody sees; it keeps working for what is
  written there on purpose (the overlay's unsent drafts).
