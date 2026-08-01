# Security Policy

HydraBox is an early Android-first VPN client and an independent, unofficial
derivative of [Etonify](https://github.com/yamixdev/Etonify). HydraBox-specific
reports must not be presented to Etonify or MeowTeam as if HydraBox were their
official release.

## Reporting a Vulnerability

Please report security issues through this repository:

- Prefer GitHub's private vulnerability-reporting form in the repository's
  **Security** tab when it is enabled.
- If private reporting is unavailable, open an issue containing only a short,
  non-exploitable summary and ask the HydraBox maintainers for a private
  channel. Do not attach secrets, working exploits, or sensitive logs.

If a problem also reproduces in an unmodified Etonify build, it may be reported
separately through Etonify's own channels. Those channels are upstream contacts,
not HydraBox support.

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
