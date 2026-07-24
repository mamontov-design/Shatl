# Shatl

Shatl is a native BitTorrent client for macOS, built with SwiftUI and libtorrent.

The project is currently being prepared for its first public release.

## Requirements

- Apple silicon Mac
- macOS 27 or later
- Xcode 27 or later

## Building

1. Clone the repository.
2. Open `Shatl.xcodeproj`.
3. Select the `Shatl` scheme and build for My Mac.

Prebuilt arm64 dependencies are stored in `Vendor/Artifacts`. To rebuild OpenSSL
and libtorrent, run `Scripts/build-openssl.sh` followed by
`Scripts/build-libtorrent.sh`.

## Privacy

Anonymous usage statistics are opt-in. Diagnostic file logging is disabled by
default and cannot be activated in release builds.

## Third-party software

See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
