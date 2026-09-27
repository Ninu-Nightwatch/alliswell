import { describe, expect, test } from 'vitest';

import { checkRef, main, refKind } from '../../../../scripts/deploy/check-ref.mjs';

/// ADR-0043 — a deploy ships a release, never whatever a ref names.
///
/// deploy.yml runs this before any of the ref's code does. On a runner that
/// lives on the server, the ref decides what runs next to the deploy key, so
/// only what the repository's owners can create passes: a version tag that
/// exists, or a commit `main` already contains. Driven with a fake
/// `git ls-remote` and a fake GitHub, so every answer is read, not believed.

const REPO = 'owner/core';
const SHA = 'a'.repeat(40);

/** A GitHub whose compare endpoint answers `status` (or an HTTP error), and records what was asked. */
function fakeCompare({ status = 'behind', http = 200 } = {}) {
  const asked = [];
  const fetchImpl = async (url, init) => {
    asked.push({ url, auth: init.headers.authorization });
    return { ok: http >= 200 && http < 300, status: http, json: async () => ({ status }) };
  };
  return { fetchImpl, asked };
}

describe('refKind — the shape, before GitHub is asked anything', () => {
  test('version tags and full SHAs are the only shapes a deploy accepts', () => {
    expect(refKind('v1.14.0')).toBe('tag');
    expect(refKind('v2.0.0-rc.1')).toBe('tag');
    expect(refKind(SHA)).toBe('sha');
    const refused = [
      'refs/pull/7/head',
      'main',
      '1.14.0',
      'v1.14',
      'a1b2c3d',
      `${SHA}0`,
      'v1.14.0/../x',
      '',
      undefined,
    ];
    for (const ref of refused) expect(refKind(ref), String(ref)).toBeNull();
  });
});

describe('checkRef', () => {
  test('a pull request head is refused without asking anyone anything', async () => {
    const { fetchImpl, asked } = fakeCompare();
    const tagLookups = [];
    const result = await checkRef({
      repo: REPO,
      ref: 'refs/pull/7/head',
      fetchImpl,
      hasTag: (...args) => tagLookups.push(args) > 0,
    });
    expect(result.ok).toBe(false);
    expect(asked).toEqual([]);
    expect(tagLookups).toEqual([]);
  });

  test('a tag passes only when the repository has it', async () => {
    const seen = [];
    const hasTag = (url, refname) => {
      seen.push([url, refname]);
      return refname === 'refs/tags/v1.14.0';
    };
    expect(await checkRef({ repo: REPO, ref: 'v1.14.0', hasTag })).toEqual({
      ok: true,
      kind: 'tag',
    });
    expect(seen).toEqual([['https://github.com/owner/core.git', 'refs/tags/v1.14.0']]);

    const missing = await checkRef({ repo: REPO, ref: 'v9.9.9', hasTag });
    expect(missing.ok).toBe(false);
    expect(missing.reason).toBe('v9.9.9 is not a tag of owner/core');
  });

  test('a SHA passes only when main already contains it', async () => {
    for (const status of ['behind', 'identical']) {
      const { fetchImpl, asked } = fakeCompare({ status });
      expect(await checkRef({ repo: REPO, ref: SHA, token: 't', fetchImpl })).toEqual({
        ok: true,
        kind: 'sha',
      });
      expect(asked).toEqual([
        { url: `https://api.github.com/repos/owner/core/compare/main...${SHA}`, auth: 'Bearer t' },
      ]);
    }
    // A fork's commit resolves through the network's shared objects — as a
    // commit main does not contain, which is the case this exists to refuse.
    for (const status of ['ahead', 'diverged']) {
      const { fetchImpl } = fakeCompare({ status });
      const result = await checkRef({ repo: REPO, ref: SHA, fetchImpl });
      expect(result.ok, status).toBe(false);
      expect(result.reason).toContain(`compare: ${status}`);
    }
  });

  test('a SHA GitHub does not know is refused with its status', async () => {
    const { fetchImpl } = fakeCompare({ http: 404 });
    expect(await checkRef({ repo: REPO, ref: SHA, fetchImpl })).toEqual({
      ok: false,
      reason: `${SHA} is not a commit of owner/core (HTTP 404)`,
    });
  });
});

describe('main — the step', () => {
  const run = async (env, deps = {}) => {
    const lines = [];
    const written = [];
    const code = await main({
      env: { GITHUB_STEP_SUMMARY: '/summary', CORE_REPO: REPO, ...env },
      append: (file, text) => written.push([file, text]),
      log: { log: (line) => lines.push(line) },
      hasTag: () => true,
      ...deps,
    });
    return { code, lines, written };
  };

  test('a release passes, saying what it is', async () => {
    const { code, lines, written } = await run({ REF: 'v1.14.0' });
    expect(code).toBe(0);
    expect(lines).toEqual(['ref: v1.14.0 is a release tag of owner/core']);
    expect(written).toEqual([]);
  });

  test('anything else stops the job, with an error and a summary line', async () => {
    const { code, lines, written } = await run({ REF: 'refs/pull/7/head' });
    expect(code).toBe(1);
    expect(lines).toHaveLength(1);
    expect(lines[0]).toMatch(/^::error::/);
    expect(lines[0]).toContain('ADR-0043');
    expect(written).toHaveLength(1);
    expect(written[0][0]).toBe('/summary');
    expect(written[0][1]).toMatch(/^### Ref\n/);
  });

  test('a GitHub that cannot be asked is a stop, not a pass', async () => {
    const fetchImpl = async () => {
      throw new Error('network down');
    };
    const { code, lines } = await run({ REF: SHA }, { fetchImpl });
    expect(code).toBe(1);
    expect(lines[0]).toContain('the ref could not be checked: network down');
  });
});
