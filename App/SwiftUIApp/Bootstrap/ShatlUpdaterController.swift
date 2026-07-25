// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import Combine
import Sparkle

@MainActor
final class ShatlUpdaterController: ObservableObject {
    @Published private(set) var canCheckForUpdates: Bool
    @Published private(set) var automaticallyChecksForUpdates: Bool
    @Published private(set) var automaticallyInstallsUpdates: Bool
    @Published private(set) var allowsAutomaticUpdates: Bool

    private let standardUpdaterController: SPUStandardUpdaterController
    private var cancellables: Set<AnyCancellable> = []

    init(startingUpdater: Bool = true) {
        let standardUpdaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        let updater = standardUpdaterController.updater

        self.standardUpdaterController = standardUpdaterController
        canCheckForUpdates = updater.canCheckForUpdates
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        automaticallyInstallsUpdates = updater.automaticallyDownloadsUpdates
        allowsAutomaticUpdates = updater.allowsAutomaticUpdates

        updater.publisher(for: \.canCheckForUpdates, options: [.initial, .new])
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
            .store(in: &cancellables)

        updater.publisher(for: \.automaticallyChecksForUpdates, options: [.initial, .new])
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.automaticallyChecksForUpdates = value
            }
            .store(in: &cancellables)

        updater.publisher(for: \.automaticallyDownloadsUpdates, options: [.initial, .new])
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.automaticallyInstallsUpdates = value
            }
            .store(in: &cancellables)

        updater.publisher(for: \.allowsAutomaticUpdates, options: [.initial, .new])
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.allowsAutomaticUpdates = value
            }
            .store(in: &cancellables)

        if startingUpdater {
            standardUpdaterController.startUpdater()
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        standardUpdaterController.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ isEnabled: Bool) {
        guard standardUpdaterController.updater.automaticallyChecksForUpdates != isEnabled else {
            return
        }

        standardUpdaterController.updater.automaticallyChecksForUpdates = isEnabled
    }

    func setAutomaticallyInstallsUpdates(_ isEnabled: Bool) {
        let updater = standardUpdaterController.updater
        guard updater.allowsAutomaticUpdates else { return }
        guard updater.automaticallyDownloadsUpdates != isEnabled else { return }

        updater.automaticallyDownloadsUpdates = isEnabled
    }
}
