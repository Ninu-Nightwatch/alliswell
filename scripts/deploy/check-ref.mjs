#!/usr/bin/env node
/**
 * ADR-0043 — a deploy ships a release, never whatever a ref happens to name.
 *
 * deploy.yml checks out `inputs.ref` and builds it on the machine that holds
 * the server's deploy key. When that machine is a runner on the server itself,
 * the ref IS the question of what code runs there — and a ref can name a pull
 * request's head (`refs/pull/N/head`), which anyone with a fork can write.
 *
 * So the ref must be something only this repository's owners can create:
 *
 *   - a version tag (`vX.Y.Z`, optionally `-suffix`) that exists here, or
 *   - a full 40-hex commit SHA that `main` already contains — the path an
 *     untagged redeploy takes.
 *
 * Anything else stops the job before a single line of the ref's code runs.
 *
 * No dependencies and no imports beyond Node itself, on purpose: deploy.yml runs
 * this file as the version committed with the workflow, like overlay-ci.mjs.
 */
import { execFileSync } from 'node:child_process';
import { appendFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const TAG = /^v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/;
const SHA = /^[0-9a-f]{40}$/;

/** `'tag'`, `'sha'` or `null` — the shape alone, before GitHub is asked anything. */
export function refKind(ref) {
  if (typeof ref !== 'string') return null;
  if (TAG.test(ref)) return 'tag';
  if (SHA.test(ref)) return 'sha';
  return null;
}

/** True when the repository has the tag. `git ls-remote --exit-code` exits 2 on no match. */
function defaultHasTag(url, refname) {
  try {
    execFileSync('git', ['ls-remote', '--exit-code', '--tags', url, refname], {
      stdio: ['ignore', 'ignore', 'ignore'],
      env: { ...process.env, GIT_TERMINAL_PROMPT: '0' },
    });
    return true;
  } catch {
    return false;
  }
}

/**
 * `{ ok: true, kind }` or `{ ok: false, reason }`. A SHA is accepted only when
 * `main...sha` reads `behind` or `identical`: `main` already contains it. A
 * fork's commit is reachable through the network's shared objects, so it does
 * resolve — as `ahead` or `diverged`, which is exactly what is refused.
 */
export async function checkRef({
  repo,
  ref,
  token,
  fetchImpl = globalThis.fetch,
  hasTag = defaultHasTag,
}) {
  const kind = refKind(ref);
  if (!kind) {
    return {
      ok: false,
      reason: `"${ref}" is neither a version tag (vX.Y.Z) nor a full commit SHA`,
    };
  }
  if (kind === 'tag') {
    return hasTag(`https://github.com/${repo}.git`, `refs/tags/${ref}`)
      ? { ok: true, kind }
      : { ok: false, reason: `${ref} is not a tag of ${repo}` };
  }
  const res = await fetchImpl(`https://api.github.com/repos/${repo}/compare/main...${ref}`, {
    headers: {
      accept: 'application/vnd.github+json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
      'x-github-api-version': '2022-11-28',
      'user-agent': 'alliswell-deploy-check-ref',
    },
  });
  if (!res.ok)
    return {
      ok: false,
      reason: `${ref} is not a commit of ${repo} (HTTP ${res.status})`,
    };
  const { status } = await res.json();
  return status === 'behind' || status === 'identical'
    ? { ok: true, kind }
    : {
        ok: false,
        reason: `${ref} is not on ${repo}'s main (compare: ${status})`,
      };
}

/** The step: reads the job's environment, writes the job summary, returns the exit code. */
export async function main({
  env = process.env,
  fetchImpl = globalThis.fetch,
  hasTag = defaultHasTag,
  append = appendFileSync,
  log = console,
} = {}) {
  const repo = env.CORE_REPO ?? '';
  const ref = env.REF ?? '';
  const summary = (line) => env.GITHUB_STEP_SUMMARY && append(env.GITHUB_STEP_SUMMARY, `${line}\n`);

  let result;
  try {
    result = await checkRef({
      repo,
      ref,
      token: env.GH_TOKEN,
      fetchImpl,
      hasTag,
    });
  } catch (err) {
    result = {
      ok: false,
      reason: `the ref could not be checked: ${err.message}`,
    };
  }
  if (!result.ok) {
    const sentence = `${result.reason} — a deploy ships a release tag or a commit on main (ADR-0043).`;
    log.log(`::error::${sentence}`);
    summary(`### Ref\n\n${sentence}`);
    return 1;
  }
  log.log(
    `ref: ${ref} is ${result.kind === 'tag' ? 'a release tag' : 'a commit on main'} of ${repo}`,
  );
  return 0;
}

// Importing this file — which the suite does — must not run it.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = await main();
}
