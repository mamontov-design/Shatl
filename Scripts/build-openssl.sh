#!/usr/bin/env bash

set -euo pipefail

# Builds static OpenSSL libraries into the project's vendored artifacts.
# This keeps the libtorrent rebuild pipeline independent from Homebrew.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

OPENSSL_VERSION="${OPENSSL_VERSION:-3.6.1}"
OPENSSL_ARCHIVE_NAME="openssl-${OPENSSL_VERSION}.tar.gz"
OPENSSL_SOURCE_URL="https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/${OPENSSL_ARCHIVE_NAME}"

SOURCE_ARCHIVE_PATH="${ROOT_DIR}/Vendor/Sources/${OPENSSL_ARCHIVE_NAME}"
SOURCE_ROOT_DIR="${ROOT_DIR}/.build/vendor-src"
SOURCE_DIR="${SOURCE_ROOT_DIR}/openssl-${OPENSSL_VERSION}"
INSTALL_DIR="${ROOT_DIR}/Vendor/Artifacts/openssl/macos-arm64"

log() {
  printf '\n[%s] %s\n' "build-openssl" "$1"
}

require_command() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "Required command not found: ${name}" >&2
    exit 1
  fi
}

download_sources_if_needed() {
  mkdir -p "${ROOT_DIR}/Vendor/Sources"

  if [[ -f "${SOURCE_ARCHIVE_PATH}" ]]; then
    log "Source archive already exists: ${SOURCE_ARCHIVE_PATH}"
    return
  fi

  log "Downloading OpenSSL ${OPENSSL_VERSION} sources"
  curl -L "${OPENSSL_SOURCE_URL}" -o "${SOURCE_ARCHIVE_PATH}"
}

extract_sources() {
  log "Extracting OpenSSL sources"
  rm -rf "${SOURCE_DIR}"
  mkdir -p "${SOURCE_ROOT_DIR}"
  tar -xzf "${SOURCE_ARCHIVE_PATH}" -C "${SOURCE_ROOT_DIR}"
}

configure_and_build() {
  log "Configuring OpenSSL"

  rm -rf "${INSTALL_DIR}"
  mkdir -p "${INSTALL_DIR}"

  (
    cd "${SOURCE_DIR}"
    local sdk_root
    sdk_root="$(xcrun --sdk macosx --show-sdk-path)"

    export CC="${CC:-$(xcrun --find clang)}"
    export CXX="${CXX:-$(xcrun --find clang++)}"
    export SDKROOT="${SDKROOT:-${sdk_root}}"
    export CPPFLAGS="${CPPFLAGS:-} -isysroot ${SDKROOT}"
    export CFLAGS="${CFLAGS:-} -arch arm64 -isysroot ${SDKROOT}"
    export CXXFLAGS="${CXXFLAGS:-} -arch arm64 -isysroot ${SDKROOT}"
    export LDFLAGS="${LDFLAGS:-} -arch arm64 -isysroot ${SDKROOT}"

    perl ./Configure \
      darwin64-arm64-cc \
      no-shared \
      no-tests \
      no-module \
      no-apps \
      --prefix="${INSTALL_DIR}" \
      --openssldir="${INSTALL_DIR}/ssl"

    make -j "$(sysctl -n hw.ncpu 2>/dev/null || echo 8)"
    make install_sw
  )
}

write_metadata() {
  log "Updating OpenSSL metadata"
  cat > "${INSTALL_DIR}/BUILD-METADATA.md" <<EOF
# OpenSSL Build Metadata

Last updated: $(date '+%Y-%m-%d %H:%M:%S %z')

- Version: ${OPENSSL_VERSION}
- Source: ${OPENSSL_SOURCE_URL}
- Linkage: static
- Artifacts:
  - \`lib/libssl.a\`
  - \`lib/libcrypto.a\`
  - \`include/openssl/\`
EOF
}

main() {
  require_command curl
  require_command perl
  require_command make
  require_command tar
  require_command xcrun

  download_sources_if_needed
  extract_sources
  configure_and_build
  write_metadata

  log "Done: vendored OpenSSL artifacts are up to date"
}

main "$@"
