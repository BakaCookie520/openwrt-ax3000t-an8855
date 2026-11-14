# ADR 0005: upstream-gated builds and upstream-versioned stable Releases

- Date: 2026-11-14
- Status: accepted

## Context

Mainline compiled unconditionally every day and stable compiled monthly.
The release workflow listened to snapshot builds and used semantic-release,
which disagreed with firmware versioning and repeatedly failed after generating
release commits. Existing public `v1.x` releases have no firmware attachments.
Changing cadence must not mistake a skipped build's successful workflow result
for validated firmware.

## Decision

- Poll mainline at `17 */6 * * *` and formal stable releases at `37 */6 * * *`.
  Resolve the source once, including peeled annotated tags, and build that SHA.
  Stable selection is numeric across all release pages, excluding drafts/RCs.
- Skip only scheduled builds with a matching successful record. Use small
  official Actions cache records isolated by channel, upstream SHA, run ID and
  attempt. Record after the actual build job and artifact upload succeed; verify
  the recorded default-branch run and actual build job before skipping.
  PRs never write trusted success records. Manual builds and mainline push/PR
  builds remain unconditional. Cache loss permits a conservative rebuild;
  lookup failures never silently reuse old sources. Feed-only changes do not
  trigger polling builds.
- Serialize each channel's default-branch builds without canceling active work.
  Keep PR concurrency separate. Keep compilation permissions read-only.
- Publish only trusted default-branch stable builds. Bind artifacts to their
  run/attempt and include `BUILD-METADATA.json` with upstream and repository
  provenance. Verify complete inventory, checksums, board, image size and ABI
  before any release mutation.
- Use the upstream stable tag as the Release version. The owner explicitly
  selected replacing attachments on the same Release, not revision suffixes.
  Keep the Release draft throughout upload/verification; leave failures draft.
  Preserve first-build Git tag targets and show actual rebuild commits in the
  notes and metadata. Reject stale runs; repeated publication is idempotent.
  Only the highest published formal stable version is Latest.
- Give the publisher only `actions: read` and `contents: write`. A manual retry
  must name a successful stable build run and passes the same validation.
  Remove semantic-release configuration and automated changelog commits;
  preserve historical tags, releases and committed changelog content.

## Consequences

An unchanged check still appears in Actions, but performs no compilation.
Success records and 90-day firmware artifacts are not permanent archives.
Expired artifacts require rebuilding; publication failures can otherwise be
retried without compiling. A manual-only `legacy_version` migration accepts
unexpired pre-metadata stable artifacts from successful first attempts, after
verifying original checksums, board/ABI/size, image filenames, package repository
version and the upstream tag's commit. Reconstructed provenance is explicitly
marked and added only to the staged release, retaining the original checksum
manifest's digest. Automatic publication never falls back to legacy artifacts.

On 2026-11-14 the still-deployed old semantic-release workflow reported no prior
reachable version, then failed creating the already-existing `v1.0.0` tag.
The replacement was still in unmerged PR #7, so this was not a failure of the
new publisher. Migration permits testing the replacement with existing stable
firmware rather than initiating another build.

Same-version download contents deliberately change, and updates temporarily hide
the Release as draft. Consumers must verify the current checksum manifest and
machine-readable provenance, not infer the rebuild commit from the fixed tag.
Immutable releases are incompatible with the selected replacement policy.
Published checksums cover only published attachments, excluding `build.log`.

This supersedes the daily cadence in ADR 0003, not its strict patch/source safety
rules. Existing image-size, recovery and kernel ABI gates remain unchanged.
