# Vendored Artifacts

Last updated: 2026-09-21 13:12:41 +0700

## libtorrent

- Version: 2.0.14
- Source: https://github.com/arvidn/libtorrent/releases/download/v2.0.14/libtorrent-rasterbar-2.0.14.tar.gz
- Source SHA-256: 1b0b21b9755b5fbec23ca9ba2d2d10434ecb6711c39f37f5fc9d5aa25cf369c9
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
