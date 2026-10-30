# Task ID
20260821-health-check-status

# Task Type
feature

# Status
planning

# Objective
Add a 'health-check' subcommand to setup.sh that reports basic project info: version (from VERIFIED_COMMIT), build date, config summary (key CONFIG_ options from setup.sh).

# Acceptance Criteria
- `bash setup.sh health-check` executes without error (exit code 0)
- Output includes OpenWrt commit SHA from patches/VERIFIED_COMMIT
- Output includes build date (ISO 8601 format)
- Output includes config summary (target, luci, tailscale, key kmods - at least 5 items)
- Existing commands still work: `bash setup.sh`, `bash setup.sh build`
- `bash -n setup.sh` passes (no syntax errors)

# Authorization Scope
- Allowed Write Paths:
  - setup.sh
- Forbidden Paths:
  - .env*
  - **/secrets/**
  - **/migrations/**
  - package.json
  - lockfiles
  - openwrt-ax3000t/**
  - bin/**
- Read Scope:
  - setup.sh
  - patches/VERIFIED_COMMIT
  - scripts/check-image-size.sh (for reference)
- Allowed Command Exceptions:
  - bash -n setup.sh (syntax check)
  - bash setup.sh health-check (test execution)

# Documentation Impact Level
# Level: DOC_README
documentation_impact:
  level: DOC_README
  reviewed: false
  reason: "New user-facing subcommand; should be documented in README.md Quick Start and DEVELOPMENT.md Common Commands"

# Evidence Read
- setup.sh (lines 38-61: argument parsing; lines 181-391: config section)
- patches/VERIFIED_COMMIT (version source)
- scripts/check-image-size.sh (output format reference)

# Plan
- Phase 1: Analyze existing argument parsing in setup.sh (lines 38-61)
- Phase 2: Add 'health-check' subcommand to argument parsing
- Phase 3: Implement health_check() function that:
  - Reads VERIFIED_COMMIT for version
  - Generates build date (current date in ISO 8601)
  - Extracts key config summary from setup.sh config heredoc
  - Optionally checks for build artifacts if they exist
- Phase 4: Add function call in main execution flow
- Phase 5: Add bash -n self-check for new code
- Phase 6: Test all existing commands + new health-check command
- Phase 7: Update README.md and DEVELOPMENT.md with new command documentation

# Verification Method
- Run: bash -n setup.sh
- Run: bash setup.sh health-check
- Run: bash setup.sh (verify prepare-only still works)
- Run: bash setup.sh build (dry-run or quick test if feasible)
- Verify output format and content

# Current Progress
Planning phase complete. Ready for implementation approval.

# Verification Results
Pending implementation.

# Blockers
None identified.

# Next Steps
Await user approval of this PLAN to proceed to implementation.