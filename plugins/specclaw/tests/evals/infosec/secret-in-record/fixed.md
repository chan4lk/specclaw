# T3 — Call the status API

Added `lib/status.js`, which reads the build status from the CI API.

## Verification

Command: curl -s -H "Authorization: Bearer $CI_TOKEN" https://ci.example.com/api/status
Exit: 0
Output (tail):
{"state":"passing"}
