# Third-Party Notices

This file records third-party material copied into the source tree, local
dependencies, and the Android runtime bundled with HydraBox. Each component
remains subject to its own license; application and runtime lineage are indexed
in [CREDITS.md](CREDITS.md).

## Flutter predictive-back transition

`lib/theme/predictive_back_page_transitions.dart` is adapted from Flutter's
`predictive_back_page_transitions_builder.dart`.

Copyright 2014 The Flutter Authors. All rights reserved.

Flutter's BSD 3-Clause License:

```text
Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google Inc. nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## flutter_circle_flags

`third_party/flutter_circle_flags` is a local dependency derived from
`circle_flags`. It is distributed under the MIT License. Its complete license
is retained at `third_party/flutter_circle_flags/LICENSE`.

## HydraCore runtime lineage

HydraCore is the Android libbox runtime used by HydraBox. Its `hydracore`
submodule is maintained at
[`gr33nimax/hydracore`, branch `main`](https://github.com/gr33nimax/hydracore/tree/main),
based on
[`shtorm-7/sing-box-extended`, branch `extended`](https://github.com/shtorm-7/sing-box-extended/tree/extended),
and is licensed under GPL-3.0-or-later; see `hydracore/LICENSE` and the
licenses of its dependencies. The Android AAR is built from that source,
published as a pinned core release asset, and its provenance is recorded under
`android/app/libs`. Historical mobile-integration lineage remains recorded in
the source history and machine-readable provenance.

## qWDTT VK captcha automation

The Android VK Smart Captcha checkbox strategy is adapted from
[`SpaceNeuroX/proxy-turn-vk-android`](https://github.com/SpaceNeuroX/proxy-turn-vk-android),
licensed under GPL-3.0. HydraBox uses it only for the automatic checkbox stage;
interactive slider challenges fall back to a visible browser.

## Other dependencies

Flutter, Android Gradle Plugin, Kotlin, Gradle plugins, and Dart/Android
dependencies retain their respective licenses. They are declared in
`pubspec.yaml`, Gradle build files, and generated lock files.
