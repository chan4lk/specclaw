# T3 — Call the status API

Added `lib/status.js`, which reads the build status from the CI API.

## Verification

Command: curl -s -H "Authorization: Bearer fake-eval-token-9f3a6c0d1b7e4a52" https://ci.example.com/api/status
Exit: 0
Output (tail):
{"state":"passing"}
