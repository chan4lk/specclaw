# Security Policy

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Report privately via [GitHub Security Advisories](https://github.com/chan4lk/specclaw/security/advisories/new), or email **chan4lk@gmail.com** with the details and reproduction steps.

You'll get an acknowledgement within a few days. Once fixed, we'll credit you in the release notes unless you'd prefer to stay anonymous.

## Scope

SpecClaw runs locally as a Claude Code plugin and operates on your repo's working directory. Of particular interest:

- Credential handling in the auth flows (`/specclaw:auth-azdo`, `/specclaw:auth-jira`).
- Any path that shells out or writes outside `.specclaw/`.
- Injection into agent payloads via untrusted repo content.

## Supported versions

The latest published release receives security fixes. Older versions are not maintained.
