/**
 * Attaches a stable machine-readable `code` (AGENTS.md §4) to an
 * @fastify/sensible HTTP error:
 *
 *   throw coded(app.httpErrors.notFound('Project not found'), 'PROJECT_NOT_FOUND');
 */
export function coded(httpError, code) {
  httpError.code = code;
  return httpError;
}

/**
 * A refusal raised INSIDE a write — by an extension's write observer, which runs
 * in the write's transaction and may find that the change cannot stand (a
 * record it keeps in step with the row refuses to move). Throwing it rolls the
 * write back, as any throw there does; what this shape adds is how the refusal
 * is REPORTED:
 *
 *   - a REST caller gets a 409 with `code`, like any other coded conflict;
 *   - the sync push records the mutation as `rejected` with `code` and answers
 *     with the row's real state (`rebase`), exactly like a mutation guard's
 *     refusal — instead of failing the whole push, which would leave the
 *     device retrying the same write forever.
 *
 * A guard should refuse first wherever it can (it runs before any write); this
 * is for what can only be known once the write is under way.
 */
export function syncRefusal(code, message = code) {
  const err = new Error(message);
  err.statusCode = 409;
  err.code = code;
  err.syncRefusal = code;
  return err;
}
