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

if [[ "$DO_PUSH" -ne 1 ]]; then
  echo "Skipped push (--no-push). Ledger modified locally; no commit made."
  exit 0
fi

# Commit via the GitHub Contents API so the commit is authored by the App's
# bot identity and signed/verified by GitHub. A plain `git push` with the App
# token works, but the resulting commit is unsigned and uses whatever local
# git user.name/email was configured.

CLA_REPO="${CLA_REPO:-netfoundry/cla}"
CLA_BRANCH="${CLA_BRANCH:-main}"
LEDGER_PATH="$CLA_VERSION/cla.json"

echo "Fetching current SHA for $LEDGER_PATH on $CLA_REPO@$CLA_BRANCH"
CURRENT_SHA=$(gh api "repos/$CLA_REPO/contents/$LEDGER_PATH?ref=$CLA_BRANCH" --jq '.sha')
if [[ -z "$CURRENT_SHA" || "$CURRENT_SHA" == "null" ]]; then
  echo "ERROR: could not fetch current SHA for $LEDGER_PATH" >&2
  exit 1
fi

NEW_CONTENT_B64=$(base64 -w0 < "$LEDGER" 2>/dev/null || base64 < "$LEDGER" | tr -d '\n')

COMMIT_MSG="Manually record CLA signature for @$RESOLVED_LOGIN

$REASON"

echo "Committing via Contents API (will be authored by the App bot and verified)"
gh api --method PUT "repos/$CLA_REPO/contents/$LEDGER_PATH" \
  -f message="$COMMIT_MSG" \
  -f content="$NEW_CONTENT_B64" \
  -f sha="$CURRENT_SHA" \
  -f branch="$CLA_BRANCH" >/dev/null

echo "Pushed signature commit to $CLA_REPO@$CLA_BRANCH."
