# Security Policy

Etonify is an early Android-first VPN client, so security reports are important to the project.

## Reporting a Vulnerability

Please report security issues through one of these channels:

- GitHub issue with limited public detail, if the issue is not immediately exploitable.
- Telegram channel/contact path: [@etonify](https://t.me/etonify).

Please do not publish exploit details publicly before the team has time to investigate and prepare a fix.

## What to Include

- Affected version or commit.
- Android version and device model, if relevant.
- Clear reproduction steps.
- Logs or screenshots, with subscription URLs, UUIDs, passwords, tokens, HWID, and IP addresses removed.
- Expected and actual behavior.

## Project Security Priorities

- No silent forwarding of HWID or device identifiers.
- Redaction of secrets in logs and exported diagnostics.
- Safe subscription refresh and deep-link import behavior.
- Reliable VPN service start/stop and selected-server consistency.
- Bounded memory/log/cache retention for daily use.

We try to respond constructively and are open to responsible disclosure, patches, and hard technical feedback.
