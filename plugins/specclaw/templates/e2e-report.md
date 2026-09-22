# E2E Test Report: {{title}}

**Path analyzed:** {{path}}
**Date generated:** {{date}}

## Detection Summary

{{detection_summary}}

## Setup / Execution Commands

{{setup_commands}}

## Page Objects Generated

| File | Real Surface Encapsulated |
|---|---|
{{page_objects_rows}}

## Test Scripts Generated

{{test_scripts_list}}

## Execution Results

<!--
  This section is bash-owned, not agent-owned. Everything between the two
  anchors below is written and later overwritten by `specclaw-bf-e2e-run`,
  never by the agent that authored the rest of this document — the agent has
  no test results to report at write time, since the tests it just generated
  have not run yet. Never hand-edit between these anchors; the next
  `specclaw-bf-e2e-run` invocation replaces it unconditionally.
-->
<!-- e2e-report:execution-results:begin -->
{{execution_results}}
<!-- e2e-report:execution-results:end -->

## Artifacts

<!--
  Bash-owned, same rule as Execution Results. specclaw-bf-e2e-run copies
  whatever the run's on-failure screenshot/video capture wrote into
  .specclaw/e2e/artifacts/ and lists it here. Never hand-edit between these
  anchors.
-->
<!-- e2e-report:artifacts:begin -->
{{artifacts}}
<!-- e2e-report:artifacts:end -->

## Gaps

{{gaps}}
