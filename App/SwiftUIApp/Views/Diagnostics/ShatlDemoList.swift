// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

#if DEBUG
import AppKit
import Foundation

/// Debug builds only: a made-up download list to measure the list against,
/// fed by `DemoTorrentEngine` instead of libtorrent. It is picked in the Debug
/// menu; Shatl relaunches into it, in a folder of its own, and relaunches out
/// of it the same way.
nonisolated enum ShatlDemoPreset: String, CaseIterable, Identifiable, Sendable {
    case active5
    case active25
    case active50
    case active75
    case active100
    case mixed5and10
    case mixed10and15
    case mixed15and25
    case mixed20and50

    var id: Self { self }

    var activeCount: Int {
        switch self {
        case .active5, .mixed5and10: 5
        case .active25: 25
        case .active50: 50
        case .active75: 75
        case .active100: 100
        case .mixed10and15: 10
        case .mixed15and25: 15
        case .mixed20and50: 20
        }
    }

    var inactiveCount: Int {
        switch self {
        case .active5, .active25, .active50, .active75, .active100: 0
        case .mixed5and10: 10
        case .mixed10and15: 15
        case .mixed15and25: 25
        case .mixed20and50: 50
        }
    }

    /// `10+15`: active and inactive downloads.
    var logName: String {
        "\(activeCount)+\(inactiveCount)"
    }

    /// Every preset plays the same list each time, so runs compare.
    var seed: UInt64 {
        UInt64(Self.allCases.firstIndex(of: self) ?? 0) &+ 0x5EED_5A71
    }
}

@MainActor
enum ShatlDemoList {
    private static let presetKey = "ShatlDebug.demoListPreset"
    private static let preferencesSuiteName = "mamontov.design.shatl.demo"

    /// The preset this launch runs, read once: switching relaunches.
    static let activePreset: ShatlDemoPreset? = UserDefaults.standard
        .string(forKey: presetKey)
        .flatMap(ShatlDemoPreset.init(rawValue:))

    /// A fresh folder for each launch, so no demo session carries over and
    /// the data folder lock never meets the user's or the previous demo's.
    static let directories: ShatlDirectories = {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShatlDemo", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return ShatlDirectories(
            applicationSupportURL: rootURL.appendingPathComponent("ApplicationSupport", isDirectory: true),
            cachesURL: rootURL.appendingPathComponent("Caches", isDirectory: true)
        )
    }()

    /// Where the made-up downloads say they save; it exists, so no card
    /// reports a missing folder.
    static var downloadsURL: URL {
        let url = directories.applicationSupportURL.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Settings of their own, starting from the user's the first time, so a
    /// mode picked in the demo stays in the demo.
    static func preferencesStore() -> AppPreferencesStore {
        guard let defaults = UserDefaults(suiteName: preferencesSuiteName) else {
            return AppPreferencesStore()
        }
        let store = AppPreferencesStore(userDefaults: defaults)
        if defaults.object(forKey: "demoPreferencesCopied") == nil {
            store.save(AppPreferencesStore().load())
            defaults.set(true, forKey: "demoPreferencesCopied")
        }
        return store
    }

    /// Relaunches Shatl into `preset`, or out of the demo with nil.
    static func relaunch(into preset: ShatlDemoPreset?) {
        if let preset {
            UserDefaults.standard.set(preset.rawValue, forKey: presetKey)
        } else {
            UserDefaults.standard.removeObject(forKey: presetKey)
        }
        // The new copy waits for this one's folder instead of handing its
        // launch over, should both use the same folder.
        ShatlSingleInstance.setClosing(true)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
}

/// How one made-up download moves: its level of speed, its size and where it
/// stands. `DemoTorrentEngine` plays it; the list starts from `record`.
nonisolated struct DemoTransferPlan: Sendable, Equatable {
    var id: UUID
    var name: String
    var status: TorrentStatus
    var progress: Double
    var totalBytes: Int64
    /// The speed it wavers around, in bytes per second.
    var baseDownloadSpeed: Double
    var baseUploadSpeed: Double
    var seeds: Int
    var peers: Int
    var uploadedBytes: Int64

    func record(saveURL: URL) -> TorrentRecord {
        TorrentRecord(
            id: id,
            attemptID: id,
            infoHash: "demo-\(id.uuidString.prefix(8))",
            originalName: name,
            alias: nil,
            progress: progress,
            status: status,
            metrics: TorrentMetrics(
                downloadSpeedBytesPerSecond: 0,
                uploadSpeedBytesPerSecond: 0,
                etaSeconds: nil,
                seeds: nil,
                peers: nil,
                uploadedBytes: uploadedBytes,
                totalBytes: totalBytes,
                selectedBytes: totalBytes
            ),
            canonicalSavePath: saveURL.path,
            selectedFileIndices: [0],
            selectedFileRelativePaths: [name],
            selectedFileCount: 1,
            totalFileCount: 1,
            materializedSelectionFootprint: nil,
            persistentIssue: nil,
            runtimeErrorState: nil,
            lastKnownProgress: progress,
            resumeCheckpointedAt: nil,
            resumeCheckpointProgress: nil,
            stopAfterDownload: false
        )
    }
}

/// Builds the made-up list of a preset: active downloads and inactive ones
/// shared out evenly between seeding, downloaded and stopped, mixed in a
/// fixed order.
nonisolated enum DemoListFactory {
    /// A third of active speeds sit near a speed-level threshold, so levels
    /// change the way they do at real thresholds.
    static let thresholds: [Double] = [250 * 1_024, 2 * 1_048_576, 8 * 1_048_576, 25 * 1_048_576]

    static func plans(for preset: ShatlDemoPreset) -> [DemoTransferPlan] {
        var generator = DemoRandom(seed: preset.seed)
        var plans: [DemoTransferPlan] = []
        let inactiveStatuses: [TorrentStatus] = [.seeding, .completed, .stopped]

        for index in 0..<preset.activeCount {
            plans.append(activePlan(index: index, generator: &generator))
        }
        for index in 0..<preset.inactiveCount {
            let status = inactiveStatuses[index % inactiveStatuses.count]
            plans.append(inactivePlan(index: preset.activeCount + index, status: status, generator: &generator))
        }
        plans.shuffle(using: &generator)
        return plans
    }

    private static func activePlan(index: Int, generator: inout DemoRandom) -> DemoTransferPlan {
        let speed: Double
        if generator.nextUnit() < 1.0 / 3 {
            let threshold = thresholds[Int(generator.next() % UInt64(thresholds.count))]
            speed = threshold * (0.9 + 0.2 * generator.nextUnit())
        } else {
            // Log-uniform from 30 KB/s to 30 MB/s.
            speed = 30 * 1_024 * pow(1_024, generator.nextUnit())
        }
        let progress = 0.05 + 0.85 * generator.nextUnit()
        // At least two hours left at its own speed, so nothing finishes
        // during a test.
        let size = max(Double(minimumSize), speed * 7_200 / (1 - progress) * (1 + generator.nextUnit()))
        return DemoTransferPlan(
            id: generator.nextUUID(),
            name: name(index: index, generator: &generator),
            status: .downloading,
            progress: progress,
            totalBytes: Int64(size),
            baseDownloadSpeed: speed,
            baseUploadSpeed: generator.nextUnit() < 0.5 ? speed * 0.1 * generator.nextUnit() : 0,
            seeds: 1 + Int(generator.next() % 120),
            peers: Int(generator.next() % 60),
            uploadedBytes: Int64(Double(size) * progress * 0.2 * generator.nextUnit())
        )
    }

    private static func inactivePlan(
        index: Int,
        status: TorrentStatus,
        generator: inout DemoRandom
    ) -> DemoTransferPlan {
        let size = Double(minimumSize) * (1 + 60 * generator.nextUnit())
        let progress = status == .stopped ? 0.1 + 0.8 * generator.nextUnit() : 1
        return DemoTransferPlan(
            id: generator.nextUUID(),
            name: name(index: index, generator: &generator),
            status: status,
            progress: progress,
            totalBytes: Int64(size),
            baseDownloadSpeed: 0,
            baseUploadSpeed: status == .seeding && generator.nextUnit() < 0.7
                ? 20 * 1_024 * pow(100, generator.nextUnit())
                : 0,
            seeds: status == .seeding ? Int(generator.next() % 40) : 0,
            peers: status == .seeding ? 1 + Int(generator.next() % 30) : 0,
            uploadedBytes: Int64(size * 0.5 * generator.nextUnit())
        )
    }

    private static let minimumSize: Int64 = 200 * 1_048_576

    private static let names = [
        "Ubuntu 26.04 LTS Desktop amd64.iso", "Blender Open Movie Collection", "Big Buck Bunny 4K",
        "Sintel Director's Cut", "Debian 13 DVD Set", "Fedora Workstation 44 Live", "Arch Linux 2026.09",
        "Tears of Steel 4K HDR", "Public Domain Film Archive 1920s", "LibreOffice Portable Suite",
        "Wikipedia Offline Dump (ru)", "Kubernetes Training Videos", "OpenStreetMap Europe Extract",
        "Internet Archive Jazz Collection", "Cosmos Laundromat", "Linux Mint 23 Cinnamon", "Godot Engine Demo Projects",
        "Creative Commons Music Pack 2026", "NASA Earth Imagery Set", "Elephants Dream Remastered",
        "FreeBSD 15 Release", "Spring 1965 Newsreels", "Project Gutenberg Top 1000 EPUB",
        "Krita Brush Library", "Audacity Sample Sessions", "Raspberry Pi OS Full", "Pop!_OS 26.04",
        "Agent 327 Operation Barbershop", "Open Source Fonts Collection", "Machine Learning Datasets Vol. 3",
    ]

    private static func name(index: Int, generator: inout DemoRandom) -> String {
        let base = names[index % names.count]
        let round = index / names.count
        return round == 0 ? base : "\(base) — Part \(round + 1)"
    }
}

/// SplitMix64: a small generator with a fixed seed, so a preset plays the
/// same list and the same speeds every time.
nonisolated struct DemoRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    /// From 0 up to, not including, 1.
    mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    /// Standard normal, by Box–Muller.
    mutating func nextGaussian() -> Double {
        let first = max(nextUnit(), .leastNonzeroMagnitude)
        return (-2 * log(first)).squareRoot() * cos(2 * .pi * nextUnit())
    }

    mutating func nextUUID() -> UUID {
        let high = next()
        let low = next()
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            bytes[index] = UInt8(truncatingIfNeeded: high >> (index * 8))
            bytes[index + 8] = UInt8(truncatingIfNeeded: low >> (index * 8))
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
#endif
