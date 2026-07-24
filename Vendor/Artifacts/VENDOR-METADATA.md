# Vendored Artifacts

Last updated: 2026-04-11 19:55:44 +0700

## libtorrent

- Version: 2.0.11
- Source: https://github.com/arvidn/libtorrent/releases/download/v2.0.11/libtorrent-rasterbar-2.0.11.tar.gz
- Linkage: static
- Artifact: `Vendor/Artifacts/libtorrent/macos-arm64/lib/libtorrent-rasterbar.a`

## OpenSSL

- Version: 3.6.1
- Source: vendored static build produced by `Scripts/build-openssl.sh`
- Artifact root: `Vendor/Artifacts/openssl/macos-arm64`
- Artifacts:
  - `Vendor/Artifacts/openssl/macos-arm64/lib/libssl.a`
  - `Vendor/Artifacts/openssl/macos-arm64/lib/libcrypto.a`
  - `Vendor/Artifacts/openssl/macos-arm64/include/openssl/`

## Notes

Normal application builds and vendored artifact rebuilds do not depend on Homebrew paths.
Rebuilds use vendored OpenSSL artifacts and a local CMake/Ninja toolchain.
