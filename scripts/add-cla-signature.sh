#!/usr/bin/env bash
# Manually record a CLA signature for a contributor who signed out-of-band
# (e.g. emailed us a signed PDF) and therefore has no signing comment on a PR.
#
# Required env:
#   GH_TOKEN        -- a token with contents:write on netfoundry/cla.
#                      In CI, this is the nf-cla-bot App token.
#                      Locally, a PAT with `repo` scope works.
#
# Required args:
#   --username <handle>     GitHub handle (with or without leading @)
#   --reason   <text>       Free-text justification, recorded in JSON + commit
#
# Optional args:
#   --cla-version <vX.Y>    Defaults to v1.1
#   --repo-root   <path>    Defaults to current directory
#   --no-push               Skip the git push (for local testing)
#
# Exits non-zero on any failure (user not found, already signed, etc.).

set -euo pipefail

USERNAME=""
REASON=""
CLA_VERSION="v1.1"
REPO_ROOT="$(pwd)"
DO_PUSH=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --username)    USERNAME="$2"; shift 2 ;;
    --reason)      REASON="$2"; shift 2 ;;
    --cla-version) CLA_VERSION="$2"; shift 2 ;;
    --repo-root)   REPO_ROOT="$2"; shift 2 ;;
    --no-push)     DO_PUSH=0; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

USERNAME="${USERNAME#@}"

if [[ -z "$USERNAME" || -z "$REASON" ]]; then
  echo "ERROR: --username and --reason are required" >&2
  exit 2
fi

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "ERROR: GH_TOKEN env var is required" >&2
  exit 2
fi

LEDGER="$REPO_ROOT/$CLA_VERSION/cla.json"
if [[ ! -f "$LEDGER" ]]; then
  echo "ERROR: ledger not found at $LEDGER" >&2
  exit 2
fi

echo "Resolving GitHub user: $USERNAME"
USER_JSON=$(gh api "users/$USERNAME")
USER_ID=$(echo "$USER_JSON" | jq -r '.id')
RESOLVED_LOGIN=$(echo "$USER_JSON" | jq -r '.login')

if [[ -z "$USER_ID" || "$USER_ID" == "null" ]]; then
  echo "ERROR: could not resolve user id for $USERNAME" >&2
  exit 1
fi

echo "Resolved $USERNAME -> login=$RESOLVED_LOGIN id=$USER_ID"

EXISTING=$(jq --argjson id "$USER_ID" '.signedContributors[] | select(.id == $id) | .name' "$LEDGER")
if [[ -n "$EXISTING" ]]; then
  echo "ERROR: user id $USER_ID ($EXISTING) already in $LEDGER -- nothing to do" >&2
  exit 1
fi

NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

TMP=$(mktemp)
jq \
  --arg name "$RESOLVED_LOGIN" \
  --argjson id "$USER_ID" \
  --arg created_at "$NOW" \
  --arg note "$REASON" \
  '.signedContributors += [{
      name: $name,
      id: $id,
      comment_id: 0,
      created_at: $created_at,
      repoId: 0,
      pullRequestNo: 0,
      note: $note
   }]' "$LEDGER" > "$TMP"
mv "$TMP" "$LEDGER"

echo "Appended entry for $RESOLVED_LOGIN ($USER_ID) to $LEDGER"

cd "$REPO_ROOT"

# Configure committer identity only if not already set (CI sets these).
if [[ -z "$(git config user.email || true)" ]]; then
  git config user.email "nf-cla-bot@users.noreply.github.com"
  git config user.name  "nf-cla-bot"
fi

git add "$CLA_VERSION/cla.json"
git commit -m "Manually record CLA signature for @$RESOLVED_LOGIN

$REASON"

if [[ "$DO_PUSH" -eq 1 ]]; then
  git push origin HEAD:main
  echo "Pushed signature commit to main."
else
  echo "Skipped push (--no-push). Commit is local."
fi
