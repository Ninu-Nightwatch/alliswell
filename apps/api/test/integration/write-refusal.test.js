import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { fileURLToPath } from 'node:url';

import { buildApp } from '../../src/app.js';
import { loadConfig } from '../../src/config.js';
import { newId } from '../../src/lib/ids.js';

// Needs real MySQL + Redis with migrations applied: the point is the ROLLBACK,
// which the unit suite's fake db does not simulate (ee-seam.test.js proves the
// response shapes there).
const enabled = process.env.INTEGRATION === '1';

const FIXTURE_DIR = fileURLToPath(new URL('../fixtures/ee-overlay', import.meta.url));
const emailPrefix = `refusal-${Date.now()}`;

/**
 * A write an extension refuses from inside its transaction (`syncRefusal`):
 * the fixture overlay's observer refuses completing a task titled "refuse me".
 * The write must be gone — not half-applied — on every door, and the push must
 * answer with the row's real state rather than fail the batch.
 */
describe.runIf(enabled)('integration: a write an extension refuses is rolled back', () => {
  let app;
  let owner;

  beforeAll(async () => {
    app = await buildApp({
      config: loadConfig({
        ...process.env,
        NODE_ENV: 'test',
        RATE_LIMIT_AUTH_MAX: '100',
        EE_ENABLED: '1',
        EE_DIR: FIXTURE_DIR,
      }),
    });
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/register',
      payload: { email: `${emailPrefix}-owner@example.com`, password: 'integration-pw-6' },
    });
    const body = res.json();
    owner = {
      id: body.user.id,
      workspace: body.workspace,
      headers: { authorization: `Bearer ${body.tokens.accessToken}` },
    };
  });

  afterAll(async () => {
    if (!app) return;
    const users = await app.db('users').where('email', 'like', `${emailPrefix}%`).select('id');
    const ids = users.map((u) => u.id);
    if (ids.length > 0) {
      await app.db('workspaces').whereIn('owner_id', ids).delete();
      await app.db('users').whereIn('id', ids).delete();
    }
    await app.close();
  });

  const make = async (title) =>
    (
      await app.inject({
        method: 'POST',
        url: `/api/v1/workspaces/${owner.workspace.id}/tasks`,
        headers: owner.headers,
        payload: { title },
      })
    ).json();

  // BIGINT may come back as a string; the API serializes it as a number.
  const row = async (id) => {
    const r = await app.db('tasks').where({ id }).first('status', 'revision', 'completed_at');
    return r && { ...r, revision: Number(r.revision) };
  };

  // A replay is recorded per device: `clientId` has to be the same on a resend.
  const push = (entityId, clientMutationId = newId(), clientId = newId()) =>
    app.inject({
      method: 'POST',
      url: '/api/v1/sync/push',
      headers: owner.headers,
      payload: {
        clientId,
        workspaceId: owner.workspace.id,
        baseRevision: 0,
        mutations: [
          {
            clientMutationId,
            // A minute ahead: equal milliseconds read as the older write (LWW).
            localUpdatedAt: new Date(Date.now() + 60_000).toISOString(),
            entityType: 'task',
            entityId,
            operation: 'update',
            patch: { status: 'completed' },
          },
        ],
      },
    });

  it('REST: the refused completion leaves the task open and its revision where it was', async () => {
    const task = await make('refuse me');
    const res = await app.inject({
      method: 'POST',
      url: `/api/v1/tasks/${task.id}/complete`,
      headers: owner.headers,
    });
    expect(res.statusCode).toBe(409);
    expect(res.json().code).toBe('SEAM_REFUSED');
    expect(await row(task.id)).toMatchObject({
      status: 'open',
      revision: task.revision,
      completed_at: null,
    });
  });

  it('PATCH: the same, through the door that used to skip observers', async () => {
    const task = await make('refuse me');
    const res = await app.inject({
      method: 'PATCH',
      url: `/api/v1/tasks/${task.id}`,
      headers: owner.headers,
      payload: { status: 'completed' },
    });
    expect(res.statusCode).toBe(409);
    expect(res.json().code).toBe('SEAM_REFUSED');
    expect(await row(task.id)).toMatchObject({ status: 'open', revision: task.revision });
  });

  it('push: rejected with the real row to rebase on, recorded so a replay answers the same', async () => {
    const task = await make('refuse me');
    const clientMutationId = newId();
    const clientId = newId();
    const first = await push(task.id, clientMutationId, clientId);
    expect(first.statusCode).toBe(200);
    const result = first.json().results[0];
    expect(result).toMatchObject({
      status: 'rejected',
      errorCode: 'SEAM_REFUSED',
      replayed: false,
    });
    // The device's optimistic "completed" is corrected by what the server holds.
    expect(result.rebase).toMatchObject({
      entityType: 'task',
      entityId: task.id,
      present: true,
      data: { status: 'open' },
    });
    expect(await row(task.id)).toMatchObject({ status: 'open', revision: task.revision });

    // The same outbox row resent (a retry after a lost answer) gets the recorded answer.
    const again = await push(task.id, clientMutationId, clientId);
    expect(again.json().results[0]).toMatchObject({
      status: 'rejected',
      errorCode: 'SEAM_REFUSED',
      replayed: true,
    });
  });

  it('a delete is described too: REST refused whole — the subtree stays', async () => {
    const task = await make('keep me');
    const child = (
      await app.inject({
        method: 'POST',
        url: `/api/v1/workspaces/${owner.workspace.id}/tasks`,
        headers: owner.headers,
        payload: { title: 'under it', parentTaskId: task.id },
      })
    ).json();
    const res = await app.inject({
      method: 'DELETE',
      url: `/api/v1/tasks/${task.id}`,
      headers: owner.headers,
    });
    expect(res.statusCode).toBe(409);
    expect(res.json().code).toBe('SEAM_KEPT');
    // Nothing of the walk survives the refusal — not the root, not the child
    // it had already soft-deleted, not a revision announcing either.
    for (const id of [task.id, child.id]) {
      const kept = await app.db('tasks').where({ id }).first('deleted_at');
      expect(kept.deleted_at).toBeNull();
    }
    expect(
      await app.db('sync_revisions').where({ entity_id: task.id, operation: 'delete' }).first(),
    ).toBeUndefined();
  });

  it('…and the push delete is rejected with the row to rebase on', async () => {
    const task = await make('keep me');
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/sync/push',
      headers: owner.headers,
      payload: {
        clientId: newId(),
        workspaceId: owner.workspace.id,
        baseRevision: 0,
        mutations: [
          { clientMutationId: newId(), entityType: 'task', entityId: task.id, operation: 'delete' },
        ],
      },
    });
    expect(res.statusCode).toBe(200);
    const result = res.json().results[0];
    expect(result).toMatchObject({ status: 'rejected', errorCode: 'SEAM_KEPT' });
    expect(result.rebase).toMatchObject({ entityId: task.id, present: true });
    expect(
      (await app.db('tasks').where({ id: task.id }).first('deleted_at')).deleted_at,
    ).toBeNull();
  });

  it('a task nobody refuses completes as ever, through every door', async () => {
    const viaRest = await make('plain one');
    expect(
      (
        await app.inject({
          method: 'POST',
          url: `/api/v1/tasks/${viaRest.id}/complete`,
          headers: owner.headers,
        })
      ).statusCode,
    ).toBe(200);
    expect((await row(viaRest.id)).status).toBe('completed');

    const viaPush = await make('plain two');
    expect((await push(viaPush.id)).json().results[0].status).toBe('applied');
    expect((await row(viaPush.id)).status).toBe('completed');
  });

  it('createTask joins a caller transaction and is rolled back with it', async () => {
    const { createTask } = await import('../../src/db/tasks.js');
    let id = null;
    await expect(
      app.db.transaction(async (trx) => {
        id = await createTask(app, {
          workspaceId: owner.workspace.id,
          userId: owner.id,
          body: { title: 'inside somebody else’s transaction' },
          trx,
        });
        // The task is visible to the transaction it joined…
        expect(await trx('tasks').where({ id }).first('id')).toBeTruthy();
        throw new Error('the caller changed its mind');
      }),
    ).rejects.toThrow('the caller changed its mind');
    // …and gone with it: the row and the revision that announced it.
    expect(id).toBeTruthy();
    expect(await app.db('tasks').where({ id }).first()).toBeUndefined();
    expect(await app.db('sync_revisions').where({ entity_id: id }).first()).toBeUndefined();
  });

  it('a task says who made it, over REST and in the pull', async () => {
    const task = await make('mine');
    expect(task.createdBy).toBe(owner.id);
    const pulled = await app.inject({
      method: 'GET',
      url: `/api/v1/sync/pull?workspaceId=${owner.workspace.id}&sinceRevision=0`,
      headers: owner.headers,
    });
    const change = pulled.json().changes.find((c) => c.entityId === task.id);
    expect(change.data.createdBy).toBe(owner.id);
  });
});
