# HydraBox roadmap

HydraBox is the subscription-first client of the Hydra self-hosted VPN stack.

## Now: stable Hydra Subscription v2

- Make the HYDRA Ultimate → encrypted subscription → HydraBox flow predictable.
- Keep import, refresh, anti-rollback, redaction, and invalid-response behavior
  fail-closed.
- Keep resources independent and make profile switching deterministic.
- Use HydraCore runtime events and managed URL-test sessions efficiently.
- Keep Android VPN lifecycle, network handoffs, DNS, split tunneling, and server
  switching stable during long-running use.
- Publish signed Android releases with checksums and reproducible HydraCore
  provenance.

## Next: self-hosted experience

- Publish an explicit HYDRA Ultimate, HydraBox, and HydraCore compatibility
  matrix.
- Improve first-run diagnostics without exposing subscription secrets.
- Add clear server-side examples and recovery guidance for self-hosters.
- Define stable update and rollback windows for client/runtime pairs.
