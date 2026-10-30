# PLAN: CI/CD Pipeline for OpenWrt AX3000T-AN8855

**Task ID**: 20260821-ci-cd-pipeline
**Task Type**: feature
**Title**: GitHub Actions CI/CD Pipeline with semantic-release and VERIFIED_COMMIT auto-update
**Base Commit**: 1c5eff5 (HEAD)
**Branch**: master
**Created At**: 2026-08-21
**Expires At**: 2026-08-28

---

> Historical plan: current package/profile and target policy is recorded in
> `docs/adr/0002-argon-xinfc-and-target-guards.md`. This is not an active build specification.

## Objective

Implement a complete CI/CD pipeline using GitHub Actions that:
1. Builds the AN8855 firmware and matching native packages
2. Runs scheduled nightly builds against OpenWrt main
3. Supports patched mainline and dynamic stable builds
4. Automates releases via semantic-release (Conventional Commits → version → tag → release)
5. Auto-updates VERIFIED_COMMIT on successful master builds
6. Uploads artifacts to workflow (90-day) and GitHub Releases

---

## Acceptance Criteria

- [ ] Scheduled nightly build runs via cron (02:00 UTC daily)
- [ ] semantic-release creates version tag and GitHub Release on conventional commits to master
- [ ] VERIFIED_COMMIT updated in repo (patches/VERIFIED_COMMIT) after successful master build
- [ ] Image size validation (scripts/check-image-size.sh STRICT=1) runs and gates build success
- [ ] All workflows pass on test pushes

---

## Read Scope

- `.github/workflows/` (existing workflows - none currently)
- `setup.sh` (build script to understand build steps)
- `scripts/check-image-size.sh` (validation script)
- `patches/VERIFIED_COMMIT` (commit locking mechanism)
- `patches/0001-add-an8855-target.patch` (patch applicability)
- `patches/mt7981b-xiaomi-mi-router-ax3000t-an8855.dts` (DTS file)
- `.gitignore` (to ensure workflow artifacts not committed)
- `package.json` / `package-lock.json` (for semantic-release if needed)

---

## Write Scope

- `.github/workflows/ci.yml` - Main CI workflow (push/PR, scheduled, multi-branch)
- `.github/workflows/release.yml` - Release workflow (semantic-release)
- `.releaserc.json` or `release.config.js` - semantic-release configuration
- `scripts/update-verified-commit.sh` - Script to update VERIFIED_COMMIT from CI
- `.github/dependabot.yml` - Optional: dependabot for action updates
- `README.md` / `DEVELOPMENT.md` - Documentation updates for CI/CD usage
- `.agent/state.yaml` - Updated auth scope and task status

---

## Forbidden Paths

- `.env*`
- `**/secrets/**`
- `**/migrations/**`
- `package.json` (only if adding semantic-release deps - will be explicit)
- `lockfiles`
- `openwrt-ax3000t/` (build directory - gitignored)
- `bin/` (build output - gitignored)

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| GitHub Actions build timeout (6h) on busy runners | Low | Medium | Set explicit timeout-minutes: 180; monitor; add ccache caching |
| VERIFIED_COMMIT auto-update requires git push from CI | Medium | High | Use GITHUB_TOKEN with contents:write; test in fork first; add failure notification via workflow status |
| semantic-release creates unexpected versions | Low | Medium | Document commit convention; use --dry-run first; configure release rules explicitly |
| Patch drift on OpenWrt main breaks nightly build | High | High | Nightly build will fail fast; alert via workflow failure; manual VERIFIED_COMMIT update needed |

---

## Validation Commands

```bash
# Syntax check workflow files
yamllint .github/workflows/*.yml || true

# Validate semantic-release config
npx semantic-release --dry-run --no-ci 2>&1 | head -50

# Test update-verified-commit script locally (dry-run)
bash scripts/update-verified-commit.sh --dry-run

# Check image size script works
bash scripts/check-image-size.sh /tmp/test-dir 2>&1 || true

# Verify git push permissions in CI (simulate)
git status
```

**Expected Validation Result**: All syntax checks pass; semantic-release dry-run shows expected version; scripts execute without errors.

---

## Budgets

- **Max Changed Files**: 8
- **Max Diff Lines**: 800
- **Max Fix Rounds**: 3
- **Max Tool Calls**: 30

---

## Rollback Strategy

- `git revert <commit>` for any workflow/config commit
- Disable workflows via GitHub Actions UI (Settings → Actions → Workflows → Disable)
- VERIFIED_COMMIT can be manually reverted: `git checkout HEAD~1 -- patches/VERIFIED_COMMIT`

---

## L2 Actions Requiring Separate Confirmation

The following actions will occur **during workflow execution** (not during implementation) and require explicit confirmation before enabling:

| Action | Impact | Target | Command | Rollback |
|--------|--------|--------|---------|----------|
| semantic-release creates git tag | Creates permanent version tag in repo | Remote repo (tags) | `npx semantic-release` (in release workflow) | `git tag -d <tag> && git push origin :refs/tags/<tag>` |
| semantic-release creates GitHub Release | Publishes release with artifacts | GitHub Releases | `npx semantic-release` | Delete release via GitHub UI/API |
| VERIFIED_COMMIT auto-commit | Commits new SHA to patches/VERIFIED_COMMIT | Remote repo (master branch) | `git commit && git push` (in CI workflow) | `git revert <commit>` |
| Workflow artifact upload | Stores build artifacts (90-day) | GitHub Actions storage | `actions/upload-artifact` | Auto-expires; manual delete via UI |
| Release artifact attachment | Attaches firmware/APK to GitHub Release | GitHub Releases | `actions/upload-release-asset` | Delete release assets via UI |

**These L2 actions are gated by:**
1. Workflow must pass all build/validation steps
2. For releases: only triggers on push to master with conventional commit
3. For VERIFIED_COMMIT: only on successful master branch build (not PR)
4. **Explicit user confirmation required before merging this PR** to enable these workflows

---

## Documentation Impact

- **Level**: DOC_README + DOC_DOCS
- **Reason**: New CI/CD pipeline adds user-visible workflows (how to trigger builds, interpret results, release process). Requires updates to DEVELOPMENT.md (CI/CD section) and README.md (badges, build status).
- **Reviewed**: false (doc-maintenance will set true post-execution)

---

## Implementation Phases

### Phase 1: Core CI Workflow (`.github/workflows/ci.yml`)
- Push/PR trigger on master
- Scheduled cron (02:00 UTC daily)
- Patched mainline snapshot plus independent dynamic stable workflow
- Build steps mirroring setup.sh
- Image size validation
- Artifact upload (workflow artifacts)

### Phase 2: VERIFIED_COMMIT Auto-Update (`scripts/update-verified-commit.sh`)
- Extract current OpenWrt commit SHA after successful build
- Update patches/VERIFIED_COMMIT
- Commit and push (only on master, not PR)

### Phase 3: semantic-release Configuration (`.releaserc.json`)
- Conventional Commits analysis
- Release on master branch only
- GitHub Release with generated notes
- Asset upload (firmware + APK)

### Phase 4: Release Workflow (`.github/workflows/release.yml`)
- Triggers on push to master
- Runs semantic-release
- Handles authentication via GITHUB_TOKEN

### Phase 5: Documentation Updates
- DEVELOPMENT.md: CI/CD usage section
- README.md: Build status badges, CI/CD overview

---

## Commit Required

Yes - all implementation files committed to feature branch, then PR to master.

---

## Stop Conditions

- Any workflow syntax error
- semantic-release dry-run fails
- Build exceeds 180 minutes in test run
- VERIFIED_COMMIT update script fails locally
- User does not confirm L2 actions before merge
