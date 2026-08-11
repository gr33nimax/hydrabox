#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
core_root="${repository_root}/hydracore"
libs_root="${repository_root}/android/app/libs"

version="$(tr -d '\r\n' < "${core_root}/release/HYDRACORE_VERSION")"
if ! [[ "${version}" =~ ^v[0-9A-Za-z][0-9A-Za-z._+-]{0,126}$ ]]; then
  echo "invalid pinned HydraCore version: ${version}" >&2
  exit 1
fi

head_commit="$(git -C "${core_root}" rev-parse HEAD)"
if existing="$(git -C "${core_root}" rev-parse -q --verify "refs/tags/${version}" 2>/dev/null)" && \
   [ "${existing}" != "${head_commit}" ]; then
  echo "pinned HydraCore tag ${version} points to ${existing}, expected ${head_commit}" >&2
  exit 1
fi
git -C "${core_root}" tag -f "${version}" HEAD
export SOURCE_DATE_EPOCH="$(git -C "${core_root}" show -s --format=%ct HEAD)"
export HYDRACORE_BUILD_ROLE=client

make -C "${core_root}" lib_install
make -C "${core_root}" lib_android

test -s "${core_root}/libbox.aar"
test -s "${core_root}/libbox-sources.jar"
mkdir -p "${libs_root}"
cp "${core_root}/libbox.aar" "${libs_root}/libbox.aar"
cp "${core_root}/libbox-sources.jar" "${libs_root}/libbox-sources.jar"
(
  cd "${libs_root}"
  sha256sum libbox.aar > libbox.sha256
)
