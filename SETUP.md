# CLA Setup Guide for Repository Maintainers

This guide explains how to enable CLA checking on repositories in the NetFoundry, OpenZiti, or OpenZiti-Test-Kitchen organizations.

## How It Works

- Contributors sign the CLA **once** by commenting on any PR
- Their signature is stored in a versioned JSON file (e.g., `v1.1/cla.json`) in this repo
- All future PRs from that contributor automatically pass
- Organization members/owners are automatically skipped (covered by employment agreements)

## Quick Start (per repo)

Once your org is set up (see below), enabling CLA on a repo is just:

```bash
mkdir -p .github/workflows
curl -so .github/workflows/cla.yml https://raw.githubusercontent.com/netfoundry/cla/main/workflow-template/cla.yml
```

That's it. The workflow calls the reusable workflow in this repo, so all logic is centralized.

## Prerequisites

### 1. GitHub App (one-time setup)

A GitHub App named "NetFoundry CLA" (or similar) with:
- **Permissions:** Contents (read and write)
- **Installation:** Installed on all three organizations

### 2. Organization Secrets

Each organization needs these secrets:

| Secret | Description |
|--------|-------------|
| `CLA_APP_ID` | The GitHub App's numeric ID |
| `CLA_APP_PRIVATE_KEY` | The GitHub App's private key (PEM format) |

## Adding a New Organization

To enable CLA checks for a new organization (e.g., openziti, openziti-test-kitchen):

### Step 1: Install the GitHub App

1. Go to the GitHub App settings: https://github.com/organizations/netfoundry/settings/apps
2. Click on the CLA app
3. Click "Install App" in the left sidebar
4. Select the organization to install on
5. Choose repository access:
   - "All repositories" (recommended) - automatically covers new repos
   - Or select specific repositories

### Step 2: Add Organization Secrets

1. Go to Organization Settings → Secrets and variables → Actions
2. Click "New organization secret"
3. Add `CLA_APP_ID`:
   - Name: `CLA_APP_ID`
   - Value: (the App ID from the GitHub App settings page)
   - Repository access: "All repositories" or select specific ones
4. Add `CLA_APP_PRIVATE_KEY`:
   - Name: `CLA_APP_PRIVATE_KEY`
   - Value: (the private key PEM content, including BEGIN/END lines)
   - Repository access: Same as above

### Step 3: Add Workflow to Repositories

**This is all you need to do per repo** - just copy one file:

```
workflow-template/cla.yml  →  .github/workflows/cla.yml
```

The workflow is minimal (just calls the reusable workflow in this repo). All logic lives in `netfoundry/cla`, so updates happen in one place:

```yaml
name: "CLA Check"
on:
  issue_comment:
    types: [created]
  pull_request_target:
    types: [opened, closed, synchronize]

permissions:
  actions: write
  contents: read
  pull-requests: write
  statuses: write

jobs:
  cla:
    uses: netfoundry/cla/.github/workflows/cla-workflow.yml@main
    secrets:
      CLA_APP_ID: ${{ secrets.CLA_APP_ID }}
      CLA_APP_PRIVATE_KEY: ${{ secrets.CLA_APP_PRIVATE_KEY }}
```

**Using gh CLI to add to multiple repos:**

```bash
for repo in repo1 repo2 repo3; do
  gh repo clone "openziti/$repo" "/tmp/$repo"
  mkdir -p "/tmp/$repo/.github/workflows"
  cp workflow-template/cla.yml "/tmp/$repo/.github/workflows/cla.yml"
  cd "/tmp/$repo"
  git add .github/workflows/cla.yml
  git commit -m "Add CLA check workflow"
  git push
  cd -
done
```

## Testing

1. Add the workflow to a test repository
2. Create a PR from an account that hasn't signed the CLA
3. Verify the bot comments asking for a signature
4. Sign by commenting: `I have read the CLA Document and I hereby sign the CLA`
5. Verify the signature appears in the versioned `cla.json` (e.g., `v1.1/cla.json`) in this repo
6. Verify the PR status check passes

## Organization Members

The workflow automatically skips the CLA check for organization members and owners. Employees don't need to sign - their contributions are covered by their employment agreement.

## Bot Allowlist

These accounts bypass the CLA check:
- `dependabot[bot]`
- `renovate[bot]`
- `github-actions[bot]`

To add additional users (e.g., contractors not in the org), either:
- Add them to the allowlist in `cla-workflow.yml`
- Or add them directly to the current version's `cla.json`

## CLA Documents

The workflows link to the official NetFoundry CLA PDFs:
- **Individual CLA:** https://github.com/netfoundry/cla/raw/main/v1.1/NetFoundry-ICLA-v1.1.pdf
- **Corporate CLA:** https://netfoundry.io/docs/assets/files/NetFoundry-CCLA-a68e768031f697589e7d435f17e0cf31.pdf

If these URLs change, update the `path-to-document` value in `cla-workflow.yml`.

## Updating the CLA Version

When you release a new version of the ICLA (e.g., v1.2, v2.0), you can force all contributors to re-sign. No changes are needed in any other repository - the reusable workflow handles everything centrally.

1. Add the new PDF to a new version directory (e.g., `v2.0/NetFoundry-ICLA-v2.0.pdf`)
2. Update two lines in `.github/workflows/cla-workflow.yml`:
   ```yaml
   path-to-signatures: 'v2.0/cla.json'
   path-to-document: 'https://github.com/netfoundry/cla/raw/main/v2.0/NetFoundry-ICLA-v2.0.pdf'
   ```
3. Commit and push to `main`

The new version directory and `cla.json` file will be created automatically when the first contributor signs. Since the new `cla.json` starts empty, every contributor will be prompted to re-sign.

Previous signatures are preserved in their version directories (e.g., `v1.1/cla.json`) as a historical record.

## Troubleshooting

**"Failed to create token for cla: Not Found"**
- The GitHub App is not installed on the organization
- Or the App doesn't have access to the `netfoundry/cla` repository
- Go to the App's installation settings and ensure `cla` is included

**"Resource not accessible by integration"**
- The `CLA_APP_ID` or `CLA_APP_PRIVATE_KEY` secrets are missing
- Or the secrets aren't accessible to the repository running the workflow
- Check organization secret settings and repository access

**Bot doesn't comment on PRs**
- Check that the workflow file is in `.github/workflows/cla.yml`
- Check the Actions tab for workflow run errors
- Ensure `pull_request_target` trigger is present (not just `pull_request`)

**Signatures not being recorded**
- The GitHub App needs Contents (read and write) permission on `netfoundry/cla`
- Check that the App is installed with access to the `cla` repository
