---
description: Use when someone wants several related approved specclaw changes delivered together as one feature through specclaw-fleet, with dependencies, a shared feature branch and one PR to main.
---

# specclaw-fleet feature

Runs a group of related changes as one feature: children build in dependency order on `feature/<module>`, each child PR merges into that branch, and one integration run opens `feature → main`. Settings come from `fleet:` in `.specclaw/config.yaml` (see `/specclaw-fleet:setup`).

## 1. Declare

Each child's `proposal.md` (or `change.md` in the lean flow) carries:

```
**Feature:** catalog
**Depends on:** 002-catalog-shell, 003-product-detail
```

`**Depends on:**` may be `none`. Edit these lines through the change's lifecycle, never on someone's behalf.

## 2. Plan

`specclaw-fleet feature plan <module>` shows waves, each member's state (`not-opted-in`, `ready`, `waiting`, `running`, `pr_open`, `merged`, `failed`, `conflict`) and its dependencies. A cycle or a dependency outside the feature is refused; fix the proposals first.

## 3. Init and opt in (ask once)

- `specclaw-fleet feature init <module>` writes `.specclaw/features/<module>/` and creates the feature's work item. It is approved by the person running it.
- `specclaw-fleet optin <module> <member>... --dry-run`, show the plan, then run it without `--dry-run`. Every member's run, and the integration run, spends the **caller's** plan. Never opt in an item assigned to someone else.
- Commit `.specclaw/features/<module>/` and push to the base branch, asking first.

## 4. Start

`specclaw-fleet feature start <module>` creates `feature/<module>` on the remote when missing (ask first: it is a push) and queues the pipeline on it. From then on the pipeline runs `feature advance` on every push to `feature/<module>`, so each merged child PR starts whatever became ready.

- A failed child blocks only its dependents; the rest continue.
- A child whose PR conflicts with the feature branch is retried once with the feature branch merged in, then marked failed for a human.
- When every child is merged, one integration run verifies the whole feature on `specclaw/integrate-<module>` and opens the PR to the trusted branch: a real PR when it passes, a draft when it does not.

## 5. Watch and report

`specclaw-fleet feature plan <module>` at any time; `specclaw-fleet status <members>... --watch 30` while runs are active. Each child PR targets `feature/<module>` and needs a human merge (branch policies apply). Report the waves, each child's PR or `exit=` reason, and the integration PR when it exists.
