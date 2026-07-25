#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2026 Mamontov Design
# SPDX-License-Identifier: GPL-3.0-only

set -euo pipefail

# Builds static libtorrent libraries into local vendored artifacts.
# This keeps normal Xcode builds independent from Homebrew paths.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

LIBTORRENT_VERSION="2.0.11"
LIBTORRENT_ARCHIVE_NAME="libtorrent-rasterbar-${LIBTORRENT_VERSION}.tar.gz"
LIBTORRENT_SOURCE_URL="https://github.com/arvidn/libtorrent/releases/download/v${LIBTORRENT_VERSION}/${LIBTORRENT_ARCHIVE_NAME}"

SOURCE_ARCHIVE_PATH="${ROOT_DIR}/Vendor/Sources/${LIBTORRENT_ARCHIVE_NAME}"
SOURCE_ROOT_DIR="${ROOT_DIR}/.build/vendor-src"
SOURCE_DIR="${SOURCE_ROOT_DIR}/libtorrent-rasterbar-${LIBTORRENT_VERSION}"
BUILD_DIR="${ROOT_DIR}/.build/vendor-build/libtorrent-rasterbar-${LIBTORRENT_VERSION}"
INSTALL_DIR="${ROOT_DIR}/Vendor/Artifacts/libtorrent/macos-arm64"
OPENSSL_INSTALL_DIR="${ROOT_DIR}/Vendor/Artifacts/openssl/macos-arm64"
BOOST_INCLUDE_DIR="${ROOT_DIR}/Vendor/Artifacts/boost/include"

LOCAL_CMAKE_BIN="${ROOT_DIR}/.build/python-tools/cmake/data/bin/cmake"
LOCAL_NINJA_BIN="${ROOT_DIR}/.build/python-tools/bin/ninja"

log() {
  printf '\n[%s] %s\n' "build-libtorrent" "$1"
}

require_file() {
  local path="$1"
  if [[ ! -e "${path}" ]]; then
    echo "Required file not found: ${path}" >&2
    exit 1
  fi
}

build_openssl_if_needed() {
  if [[ -f "${OPENSSL_INSTALL_DIR}/lib/libssl.a" && -f "${OPENSSL_INSTALL_DIR}/lib/libcrypto.a" && -f "${OPENSSL_INSTALL_DIR}/include/openssl/ssl.h" ]]; then
    log "Vendored OpenSSL is ready: ${OPENSSL_INSTALL_DIR}"
    return
  fi

  log "Vendored OpenSSL not found; building OpenSSL"
  "${ROOT_DIR}/Scripts/build-openssl.sh"
}

find_cmake() {
  if [[ -x "${LOCAL_CMAKE_BIN}" ]]; then
    printf '%s' "${LOCAL_CMAKE_BIN}"
    return
  fi

  if command -v cmake >/dev/null 2>&1; then
    command -v cmake
    return
  fi

  cat >&2 <<'EOF'
Unable to find cmake.
Expected path:
  .build/python-tools/cmake/data/bin/cmake

Prepare a local toolchain with:
  python3 -m pip download cmake ninja -d .build/tool-downloads
  python3 -m pip install --no-index --find-links .build/tool-downloads --target .build/python-tools cmake ninja
EOF
  exit 1
}

find_ninja() {
  if [[ -x "${LOCAL_NINJA_BIN}" ]]; then
    printf '%s' "${LOCAL_NINJA_BIN}"
    return
  fi

  if command -v ninja >/dev/null 2>&1; then
    command -v ninja
    return
  fi

  cat >&2 <<'EOF'
Unable to find ninja.
Expected path:
  .build/python-tools/bin/ninja
EOF
  exit 1
}

download_sources_if_needed() {
  mkdir -p "${ROOT_DIR}/Vendor/Sources"

  if [[ -f "${SOURCE_ARCHIVE_PATH}" ]]; then
    log "Source archive already exists: ${SOURCE_ARCHIVE_PATH}"
    return
  fi

  log "Downloading libtorrent ${LIBTORRENT_VERSION} sources"
  curl -L "${LIBTORRENT_SOURCE_URL}" -o "${SOURCE_ARCHIVE_PATH}"
}

extract_sources() {
  log "Extracting sources"
  rm -rf "${SOURCE_DIR}" "${BUILD_DIR}"
  mkdir -p "${SOURCE_ROOT_DIR}" "${ROOT_DIR}/.build/vendor-build"
  tar -xzf "${SOURCE_ARCHIVE_PATH}" -C "${SOURCE_ROOT_DIR}"
}

configure_and_build() {
  local cmake_bin="$1"
  local ninja_bin="$2"

  log "Configuring CMake"
  "${cmake_bin}" \
    -S "${SOURCE_DIR}" \
    -B "${BUILD_DIR}" \
    -G Ninja \
    -DCMAKE_MAKE_PROGRAM="${ninja_bin}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" \
    -DBUILD_SHARED_LIBS=OFF \
    -Dpython-bindings=OFF \
    -Dpython-egg-info=OFF \
    -Dbuild_tests=OFF \
    -Dbuild_examples=OFF \
    -Dbuild_tools=OFF \
    -DOPENSSL_ROOT_DIR="${OPENSSL_INSTALL_DIR}" \
    -DOPENSSL_USE_STATIC_LIBS=TRUE \
    -DBOOST_INCLUDEDIR="${BOOST_INCLUDE_DIR}" \
    -DBoost_INCLUDE_DIR="${BOOST_INCLUDE_DIR}" \
    -DBoost_NO_SYSTEM_PATHS=TRUE

  log "Building and installing libtorrent"
  "${cmake_bin}" --build "${BUILD_DIR}" --target install -j 8
}

write_metadata() {
  log "Updating vendored artifact metadata"
  cat > "${ROOT_DIR}/Vendor/Artifacts/VENDOR-METADATA.md" <<EOF
# Vendored Artifacts

Last updated: $(date '+%Y-%m-%d %H:%M:%S %z')

## libtorrent

- Version: ${LIBTORRENT_VERSION}
- Source: ${LIBTORRENT_SOURCE_URL}
- Linkage: static
- Artifact: \`Vendor/Artifacts/libtorrent/macos-arm64/lib/libtorrent-rasterbar.a\`

## OpenSSL

- Source: vendored static build produced by \`Scripts/build-openssl.sh\`
- Artifact root: \`Vendor/Artifacts/openssl/macos-arm64\`
- Artifacts:
  - \`Vendor/Artifacts/openssl/macos-arm64/lib/libssl.a\`
  - \`Vendor/Artifacts/openssl/macos-arm64/lib/libcrypto.a\`
  - \`Vendor/Artifacts/openssl/macos-arm64/include/openssl/\`

## Notes

Normal application builds and vendored artifact rebuilds do not depend on Homebrew paths.
Rebuilds use vendored OpenSSL artifacts and a local CMake/Ninja toolchain.
EOF
}

main() {
  require_file "${BOOST_INCLUDE_DIR}/boost/version.hpp"

  local cmake_bin
  local ninja_bin

  cmake_bin="$(find_cmake)"
  ninja_bin="$(find_ninja)"

  build_openssl_if_needed
  download_sources_if_needed
  extract_sources
  configure_and_build "${cmake_bin}" "${ninja_bin}"
  write_metadata

  log "Done: vendored static libtorrent artifacts are up to date"
}

main "$@"
