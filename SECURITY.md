# Security policy

HydraBox processes remote subscriptions, local secrets, network traffic, deep
links, update artifacts, and native runtime configuration. Authentication,
validation, secret handling, resource exhaustion, lifecycle, and routing bugs
may therefore be security relevant.

## Reporting

Use GitHub private vulnerability reporting when available. Otherwise open only
a short non-exploitable issue and request a private channel. Do not publish a
working exploit or attach subscription URLs, credentials, keys, tokens, device
identifiers, private addresses, or sensitive logs.

Include the affected HydraBox version or commit, Android version/device when
relevant, minimal reproduction conditions, expected behavior, and carefully
redacted diagnostics.

## Priorities

- Authenticated, fail-closed subscription import and refresh.
- No silent forwarding of device identifiers or secret headers.
- Redaction of secrets in logs, diagnostics, backups, and errors.
- Safe updater signature, package, version, and digest validation.
- Reliable VPN lifecycle, selected-profile consistency, and split routing.
- Bounded memory, concurrency, log, and cache retention.

Please allow maintainers time to investigate and prepare a fix before public
disclosure.
