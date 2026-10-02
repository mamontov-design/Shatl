# Vendor

This directory contains third-party artifacts required for reproducible Shatl builds.

Main directories:

- `Artifacts/` contains prebuilt dependencies referenced by the Xcode project.
- `Licenses/` contains the corresponding third-party license texts.
- `Sources/` is local and ignored by Git; build scripts download pinned source archives there.

Sparkle is resolved through Swift Package Manager rather than stored in
`Artifacts/`. Its complete license text is retained in `Licenses/` for release
notices.

Current pipeline:

- OpenSSL is built into `Vendor/Artifacts/openssl/macos-arm64/`.
- libtorrent is built into `Vendor/Artifacts/libtorrent/macos-arm64/`.
- Boost headers live in `Vendor/Artifacts/boost/include/`.

Boost 1.90.0 is kept to the headers that are actually included: 1,782 of
the 15,987 in the release, 12 MB instead of 179 MB. The set is the union
of the headers `LibtorrentSessionBridge.mm` includes in Debug and
Release and the headers libtorrent 2.0.14 includes when
`Scripts/build-libtorrent.sh` builds it; that script was run from scratch
against the pruned set. A libtorrent update, a new compiler flag or a new
Boost include may need headers that are gone: put the full
`boost/` folder of the same Boost release back into
`Vendor/Artifacts/boost/include/`, build libtorrent and the app, and prune
again to the union of the build's dependency files (`ninja -t deps` in
`.build/vendor-build/libtorrent-rasterbar-2.0.14` and the bridge's `.d`
files in DerivedData).

Rebuild scripts:

- `Scripts/build-openssl.sh`
- `Scripts/build-libtorrent.sh`
