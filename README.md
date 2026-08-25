# cloudflare-worker-template

A [Copier](https://copier.readthedocs.io/) template for Generality Labs
Cloudflare Worker projects, plus the shared reusable CI/deploy workflows they
all call. It encodes one standard so the Worker repos don't drift:

- **TypeScript, `strict`**, type-checked with `tsc --noEmit`
- **vitest** running *inside workerd* via
  [`@cloudflare/vitest-pool-workers`](https://developers.cloudflare.com/workers/testing/vitest-integration/),
  so tests exercise real bindings (D1, R2) against local simulations
- **Named wrangler environments always**: the top level of `wrangler.toml` is
  local dev/tests only, and every deploy targets `[env.production]` (or
  `[env.staging]`) explicitly — local development can never bind production
  resources by accident
- **CI-driven deploys**: `wrangler deploy` runs from GitHub Actions with a
  scoped `CLOUDFLARE_API_TOKEN`, migrations applied first, health smoke test
  after
- **pre-commit** stack: Biome (lint + format — the TS analogue of ruff),
  [zizmor](https://docs.zizmor.sh/) (Actions security), actionlint, mdformat,
  optionally typos
- Shared **`worker-ci`** and **`worker-deploy`** reusable workflows, so every
  repo's CI and deploy pipeline is a thin caller
- **Keep a Changelog** `CHANGELOG.md`, SHA-pinned actions, Dependabot for
  actions and npm
- A Claude Code `SessionStart` hook that pre-warms the toolchain

## Scaffold a new Worker

```bash
uvx copier copy gh:Generality-Labs/cloudflare-worker-template my-new-worker
```

You'll be asked for the name and description, whether to add a staging
environment, which resources the Worker uses (D1, R2, cron triggers), the Node
version, and whether to run the typos spell-checker and the automatic
template-update PRs.

After scaffolding, the copier message lists the resource-creation commands
(`wrangler d1 create` / `wrangler r2 bucket create`) whose ids/names go into
`wrangler.toml`, and CI needs two repository secrets:

- `CLOUDFLARE_API_TOKEN` — token with Workers (and D1, if used) edit
  permissions
- `CLOUDFLARE_ACCOUNT_ID` — the Cloudflare account id

## How environments work

Deployed targets are named wrangler environments; the top level of
`wrangler.toml` is what `wrangler dev` and the test pool read, pointing at
`-dev` resources that are simulated locally. The top-level Worker *name* is
suffixed `-dev` too, so a bare `wrangler deploy` (without `--env`) can never
overwrite the deployed production Worker — it would create a separate
`<name>-dev` Worker instead. Two wrangler gotchas the scaffold
encodes, because everyone hits them once:

1. **Named environments do not inherit bindings.** `[[d1_databases]]`,
   `[[r2_buckets]]` and `[triggers]` must be repeated per environment,
   pointing at that environment's own resources. The scaffold writes every
   block out explicitly.
1. **Cron triggers fire in every environment that declares them.** The
   scaffold declares crons in staging as well as production; delete the
   staging block for a job that must not run twice (email, paid APIs, ...).

With `use_staging`, every push to main deploys staging first and production
second, each as a GitHub environment. Add required reviewers to the
`production` GitHub environment in repo settings to turn that hand-off into a
manual approval gate. Each deploy job smoke-tests the Worker afterwards when a
`HEALTH_URL` variable is set on the GitHub environment.

One constraint worth knowing: the deploy pipeline passes the Cloudflare
secrets to the reusable workflow explicitly (zizmor flags `secrets: inherit`,
and with reason). That means the secrets live at the *repository* level. If
you need different tokens per environment, switch the scaffolded `deploy.yml`
to `secrets: inherit` and silence the finding — a deliberate, per-repo choice.

## Secrets

Secrets never live in `wrangler.toml` (that's for non-secret `[vars]`) or in
git. The scaffold's workflow:

1. Declare each secret as a `KEY=` line in the committed `.dev.vars.example`
   (suffix `# optional` for ones an environment may legitimately lack).
1. `cp .dev.vars.example .dev.vars` and fill in dev values — `wrangler dev`
   and vitest read it directly.
1. For deploys: `cp .dev.vars.example .dev.vars.production` (and
   `.dev.vars.staging`), fill in that environment's values, then
   `npm run secrets` / `npm run secrets:staging`. The script validates every
   required value before pushing anything, so a typo can't leave the Worker
   half-updated.

All the copies are gitignored; only `.dev.vars.example` is committed. Note
that `wrangler secret put` creates a new Worker version — long-running
Workflow instances keep the version (and secrets) they started with.

## Cloudflare Access in front of deployed Workers

The org convention: every deployed Worker hostname sits behind a Cloudflare
Access one-click app from day one — staging *stays* behind it permanently, so
half-baked deploys can never leak; production stays behind it until launch.
Turn it on per Worker in the dashboard (Workers & Pages -> the Worker ->
Settings -> Domains & Routes -> workers.dev -> Enable Cloudflare Access).

**Smoke tests through Access.** The deploy smoke test requires a real 200, so
an Access-protected `HEALTH_URL` needs a service token: in Zero Trust ->
Access -> Service Auth, create a token; on each protected Access app add a
policy with decision **Service Auth** that includes that token; then set the
token's id/secret as the `ACCESS_CLIENT_ID` / `ACCESS_CLIENT_SECRET`
*repository* secrets (they resolve in the caller's context, like the
Cloudflare ones).

**Making production public at launch** — `scripts/set-public-access.sh
<on|off|status>` attaches/detaches a named Bypass policy on the production
app without touching the app's own policies, so `off` restores exactly the
prior state; it verifies the live behaviour from outside afterwards, and the
`on` direction asks for typed confirmation (or `--yes` non-interactively).

Two hard-won API-token notes (they apply to the script, which is why it reads
`CLOUDFLARE_API_TOKEN` from the environment rather than reusing CI's):
editing Access needs an *account-scoped* token with BOTH "Access: Apps" and
"Access: Policies" write (Policies-only looks fine right up until `POST apps`
fails with `[1010] auth.forbidden`); and keep Access-editing rights out of
the CI deploy token — mint short-TTL tokens for the occasional toggle
instead. Also note Access does not log requests a Bypass policy admits.

## The reusable workflows

Generated projects call these rather than duplicating CI. To bump CI for every
repo at once, change it here and move the `v1` tag (releases move it via
`bump-v1.yml`).

[`worker-ci.yml`](.github/workflows/worker-ci.yml) — install, `tsc --noEmit`,
vitest, and the pre-commit stack:

```yaml
jobs:
  ci:
    uses: Generality-Labs/cloudflare-worker-template/.github/workflows/worker-ci.yml@v1
    with:
      node-version: "22"
```

[`worker-deploy.yml`](.github/workflows/worker-deploy.yml) — optional D1
migrations, `wrangler deploy --env <env>`, health smoke test; called once per
environment. The smoke test requires an actual `200` (an Access login
redirect does not count); for Access-protected Workers set the
`ACCESS_CLIENT_ID` / `ACCESS_CLIENT_SECRET` repository secrets to an Access
service token that a Service Auth policy on the app allows:

```yaml
jobs:
  production:
    uses: Generality-Labs/cloudflare-worker-template/.github/workflows/worker-deploy.yml@v1
    with:
      environment: production
    secrets:
      cloudflare-api-token: ${{ secrets.CLOUDFLARE_API_TOKEN }}
      cloudflare-account-id: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
```

npm is assumed throughout (both scripts and lockfile) — it's what the existing
Worker repos use, and workers projects have no build step for a faster
package manager to speed up.

## Testing against real bindings

The test pool runs the Worker in workerd with simulated local resources. With
`use_d1`, `vitest.config.ts` reads `migrations/` and a setup file applies them
to the simulated database before every run — so tests exercise the *actual
migrations*, not a hand-maintained copy of the schema, and a migration that
breaks the schema fails CI before it reaches a real database.

## Turning off `typos`

Answer no to `use_typos` and the hook is left out of the generated
`.pre-commit-config.yaml`. Worth doing for projects whose vocabulary the
checker doesn't know — domain terms, non-English proper nouns — or that commit
generated data. The hook is configured **report-only** (`--write-changes` is
deliberately dropped from its defaults): a spelling correction should need a
human to approve it.

## Update an existing project when the template changes

From inside a project that was generated from this template (it has a
`.copier-answers.yml`):

```bash
uvx copier update
```

Copier does a 3-way merge between the old template output, the new output, and
your local edits — so you get template improvements without losing your
customizations.

Answer yes to `use_template_update` (the default) and the scaffold gets a
`template-update.yml` workflow that runs `copier update` weekly (and on
demand) and opens a PR when the template's *scaffolded files* have changed.
Reusable-workflow changes need no update run: consumers pin `@v1`, so moving
the tag propagates those immediately.

## Versioning

Tagged releases move a `v1` major tag via `bump-v1.yml`. Generated projects
pin the reusable workflows to `@v1`; a repo-local `.github/zizmor.yml` allows
tag-pinned refs from `Generality-Labs/*` while still requiring commit-SHA pins
for third-party actions, and the generated `.github/dependabot.yml` tells
Dependabot to leave `Generality-Labs/*` alone so it doesn't rewrite the moving
tag to a fixed version on every release.

## Prior art

The template's structure (copier layout, reusable-workflow versioning,
pre-commit stack, template-update machinery) is adapted from
[MattFisher/python-project-template](https://github.com/MattFisher/python-project-template),
with the Python toolchain swapped for the Workers one.
