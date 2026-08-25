# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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
