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
    /// The link field's height, kept for the room it leaves while it is out.
    @State private var magnetFieldHeight: CGFloat = 0

    let placement: AddTorrentEntryPlacement
    /// Set while a download is dragged over the empty window. The link field
    /// is the system's: it accepts dragged text itself, and its focus ring is
    /// drawn apart from the view, so it does not fade with it. The field
    /// therefore leaves the window at once, before the drop screen comes,
    /// and returns with its text when the drag is over.
    let hidesMagnetFieldForDrag: Bool
    let onValidationError: (TorrentErrorState) -> Void

    init(
        placement: AddTorrentEntryPlacement,
        hidesMagnetFieldForDrag: Bool = false,
        onValidationError: @escaping (TorrentErrorState) -> Void = { _ in }
    ) {
        self.placement = placement
        self.hidesMagnetFieldForDrag = hidesMagnetFieldForDrag
        self.onValidationError = onValidationError
    }

    /// The modal's padding; the window's corners are rounder on macOS 26.
    private static var modalPadding: CGFloat {
        if #available(macOS 27.0, *) { 16 } else { 18 }
    }

    var body: some View {
        contentContainer
        .padding(placement == .modal ? Self.modalPadding : 0)
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
            scheduleRefocus()
        }
        .onChange(of: hidesMagnetFieldForDrag) { _, isHidden in
            if isHidden {
                blurMagnetField()
            } else {
                // Once the window's content has faded back in: the focus
                // ring would otherwise show at full strength ahead of it.
                scheduleRefocus()
            }
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

    /// The empty window also takes a file or a link dragged into it, and
    /// says so; the add modal lies over the list, where nothing can be dropped.
    private var subtitle: String {
        switch placement {
        case .emptyState:
            L10n.string(
                "add_torrent.entry.empty_subtitle",
                localeOverride: store.preferences.localeOverride,
                defaultValue: "Перетащите сюда .torrent-файл или magnet-ссылку либо добавьте их ниже."
            )
        case .modal:
            L10n.string(
                "add_torrent.entry.subtitle",
                localeOverride: store.preferences.localeOverride,
                defaultValue: "Вставьте magnet-ссылку в поле ниже или выберите .torrent-файл с вашего Mac."
            )
        }
    }

    private var hasMagnetInput: Bool {
        !magnetInput.isEmpty
    }

    /// The empty window's content; the add modal is `modalHeader` and
    /// `modalActionBox`.
    private var windowContent: some View {
        VStack(spacing: 16) {
            AddTorrentHeader(title: title, subtitle: subtitle)
            addTorrentBox
        }
        .frame(width: 300)
    }

    private var addTorrentBox: some View {
        addTorrentBoxContent
            .padding(12)
            .frame(width: 250)
            .glassEffect(
                .regular.tint(.accent.opacity(ShatlGlassTint.subtleOpacity)),
                in: addTorrentBoxShape
            )
            .background { addTorrentBoxShadow }
    }

    private var addTorrentBoxContent: some View {
        VStack(spacing: 8) {
            magnetContainer
            orDivider

            chooseFileButton
        }
    }

    /// The shape only casts the shadow, and its inside is cut away, so nothing
    /// darkens under the glass, as with a Figma drop shadow by default.
    private var addTorrentBoxShadow: some View {
        addTorrentBoxShape
            .fill(Color.black)
            .shatlShadow(ShatlShadow.addTorrentEmptyStateBox)
            .mask {
                ZStack {
                    // Room for the 16 pt blur moved 4 pt down.
                    Rectangle()
                        .padding(-64)
                    addTorrentBoxShape
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
            // Taken out for a drag and put back in one frame, whatever
            // animation the window around it is running.
            Group {
                if hidesMagnetFieldForDrag {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: magnetFieldHeight)
                        .transition(.identity)
                } else {
                    TextField("magnet:?xt=…", text: $magnetInput)
                        .controlSize(.large)
                        .focused($isMagnetFieldFocused)
                        .onSubmit {
                            continueWithMagnet()
                        }
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height
                        } action: { height in
                            magnetFieldHeight = height
                        }
                        .transition(.identity)
                }
            }
            .animation(nil, value: hidesMagnetFieldForDrag)

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

    /// Gives the link field its focus back a moment after a modal has
    /// closed or a drag has ended, if the empty list is still what is shown.
    private func scheduleRefocus() {
        guard placement == .emptyState else { return }

        refocusTask?.cancel()
        refocusTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            guard store.presentedModal == nil, store.torrents.isEmpty, !hidesMagnetFieldForDrag else { return }
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

/// The empty window's header; the add modal has its own, without the mark.
private struct AddTorrentHeader: View {
    @EnvironmentObject private var store: AppStore

    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 24) {
            ShatlWordmark(
                selection: preferredBrandMark
            )

            VStack(spacing: 6) {
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
            .frame(width: 300)
        }
        .frame(width: 300)
    }

    private var preferredBrandMark: Binding<ShatlBrandMark> {
        Binding(
            get: { store.preferences.preferredBrandMark },
            set: { store.setPreferredBrandMark($0) }
        )
    }
}
