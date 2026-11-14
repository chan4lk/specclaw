---
description: Use when a build is finished and the user asks whether it is done or passes.
---

**Flow check:** run `specclaw-ensure-init .specclaw && specclaw-flow .specclaw`. If it prints `full`, read `$CLAUDE_PLUGIN_ROOT/references/full/verify.md` and follow it instead of this file.

# specclaw verify (lean)

1. `specclaw-validate-change .specclaw <change> verify`. Stop if it fails.
2. Run the configured test, lint and build commands (`config.yaml`, or the project's standard ones); record each command and exit code. Each of these is a FAIL on any non-zero exit:
   - `specclaw-preset-check .`: its JSON lists each violation.
   - `specclaw-quality-scan . --gate`: name the `high` functions and duplicates; exit 2 means a tool did not run.
   - `specclaw-verify size .specclaw <change>`: exit 1 is over `pr.size_cap` with no `Size waiver:` line, exit 2 could not count. Record its line, including any split note.
3. Screenshots, saved under `.specclaw/changes/<change>/shots/`:
   - Start the app if the change has a UI.
   - Run `specclaw-screenshot <app-url> …/shots/app.png` and `specclaw-screenshot .specclaw/mock/index.html#<change> …/shots/mock.png`.
   - **Exit 3** (Playwright unavailable): give the user both locations and ask them to compare by eye. Record `compared by eye: <name>` only after they answer.
   - **Never record a pass without a screenshot or a human comparison.**
3b. **Local review.** When `command -v specclaw-review` succeeds, run the review loop from the `specclaw-review:review` skill until `specclaw-review verdict --change <change>` exits 0. Record its one-line output under `## Verify`. A non-zero verdict is a FAIL. Otherwise run `specclaw-suggest .specclaw review` and show any line it prints, at most once per session; if the user says no, run `specclaw-suggest .specclaw --dismiss review`.
4. Under `## Verify` in `change.md`, write:
   - `**Verdict:** PASS` or `FAIL` on the first line
   - one `- AC-n: pass|fail — <evidence>` line per criterion
   - the commands run and the screenshot paths
5. `specclaw-set-phase .specclaw <change> verify done` (or `failed`), then `specclaw-update-status .specclaw`. On PASS, the next step is `/specclaw:pr`. On FAIL, fix with `/specclaw:build` and re-verify.
