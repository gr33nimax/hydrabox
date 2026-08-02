# HydraBox Subscription v2

Status: **draft 0.3 / WDTT remote-policy profile**

Subscription v2 extends the v1 explicit-profile envelope with device-bound
runtime credentials. The product entry point remains the Hydra subscription:
users do not import WDTT links, passwords, WireGuard files, or VK relay data by
hand.

## WDTT material split

The native sing-box document contains a bounded endpoint and an opaque
reference only:

```json
{
  "type": "wdtt",
  "tag": "wdtt-primary",
  "server": "wdtt.example",
  "server_port": 4433,
  "credential_ref": "wdtt:user-id:device-id",
  "vk_hashes": ["call-1", "call-2", "call-3", "call-4"],
  "workers": 18,
  "obfs": "audio",
  "vk_auth": "auto",
  "vk_anon_path": "vkcalls"
}
```

The matching material is a top-level `credentials` entry in the decrypted JWE
plaintext:

```json
{
  "kind": "wdtt_device_grant",
  "credential_ref": "wdtt:user-id:device-id",
  "device_id": "<64 lowercase hex characters>",
  "device_grant": "hwdtt1_<43 base64url characters>"
}
```

`credentials` is rejected in plaintext transport. Every WDTT endpoint must
have exactly one matching credential and no unreferenced credential is
accepted. `device_id` must match the SHA-256 identity registered by the HYDRA
subscription request.

## Secret lifecycle

1. HYDRA returns a flattened `application/jose+json` response.
2. HydraBox authenticates and decrypts it with the `hbx-key` from the URL
   fragment.
3. HydraBox validates the endpoint, grant, device binding, and subscription
   anti-replay tuple.
4. The grant is written only to the Android Keystore-backed encrypted payload
   box. It is excluded from `Subscription.toMap()` and profile exports.
5. Immediately before runtime start or reconfiguration, HydraBox atomically
   replaces HydraCore's process-local credential set.
6. HydraCore resolves `credential_ref` in memory. The grant is never serialized
   into sing-box JSON, logs, diagnostics, or a WireGuard configuration.

Process death clears the native copy; the encrypted payload restores it on the
next cold start. Subscription expiry and server-side revocation remain
authoritative. An unlimited subscription has no artificial client expiry.

## Worker and lease contract

- minimum worker group: **9**;
- recommended steady state: **18**;
- allowed steady state: **9, 18, 27, or 36**;
- hot-rotation burst: one additional group of **9**;
- session lease TTL: **15 minutes**;
- renewal begins after **10 minutes**;
- cutover occurs after the new generation has at least **9** accepted workers;
- the old generation drains after cutover, without restarting the VPN.

These numbers are per active device connection, not a user-count limit. HYDRA
does not impose an artificial number of WDTT users. Capacity is bounded by the
operator's CPU, memory, bandwidth, VK relay availability, and an optional
explicit global worker quota.

## Compatibility

- v1 remains accepted for existing non-WDTT subscriptions;
- a trusted v1 tuple may upgrade to v2 at a monotonic sequence;
- v2 to v1 downgrade is rejected;
- WDTT activation requires HydraCore API v1 with remote policy v2 and the exact
  WDTT capability contract;
- missing, malformed, older, or wider capability manifests fail closed.

The v1 envelope and trust model remain documented in
[hydrabox-subscription-v1.md](hydrabox-subscription-v1.md).
