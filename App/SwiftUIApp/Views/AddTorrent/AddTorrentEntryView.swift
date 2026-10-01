// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum AddTorrentEntryPlacement: Equatable {
    case emptyState
    case modal
}

struct AddTorrentEntryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var magnetInput: String = ""
    @State private var refocusTask: Task<Void, Never>?
    @State private var validationError: TorrentErrorState?
    @State private var validationToastDismissTask: Task<Void, Never>?
    @FocusState private var isMagnetFieldFocused: Bool

    let placement: AddTorrentEntryPlacement
    let onValidationError: (TorrentErrorState) -> Void

    init(
        placement: AddTorrentEntryPlacement,
        onValidationError: @escaping (TorrentErrorState) -> Void = { _ in }
    ) {
        self.placement = placement
        self.onValidationError = onValidationError
    }

    var body: some View {
        contentContainer
        .padding(placement == .modal ? 16 : 0)
        .frame(width: 300)
        .overlay(alignment: .bottom) {
            validationToast
        }
        .animation(ShatlMotion.interface, value: hasMagnetInput)
        .animation(ShatlMotion.messageToast, value: validationError?.id)
        .onAppear {
            focusMagnetField()
        }
        .onChange(of: magnetInput) { _, _ in
            dismissValidationToast()
        }
        .onChange(of: store.presentedModal?.id) { oldModalID, newModalID in
            guard oldModalID != nil, newModalID == nil else { return }
            scheduleRefocusAfterModalDismiss()
        }
        .onDisappear {
            resetFocusState()
        }
    }

    @ViewBuilder
    private var contentContainer: some View {
        switch placement {
        case .emptyState:
            windowContent
        case .modal:
            VStack(alignment: .leading, spacing: 24) {
                modalHeader
                modalActionBox
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var title: String {
        switch placement {
        case .emptyState:
            L10n.string(
                "add_torrent.entry.empty_title",
                localeOverride: store.preferences.localeOverride,
                defaultValue: "Список загрузок пуст"
            )
        case .modal:
            L10n.string(
                "add_torrent.title",
                localeOverride: store.preferences.localeOverride,
                defaultValue: "Добавление загрузки"
            )
        }
    }

    private var subtitle: String {
        L10n.string(
            "add_torrent.entry.subtitle",
            localeOverride: store.preferences.localeOverride,
            defaultValue: "Вставьте .magnet-ссылку в поле ниже или выберите .torrent-файл с вашего Mac."
        )
    }

    private var hasMagnetInput: Bool {
        !magnetInput.isEmpty
    }

    private var windowContent: some View {
        VStack(spacing: 16) {
            AddTorrentHeader(title: title, subtitle: subtitle, placement: placement)
            addTorrentBox
        }
        .frame(width: placement == .emptyState ? 300 : nil)
        .frame(maxWidth: placement == .modal ? .infinity : nil)
    }

    @ViewBuilder
    private var addTorrentBox: some View {
        switch placement {
        case .emptyState:
            if #available(macOS 27.0, *) {
                addTorrentBoxContent
                    .padding(12)
                    .frame(width: 250)
                    .glassEffect(
                        .regular.tint(.accent.opacity(ShatlGlassTint.subtleOpacity)),
                        in: addTorrentBoxShape
                    )
            } else {
                addTorrentBoxContent
                    .padding(12)
                    .frame(width: 250)
            }
        case .modal:
            addTorrentBoxContent
                .padding(8)
                .frame(maxWidth: .infinity)
        }
    }

    private var addTorrentBoxContent: some View {
        VStack(spacing: 8) {
            magnetContainer
            orDivider

            chooseFileButton
        }
    }

    private var addTorrentBoxShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 19,
            bottomLeadingRadius: 27,
            bottomTrailingRadius: 27,
            topTrailingRadius: 25,
            style: .continuous
        )
    }

    @ViewBuilder
    private var chooseFileButton: some View {
        if hasMagnetInput {
            chooseFileButtonContent
                .buttonStyle(.glass)
        } else {
            chooseFileButtonContent
                .buttonStyle(.glassProminent)
        }
    }

    private var chooseFileButtonContent: some View {
        Button {
            presentTorrentFilePicker()
        } label: {
            Text(
                L10n.string(
                    "add_torrent.entry.choose_file",
                    localeOverride: store.preferences.localeOverride,
                    defaultValue: "Выбрать .torrent-файл…"
                )
            )
            .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var magnetContainer: some View {
        HStack(spacing: 8) {
            TextField("magnet:?xt=…", text: $magnetInput)
                .controlSize(.large)
                .focused($isMagnetFieldFocused)
                .onSubmit {
                    continueWithMagnet()
                }

            Button {
                continueWithMagnet()
            } label: {
                Label {
                    Text(
                        L10n.string(
                        "add_torrent.entry.continue",
                        localeOverride: store.preferences.localeOverride,
                        defaultValue: "Продолжить"
                        )
                    )
                } icon: {
                    Image(systemName: "arrow.forward")
                }
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!hasMagnetInput)
            .accessibilityLabel(
                Text(
                    L10n.string(
                        "add_torrent.entry.continue",
                        localeOverride: store.preferences.localeOverride,
                        defaultValue: "Продолжить"
                    )
                )
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var orDivider: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(ShatlColor.outlineSecondary)
                .frame(height: 1)

            Text(
                L10n.string(
                    "common.or",
                    localeOverride: store.preferences.localeOverride,
                    defaultValue: "Или"
                )
            )
                .shatlTypography(ShatlTypography.captionRegular)
                .foregroundStyle(ShatlColor.typographySecondary)

            Rectangle()
                .fill(ShatlColor.outlineSecondary)
                .frame(height: 1)
        }
        .padding(.horizontal, 4)
    }

    private var modalHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(ShatlColor.typographyTertiary)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .shatlTypography(ShatlTypography.headlineSemibold)
                    .foregroundStyle(ShatlColor.typographyPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .shatlTypography(ShatlTypography.bodyRegular)
                    .foregroundStyle(ShatlColor.typographySecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modalActionBox: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("magnet:?xt=…", text: $magnetInput)
                    .controlSize(.large)
                    .focused($isMagnetFieldFocused)
                    .onSubmit {
                        continueWithMagnet()
                    }

                ShatlButton(
                    systemImage: "arrow.forward",
                    iconSize: 14,
                    role: hasMagnetInput ? .borderedColored : .borderedNeutral,
                    isDisabled: !hasMagnetInput
                ) {
                    continueWithMagnet()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel(
                    Text(
                        L10n.string(
                            "add_torrent.entry.continue",
                            localeOverride: store.preferences.localeOverride,
                            defaultValue: "Продолжить"
                        )
                    )
                )
            }

            modalOrDivider

            ShatlButton(
                title: L10n.string(
                    "add_torrent.entry.choose_file",
                    localeOverride: store.preferences.localeOverride,
                    defaultValue: "Выбрать .torrent-файл…"
                ),
                role: hasMagnetInput ? .borderedNeutral : .borderedColored,
                fillsWidth: true
            ) {
                presentTorrentFilePicker()
            }

            ShatlButton(
                title: L10n.string(
                    "onboarding.action.close",
                    localeOverride: store.preferences.localeOverride,
                    defaultValue: "Закрыть"
                ),
                role: .borderedNeutral,
                fillsWidth: true
            ) {
                store.dismissModal()
            }
        }
    }

    private var modalOrDivider: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(ShatlColor.outlineSecondary)
                .frame(height: 1)

            Text(
                L10n.string(
                    "common.or",
                    localeOverride: store.preferences.localeOverride,
                    defaultValue: "Или"
                )
            )
                .shatlTypography(ShatlTypography.captionRegular)
                .foregroundStyle(ShatlColor.typographyPrimary)

            Rectangle()
                .fill(ShatlColor.outlineSecondary)
                .frame(height: 1)
        }
        .padding(.horizontal, 4)
    }

    /// The first vertical slice must accept a real torrent file,
    /// not just a preview placeholder.
    private func presentTorrentFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(importedAs: "org.bittorrent.torrent")]
        panel.prompt = L10n.string("common.choose", localeOverride: store.preferences.localeOverride)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        blurMagnetField()
        store.continueFromTorrentFile(at: url.path)
    }

    private func continueWithMagnet() {
        if let validationError = ShatlErrorCatalog.inlineMagnetValidation(
            for: magnetInput,
            localeOverride: store.preferences.localeOverride
        ) {
            switch placement {
            case .emptyState:
                onValidationError(validationError)
            case .modal:
                presentValidationToast(validationError)
            }
            return
        }

        blurMagnetField()
        store.continueFromEntry(with: magnetInput)
    }

    private func focusMagnetField() {
        DispatchQueue.main.async {
            isMagnetFieldFocused = true
        }
    }

    private func blurMagnetField() {
        refocusTask?.cancel()
        isMagnetFieldFocused = false
    }

    private func scheduleRefocusAfterModalDismiss() {
        guard placement == .emptyState else { return }

        refocusTask?.cancel()
        refocusTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            guard store.presentedModal == nil, store.torrents.isEmpty else { return }
            focusMagnetField()
        }
    }

    private func resetFocusState() {
        refocusTask?.cancel()
        refocusTask = nil
        validationToastDismissTask?.cancel()
        validationToastDismissTask = nil
        validationError = nil
        isMagnetFieldFocused = false
    }

    @ViewBuilder
    private var validationToast: some View {
        if placement == .modal, let validationError {
            ShatlMessageBlock(
                title: validationError.title,
                message: validationError.message,
                buttonTitle: L10n.string(
                    "onboarding.action.close",
                    localeOverride: store.preferences.localeOverride,
                    defaultValue: "Закрыть"
                ),
                buttonAction: {
                    dismissValidationToast()
                },
                localeOverride: store.preferences.localeOverride
            )
            .padding(.bottom, 24)
            .transition(ShatlMotion.messageToastTransition)
        }
    }

    private func presentValidationToast(_ errorState: TorrentErrorState) {
        validationToastDismissTask?.cancel()
        blurMagnetField()

        withAnimation(ShatlMotion.messageToast) {
            validationError = errorState
        }

        let errorID = errorState.id
        validationToastDismissTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled, validationError?.id == errorID else { return }
            dismissValidationToast()
        }
    }

    private func dismissValidationToast() {
        guard validationError != nil else { return }

        validationToastDismissTask?.cancel()
        validationToastDismissTask = nil

        withAnimation(ShatlMotion.messageToast) {
            validationError = nil
        }
    }
}

private struct AddTorrentHeader: View {
    @EnvironmentObject private var store: AppStore

    let title: String
    let subtitle: String
    let placement: AddTorrentEntryPlacement

    var body: some View {
        VStack(spacing: 24) {
            wordmark

            VStack(spacing: placement == .modal ? 4 : 6) {
                Text(title)
                    .shatlTypography(ShatlTypography.headlineSemibold)
                    .foregroundStyle(ShatlColor.typographyPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .shatlTypography(ShatlTypography.bodyRegular)
                    .foregroundStyle(ShatlColor.typographySecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: placement == .emptyState ? 300 : nil)
            .frame(maxWidth: placement == .modal ? .infinity : nil)
        }
        .frame(width: placement == .emptyState ? 300 : nil)
        .frame(maxWidth: placement == .modal ? .infinity : nil)
    }

    @ViewBuilder
    private var wordmark: some View {
        switch placement {
        case .emptyState:
            ShatlWordmark(
                renderingMode: .glass,
                selection: preferredBrandMark
            )
        case .modal:
            ShatlWordmark(
                renderingMode: .flat,
                selection: preferredBrandMark
            )
        }
    }

    private var preferredBrandMark: Binding<ShatlBrandMark> {
        Binding(
            get: { store.preferences.preferredBrandMark },
            set: { store.setPreferredBrandMark($0) }
        )
    }
}
