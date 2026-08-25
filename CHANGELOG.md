# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- `npm run typecheck` now regenerates binding types from wrangler.toml
  (`wrangler types --include-runtime=false`) before `tsc --noEmit`; the
  generated `worker-configuration.d.ts` is gitignored and the hand-maintained
  `Cloudflare.Env` declaration block is gone (declare only secrets by hand —
  the generator can't see those).
- The single `cors.json` is now per-environment (`cors.dev.json`,
  `cors.staging.json`, `cors.production.json`) so dev origins like localhost
  can never be applied to the production bucket.
- `vitest.config.ts` now defines two projects: `unit` (plain Node, for
  pure-function modules with no runtime `cloudflare:*` imports) and `worker`
  (workerd via the vitest workers pool, `test/worker.test.ts` only) — unit
  tests no longer pay the workerd startup cost.

### Added

- `use_playwright` option: a Playwright e2e setup that launches `wrangler
  dev` as its web server (readiness-probed on `/health`) and exercises the
  Worker over real HTTP via `npm run test:e2e`. Local-only by design — CI
  keeps running vitest.
- `scripts/set-public-access.sh <on|off|status>`: toggle whether the
  production Worker is publicly reachable by attaching/detaching a named
  Bypass policy on its Cloudflare Access app, with typed confirmation for the
  public direction and outside-in verification; plus a README section on the
  staging-behind-Access convention and smoke-testing through Access with a
  service token.
- Secrets workflow: a committed `.dev.vars.example` declares the Worker's
  secret names (with an `# optional` marker for ones an environment may
  lack); gitignored `.dev.vars.<env>` copies hold the values; and
  `scripts/put-secrets.sh` (npm run `secrets` / `secrets:staging`) validates
  the full set before pushing anything via `wrangler secret put`.
- Initial template: TypeScript Worker scaffold with named wrangler
  environments (local-dev top level, `[env.production]`, optional
  `[env.staging]`), optional D1/R2/cron support, vitest-pool-workers tests
  that apply real D1 migrations, reusable `worker-ci.yml` and
  `worker-deploy.yml` workflows, the shared pre-commit stack (Biome, zizmor,
  actionlint, mdformat, optional typos), and copier template-update
  machinery.

### Fixed

- The scaffolded top-level (local-dev) Worker name is now `<project>-dev`, so
  a bare `wrangler deploy` without `--env` can no longer deploy over the
  production Worker.
- `.gitignore` now un-ignores `.dev.vars.example` (the committed secrets
  template) instead of the stale `.env.example`.
- The deploy smoke test now requires an actual HTTP 200 instead of accepting
  any non-4xx/5xx response — behind Cloudflare Access it silently passed on
  the login redirect without ever exercising the Worker. It can authenticate
  with an Access service token via new optional `access-client-id` /
  `access-client-secret` secrets on `worker-deploy.yml`.
- Template CI's negative content assertions (`! grep …`) never actually
  enforced anything: `!` exempts a command from errexit (SC2251), so a failing
  assert couldn't fail the job. They now go through a `refute` helper that
  exits explicitly.
- `worker-ci.yml` no longer runs zizmor's online audits by default: they need
  a token that can read every repo referenced in `uses:`, which the default
  GITHUB_TOKEN cannot (this template repo is private), so every consumer's CI
  failed. Opt back in with the new `run-online-audits` input.
