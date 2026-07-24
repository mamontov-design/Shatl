# Vendor

This directory contains third-party artifacts required for reproducible Shatl builds.

Main directories:

- `Artifacts/` contains prebuilt dependencies referenced by the Xcode project.
- `Licenses/` contains the corresponding third-party license texts.
- `Sources/` is local and ignored by Git; build scripts download pinned source archives there.

Current pipeline:

- OpenSSL is built into `Vendor/Artifacts/openssl/macos-arm64/`.
- libtorrent is built into `Vendor/Artifacts/libtorrent/macos-arm64/`.
- Boost headers live in `Vendor/Artifacts/boost/include/`.

Rebuild scripts:

- `Scripts/build-openssl.sh`
- `Scripts/build-libtorrent.sh`
