# HydraBox roadmap

HydraBox is the subscription-first client of the Hydra self-hosted VPN stack.
The roadmap prioritizes a dependable daily client and a stable subscription
contract over adding transports for their own sake.

## Now: polish the product

- Make the HYDRA Ultimate → encrypted subscription → HydraBox flow predictable.
- Harden import, refresh, rollback, redaction, and invalid-response behavior.
- Keep Android VPN lifecycle, network changes, DNS, split tunneling, and server
  switching stable during long-running use.
- Publish signed Android releases with checksums, updater metadata, changelog,
  and reproducible HydraCore provenance.
- Complete the project page, onboarding, support, and release documentation.

## Next: self-hosted experience

- Publish an explicit HYDRA Ultimate/HydraBox subscription compatibility
  matrix.
- Improve first-run diagnostics without exposing subscription secrets.
- Add clear server-side examples and recovery guidance for self-hosters.
- Define stable update and rollback windows for HydraBox and HydraCore pairs.

## Research: optional WDTT mode

WDTT is not part of the stable HydraBox product. Existing work is preserved in
the `archive/wdtt` branch, with no release date or compatibility promise.

It may return only as an optional experimental mode after the VK relay
dependency, long-term availability, multi-user architecture, abuse model, and
operational stability are validated. The normal Hydra subscription path must
never depend on WDTT.
