// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// What Shatl is built with, as `THIRD-PARTY-NOTICES.md` lists it. The
/// licences popover in About names each component with its licence and
/// links to that licence on the component's own site; the full texts ship
/// in the app, in `Resources/Licenses`. `ThirdPartyLicensesTests` keeps the
/// notices, the texts and this list in step: a new version of a library is
/// written here too.
nonisolated enum ShatlThirdPartyComponent: CaseIterable, Identifiable, Sendable {
    case boost
    case libtorrent
    case openSSL
    case sparkle
    case radixColors

    var id: Self { self }

    var name: String {
        switch self {
        case .boost: "Boost"
        case .libtorrent: "libtorrent"
        case .openSSL: "OpenSSL"
        case .sparkle: "Sparkle"
        case .radixColors: "Radix Colors"
        }
    }

    /// The notices give Boost no version: its headers come with libtorrent.
    var version: String? {
        switch self {
        case .boost: nil
        case .libtorrent: "2.0.14"
        case .openSSL: "3.6.1"
        case .sparkle: "2.9.2"
        case .radixColors: "3.0.0"
        }
    }

    /// The licence's own name, not translated.
    var license: String {
        switch self {
        case .boost: "Boost Software License 1.0"
        case .libtorrent: "BSD 3-Clause"
        case .openSSL: "Apache License 2.0"
        case .sparkle, .radixColors: "MIT"
        }
    }

    /// "libtorrent 2.0.14 — BSD 3-Clause", the same in every language.
    var title: String {
        [name, version].compactMap { $0 }.joined(separator: " ") + " — " + license
    }

    /// The licence on the component's own site, of our version where the
    /// site keeps one per version. Radix Colors has no version tags.
    var licenseURL: URL {
        switch self {
        case .boost:
            URL(string: "https://www.boost.org/LICENSE_1_0.txt")!
        case .libtorrent:
            URL(string: "https://github.com/arvidn/libtorrent/blob/v2.0.14/LICENSE")!
        case .openSSL:
            URL(string: "https://openssl-library.org/source/license/")!
        case .sparkle:
            URL(string: "https://github.com/sparkle-project/Sparkle/blob/2.9.2/LICENSE")!
        case .radixColors:
            URL(string: "https://github.com/radix-ui/colors/blob/main/LICENSE")!
        }
    }

    /// The licence text in `Vendor/Licenses`, copied into the app.
    var licenseFileName: String {
        switch self {
        case .boost: "Boost-LICENSE_1_0.txt"
        case .libtorrent: "libtorrent-LICENSE.txt"
        case .openSSL: "OpenSSL-LICENSE.txt"
        case .sparkle: "Sparkle-LICENSE.txt"
        case .radixColors: "Radix-Colors-LICENSE.txt"
        }
    }
}
