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

## License

Shatl's first-party source code is licensed under
[GNU GPL version 3 only](LICENSE). Third-party components remain under their
respective licenses.

The Shatl name, wordmark, logomark, and application icon are governed by the
separate [brand and trademark policy](TRADEMARKS.md). The GPL license does not
grant permission to present modified software as an official Shatl release.

## Third-party software

See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
