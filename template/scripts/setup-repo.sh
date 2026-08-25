#!/usr/bin/env bash
# Apply this repo's GitHub settings and rulesets — settings-as-code for the
# things GitHub keeps in the UI/API rather than in checked-in files.
#
#   1. Repo settings (PATCH /repos/{owner}/{repo}): delete_branch_on_merge —
#      merged head branches are deleted automatically. Stacked PRs depend on
#      this: GitHub only retargets a stacked PR to the next base when its
#      current base branch is deleted after merging.
#   2. Every ruleset JSON in .github/rulesets/: created if absent, updated in
#      place when a ruleset with the same name already exists. The JSON is
#      the same shape the GitHub UI imports/exports (Settings -> Rules).
#
# Idempotent: safe to re-run after editing any of the JSON files.
#
# NOTE: the rulesets API refuses private repos on the Free plan outright
# (403 "Upgrade to GitHub Pro..."). The script applies the plain settings,
# tells you, and exits cleanly — re-run it after the org plan upgrade.
#
# Usage (against the repo of the current checkout):
#   scripts/setup-repo.sh
set -euo pipefail

command -v jq > /dev/null || {
  echo "error: jq is required (brew install jq)" >&2
  exit 1
}
gh auth status > /dev/null 2>&1 || {
  echo "error: gh is not authenticated (run: gh auth login)" >&2
  exit 1
}

repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
echo "== GitHub settings for $repo =="

echo "+ repo settings: delete_branch_on_merge=true"
gh api -X PATCH "repos/$repo" -F delete_branch_on_merge=true > /dev/null

shopt -s nullglob
files=(.github/rulesets/*.json)
if [[ ${#files[@]} -eq 0 ]]; then
  echo "no ruleset files under .github/rulesets/ — done."
  exit 0
fi

# One listing up front; each file is then a create (no ruleset with that
# name) or an in-place update (PUT by id), so re-runs never duplicate.
if ! existing="$(gh api "repos/$repo/rulesets?per_page=100" 2>&1)"; then
  if grep -q "Upgrade to GitHub" <<< "$existing"; then
    echo "note: the rulesets API refuses private repos on the current GitHub plan"
    echo "      (needs Pro/Team+). Plain settings were applied; re-run this script"
    echo "      after the plan upgrade to apply .github/rulesets/*.json."
    exit 0
  fi
  printf '%s\n' "$existing" >&2
  exit 1
fi
for f in "${files[@]}"; do
  name="$(jq -r '.name' "$f")"
  id="$(jq -r --arg name "$name" '.[] | select(.name == $name) | .id' <<< "$existing" | head -n 1)"
  if [[ -n "$id" ]]; then
    echo "+ update ruleset '$name' (id $id) from $f"
    gh api -X PUT "repos/$repo/rulesets/$id" --input "$f" > /dev/null
  else
    echo "+ create ruleset '$name' from $f"
    gh api -X POST "repos/$repo/rulesets" --input "$f" > /dev/null
  fi
done

cat << EOF

Applied. Settings that stay manual:
  - the HEALTH_URL variable on each GitHub environment (deploy smoke tests)
  - required reviewers on the 'production' environment (needs GitHub Team+)
EOF
