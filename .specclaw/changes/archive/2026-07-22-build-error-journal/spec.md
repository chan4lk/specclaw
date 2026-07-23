# Spec: Build Error Journal

**Change:** build-error-journal
**Created:** 2026-03-28
**Status:** 🟢 Approved

## Overview

Auto-capture structured error entries when build tasks fail, and feed previous errors as context when retrying tasks — so agents don't repeat the same mistakes.

## Requirements

### Functional Requirements

- **FR-1:** When a build task fails, auto-append a structured error entry to `.specclaw/changes/<change>/errors.md`
- **FR-2:** Error entries include: task ID, wave, timestamp, agent label, error output/summary, files attempted, and previous task status
- **FR-3:** On retry, `build-context.sh` includes relevant previous errors for that task in the agent's context
- **FR-4:** Limit error history in context to the last 3 attempts per task to avoid context bloat
- **FR-5:** `errors.md` persists across build attempts (append-only during builds)
- **FR-6:** When a task succeeds after previous failures, mark those error entries as `resolved_on_retry`
- **FR-7:** Provide `scripts/log-error.sh` to append entries programmatically
- **FR-8:** Error template created alongside other change files

### Non-Functional Requirements

- **NFR-1:** Error logging must not block or slow down the build pipeline
- **NFR-2:** Scripts must work with bash 5+ and standard coreutils
- **NFR-3:** Error entries must be human-readable markdown

## Acceptance Criteria

- [ ] **AC-1:** GIVEN a task agent fails WHEN the build engine processes the failure THEN an entry is appended to `errors.md` with task ID, timestamp, and error context
- [ ] **AC-2:** GIVEN a task has 2 previous failures in errors.md WHEN retrying THEN build-context.sh includes those 2 error entries in the agent context under "## Previous Errors"
- [ ] **AC-3:** GIVEN a task has 5 previous failures WHEN retrying THEN only the last 3 are included in context
- [ ] **AC-4:** GIVEN a task succeeds after failure WHEN log-error.sh is called with "resolved" THEN previous entries for that task are marked `resolved_on_retry`
- [ ] **AC-5:** GIVEN a fresh change with no errors.md WHEN first failure occurs THEN errors.md is created with header and first entry

## Edge Cases

1. No errors occur during build — errors.md not created (no empty file)
2. Multiple tasks fail in same wave — each gets its own entry
3. Agent result is empty/timeout — entry notes "timeout" or "no output"
4. errors.md already exists from previous build run — append, don't overwrite

## Dependencies

- build-context.sh (from build-engine, will be modified)
- update-task-status.sh (existing)
