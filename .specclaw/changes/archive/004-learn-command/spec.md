# Spec: specclaw learn — Capture Build Learnings

**Change:** learn-command
**Created:** 2026-03-28
**Status:** 🟢 Approved

## Overview

Capture structured learnings during and after build cycles — spec gaps, design misses, patterns discovered. Learnings accumulate per change and can be promoted to improve future builds.

## Requirements

### Functional Requirements

- **FR-1:** `scripts/log-learning.sh` appends structured learning entries to `.specclaw/changes/<change>/learnings.md`
- **FR-2:** Each entry has: ID, category (spec_gap, design_gap, pattern, best_practice), priority, timestamp, detail, and suggested action
- **FR-3:** Categories: spec_gap, design_gap, pattern, best_practice, agent_issue
- **FR-4:** `log-learning.sh --list <change>` shows all learnings for a change
- **FR-5:** `log-learning.sh --promote <learning_id>` marks a learning as promoted and outputs it for inclusion in SKILL.md or agent prompts
- **FR-6:** Learnings template created for new changes
- **FR-7:** SKILL.md updated with `specclaw learn` command documentation

### Non-Functional Requirements

- **NFR-1:** Bash only, no external dependencies
- **NFR-2:** Human-readable markdown format

## Acceptance Criteria

- [ ] **AC-1:** GIVEN a change exists WHEN `log-learning.sh .specclaw change-name "spec_gap" "medium" "Tasks needed shared types"` runs THEN a structured entry is appended to learnings.md
- [ ] **AC-2:** GIVEN learnings.md has 3 entries WHEN `--list` runs THEN all 3 are shown with IDs
- [ ] **AC-3:** GIVEN a learning exists WHEN `--promote L1` runs THEN entry is marked promoted
- [ ] **AC-4:** GIVEN no learnings.md WHEN first learning logged THEN file created with template header

## Edge Cases

1. Empty category or invalid category — reject with error
2. No learnings.md yet — create on first log
3. Promote non-existent ID — error message
