# libbox binary

Etonify 0.2.2 intentionally uses the same `libbox.aar` that shipped with
Etonify 0.2.1. Its SHA-256 is pinned in `libbox.sha256` and verified by CI
before Android compilation.

The exact upstream/fork commit used to produce this binary is not known. The
binary must therefore be treated as a compatibility artifact, not as a
reproducible build. Replacing it requires updating the hash and testing the
Pigeon/Kotlin API contract, Android unit tests, lint, assemble, and a device
soak test.
