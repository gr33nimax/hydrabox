# Keep file present so release minification/shrinking has an explicit project rules file.
# Consumer rules from bundled AARs are still applied automatically.

# Legacy Happ native crypt5 bridge is excluded from build now; keep these rules
# commented as a breadcrumb in case the old bridge is ever re-enabled.
# -keep class su.happ.proxyutility.** { *; }
# -keep class com.happproxy.util.protection.** { *; }
# -keep class com.etonify.meow_client.happcrypto.** { *; }
