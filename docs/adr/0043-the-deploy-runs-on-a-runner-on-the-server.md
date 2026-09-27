# ADR-0043 — The deploy runs on a runner on the server, started from the overlay's private repository

- **Status:** Accepted
- **Date:** 2026-09-27
- **Related task:** — (owner decision 2026-09-27: one self-hosted runner deploys the core and the
  overlay in one go; a tag still deploys by itself)

## Context

`deploy.yml` ran on GitHub's runner in this public repository and reached the server over SSH, with
a key accepted from anywhere and stored here as a secret. The owner wants the deploy to run on the
server itself, from one self-hosted runner, shipping the core and the private overlay together.

What constrains it:

1. **A runner registers with exactly one owner** — a repository, an organisation or an enterprise.
   This repository belongs to a personal account and the overlay's to an organisation, so one
   runner cannot serve both.
2. **A public repository must never hold a self-hosted runner.** Anyone can open a pull request
   from a fork, and a pull request can change a workflow to run on that runner (GitHub's own
   hardening guidance). On the server, that runner holds the deploy key.
3. **Inside a called workflow, `github.repository`, `github.workflow_sha` and `vars` are the
   CALLER's.** A workflow written for its own repository deploys the caller's name and looks for
   its scripts in the caller's commit.
4. **The box.** Another project's runner already lives in `/opt/actions-runner`; `deploy.yml`'s
   Node discovery skips only paths under `*/actions-runner/*` (v1.4.0 broke on a runner's Node);
   the box has ~3 GiB of free memory and a Flutter web build takes 2–3; a login-alert script prints
   to stdout on every SSH session, and that output landed in this repository's public deploy logs.

## Decision

1. **The runner lives on the server, registered with the overlay's private repository** (label
   `alliswell-deploy`, a dedicated user with no sudo, installed under a path containing
   `/actions-runner/`). That repository's `Deploy` workflow calls this repository's `deploy.yml`
   at `main`, passing `runner` (JSON for `runs-on`), `core_repository` and the secrets by name.
   `deploy.yml` stays the single implementation, and GitHub's runner stays its default.
2. **The ref is a release before any of its code runs**: a version tag of this repository, or a
   commit `main` already contains (`scripts/deploy/check-ref.mjs`, read from the workflow's own
   commit like the overlay gate). A pull request's head is neither.
3. **The deploy key lives for one job.** A last `if: always()` step deletes it, and the runner's
   job-completed hook does too. The key the runner uses is accepted by the server only from
   `127.0.0.1`/`::1` (`from=` in `authorized_keys`), so the secret is useless off the box.
4. **In the overlay's own repository the job's token replaces `DEPLOY_OVERLAY_TOKEN`** — contents
   and Actions runs, read-only, expiring with the job. Elsewhere the secret is still required and
   the gate refuses by name without it.
5. **`release.yml` takes exactly one path.** With `vars.DEPLOY_VIA_OVERLAY` = `true` it only starts
   the overlay repository's `Deploy` (`secrets.DEPLOY_DISPATCH_TOKEN`: fine-grained, that one
   repository, Actions: write; the repository's name stays in `secrets.DEPLOY_OVERLAY_REPO`).
   Otherwise `deploy.yml` runs here exactly as before — forks and self-hosters see no change.
6. **The live sites outrank the build.** The runner's systemd unit carries `OOMScoreAdjust=1000`,
   `Nice=10`, low IO priority and `Restart=on-failure`: under memory pressure the build is killed
   first, never the database. The build runs before anything on the server changes, so a killed
   build is a failed deploy with the live site untouched.

## Alternatives considered

- **Register the runner with this public repository** (the smallest code change) — rejected by
  constraint 2; approval settings for fork pull requests make it a human's click away from root.
- **Move this repository into the organisation** so one organisation runner serves both — a much
  larger change, and a public repository would still be holding the runner.
- **Keep the deploy on GitHub's runner and move only the overlay's CI onto a runner** — keeps a key
  valid from anywhere in a public repository's secrets; and the overlay's CI on the production box
  means test databases on the ports the live ones use, next to the live sites.
- **Pay for more Actions minutes** — declined by the owner; the server already exists.

## Consequences

- Deploy logs now live in a private repository; the login alert's output no longer reaches a public
  log (in the old ones the server address was masked only because it equals a secret's value).
- A release run no longer shows the deploy's outcome — only that it started. Follow the overlay
  repository's `Actions ▸ Deploy`.
- The overlay gate (OPH-345) is unchanged: an overlay commit ships only on its own green CI.
- Deploys cost the server a few minutes of CPU and ~3 GB of memory for the Flutter build.
- Follow-up once this path has shipped a release: retire the old key and `DEPLOY_SSH_*` secrets
  here, and move `diagnose.yml` (it still SSHes in from GitHub's runner) to the same runner.
