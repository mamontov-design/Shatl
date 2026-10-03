// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

struct OnboardingFlowView: View {
    @Environment(\.openSettings) private var openSettings

    var localeOverride: AppLocaleOverride = .russian
    var metricsMode: MetricsPresentationMode = .simplified
    var onClose: () -> Void = {}
    var onEnableUsageStatistics: () -> Void = {}

    @State private var step = OnboardingStep.welcome

    var body: some View {
        ZStack {
            if step == .done {
                completionStep
                    .transition(.blurReplace)
            } else {
                onboardingShell
                    .transition(.blurReplace)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(ShatlMotion.onboardingStepChange, value: step)
    }

    private var onboardingShell: some View {
        OnboardingStepShell(
            stepID: step.rawValue,
            title: stepTitle,
            showsCaptionTopBorder: step == .welcome
        ) {
            onboardingPresentation
        } description: {
            onboardingDescription
        } actions: {
            onboardingActions
        }
    }

    private var completionStep: some View {
        OnboardingCompletionStep(
            title: stepTitle,
            introduction: localized(
                "onboarding.done.description",
                defaultValue: "В Настройках также доступны:"
            ),
            metricsTitle: localized(
                "settings.appearance.metrics.section",
                defaultValue: "Отображение данных"
            ),
            metricsDescription: localized(
                "onboarding.done.metrics.caption",
                defaultValue: "Упрощённо — только главное. Подробно — больше данных и точнее."
            ),
            performanceTitle: localized(
                "settings.downloads.performance.section",
                defaultValue: "Режим производительности"
            ),
            performanceDescription: localized(
                "onboarding.done.performance.caption",
                defaultValue: "Выберите Halo, Orbit или Nova — от бережного до максимального режима."
            ),
            localeOverride: localeOverride
        ) {
            onboardingActions
        }
    }

    private var stepTitle: String {
        switch step {
        case .welcome:
            localized("onboarding.welcome.title", defaultValue: "Добро пожаловать.")
        case .expandedCard:
            localized(
                "onboarding.expanded_card.title",
                defaultValue: "Расширенный вид."
            )
        case .data:
            localized("onboarding.data.title", defaultValue: "Делиться анонимной статистикой?")
        case .done:
            localized("onboarding.done.title", defaultValue: "Всё готово.")
        }
    }

    @ViewBuilder
    private var onboardingPresentation: some View {
        switch step {
        case .welcome:
            OnboardingWelcomeCoverPresentation()
        case .expandedCard:
            OnboardingExpandedCardPresentationView(
                localeOverride: localeOverride,
                metricsMode: metricsMode
            )
        case .data:
            DataCollectionInfo(style: .onboarding)
                .padding(.horizontal, 24)
        case .done:
            EmptyView()
        }
    }

    @ViewBuilder
    private var onboardingDescription: some View {
        switch step {
        case .welcome:
            plainDescription(
                "onboarding.welcome.description",
                defaultValue: "Перед вами лёгкий торрент-клиент для Mac на базе libtorrent. Открытый исходный код, только необходимые функции и аккуратный интерфейс. Несколько коротких шагов — и всё будет готово."
            )
        case .expandedCard:
            expandedCardDescription
        case .data:
            VStack(alignment: .leading, spacing: 8) {
                plainDescription(
                    "onboarding.data.description",
                    defaultValue: "Вы можете помочь понять, насколько Shatl нужен пользователям. Отчёт отправляется не чаще раза в неделю."
                )

                plainDescription(
                    "settings.data.caption.technical",
                    defaultValue: "Технически отчёт также содержит случайный идентификатор установки и отчётную неделю. Они нужны для объединения еженедельной статистики."
                )
            }
        case .done:
            EmptyView()
        }
    }

    @ViewBuilder
    private var onboardingActions: some View {
        switch step {
        case .welcome, .expandedCard:
            HStack(spacing: 8) {
                ShatlButton(
                    title: localized("onboarding.action.close", defaultValue: "Закрыть"),
                    role: .borderedNeutral,
                    action: finish
                )

                ShatlButton(
                    title: localized("onboarding.action.next", defaultValue: "Далее"),
                    role: .borderedColored,
                    action: goNext
                )
            }
        case .data:
            HStack(spacing: 8) {
                ShatlButton(
                    title: localized("onboarding.action.not_now", defaultValue: "Не сейчас"),
                    role: .borderedNeutral,
                    action: goNext
                )

                ShatlButton(
                    title: localized("onboarding.action.help_development", defaultValue: "Помочь развитию"),
                    role: .borderedColored
                ) {
                    onEnableUsageStatistics()
                    goNext()
                }
            }
        case .done:
            HStack(spacing: 8) {
                ShatlButton(
                    title: localized("onboarding.action.settings", defaultValue: "Настройки"),
                    role: .borderedNeutral,
                    action: openSettingsAndFinish
                )

                ShatlButton(
                    title: localized("onboarding.action.get_started", defaultValue: "Начать"),
                    role: .borderedColored,
                    action: finish
                )
            }
        }
    }

    private var expandedCardDescription: some View {
        VStack(alignment: .leading, spacing: 8) {
            plainDescription(
                "onboarding.expanded_card.description.lead",
                defaultValue: "Так будут выглядеть загрузки — каждая в своей карточке."
            )

            Text("\(expandedDescriptionPrefix)\(expandedDescriptionIcon)\(expandedDescriptionSuffix)")
                .shatlTypography(ShatlTypography.bodyRegular)
                .foregroundStyle(ShatlColor.typographySecondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var expandedDescriptionPrefix: Text {
        Text(
            localized(
                "onboarding.expanded_card.description.prefix",
                defaultValue: "Нажмите кнопку "
            )
        )
    }

    private var expandedDescriptionIcon: Text {
        Text(Image(systemName: "arrow.down.left.and.arrow.up.right"))
            .foregroundColor(ShatlColor.neonBlue)
    }

    private var expandedDescriptionSuffix: Text {
        Text(
            localized(
                "onboarding.expanded_card.description.suffix",
                defaultValue: " в правом верхнем углу, чтобы увидеть больше данных: сиды, пиры, размер и раздачу. Нажмите ещё раз, чтобы свернуть карточку."
            )
        )
    }

    private func plainDescription(_ key: String, defaultValue: String) -> some View {
        Text(localized(key, defaultValue: defaultValue))
            .shatlTypography(ShatlTypography.bodyRegular)
            .foregroundStyle(ShatlColor.typographySecondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func localized(_ key: String, defaultValue: String) -> String {
        L10n.string(key, localeOverride: localeOverride, defaultValue: defaultValue)
    }

    private func goNext() {
        guard let nextStep = step.next else { return }

        withAnimation(ShatlMotion.onboardingStepChange) {
            step = nextStep
        }
    }

    private func finish() {
        onClose()
    }

    private func openSettingsAndFinish() {
        openSettings()
        finish()
    }

}

private enum OnboardingStep: Int, CaseIterable {
    case welcome = 1
    case expandedCard
    case data
    case done

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

}

private struct OnboardingStepShell<Presentation: View, Description: View, Actions: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let stepID: Int
    let title: String
    let showsCaptionTopBorder: Bool
    let presentation: () -> Presentation
    let description: () -> Description
    let actions: () -> Actions

    init(
        stepID: Int,
        title: String,
        showsCaptionTopBorder: Bool = false,
        @ViewBuilder presentation: @escaping () -> Presentation,
        @ViewBuilder description: @escaping () -> Description,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.stepID = stepID
        self.title = title
        self.showsCaptionTopBorder = showsCaptionTopBorder
        self.presentation = presentation
        self.description = description
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: 0) {
            presentationArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(0)

            captionArea
                .zIndex(1)
        }
    }

    private var presentationArea: some View {
        Group {
            if stepID == OnboardingStep.welcome.rawValue {
                presentation()
            } else {
                ZStack {
                    presentationBackground

                    presentation()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id(stepID)
                }
            }
        }
    }

    private var captionArea: some View {
        VStack(spacing: 16) {
            labelsContainer
                .id(stepID)
                .transition(.blurReplace)

            buttonContainer
                .id(stepID)
                .transition(.blurReplace)
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            if showsCaptionTopBorder {
                Rectangle()
                    .fill(ShatlColor.outlinePrimary)
                    .frame(height: 0.5)
            }
        }
    }

    private var presentationBackground: LinearGradient {
        let colors: [Color] = colorScheme == .dark
            ? [
                Color(red: 63 / 255, green: 63 / 255, blue: 70 / 255),
                Color.black.opacity(0),
            ]
            : [
                Color(red: 244 / 255, green: 244 / 255, blue: 245 / 255),
                Color.white,
            ]

        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private var labelsContainer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .shatlTypography(ShatlTypography.headlineSemibold)
                .foregroundStyle(ShatlColor.typographyPrimary)
                .multilineTextAlignment(.leading)

            description()
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var buttonContainer: some View {
        HStack(spacing: 12) {
            OnboardingStepIndicator(currentStepID: stepID)

            Spacer(minLength: 0)

            actions()
        }
    }
}

private struct OnboardingCompletionStep<Actions: View>: View {
    let title: String
    let introduction: String
    let metricsTitle: String
    let metricsDescription: String
    let performanceTitle: String
    let performanceDescription: String
    let localeOverride: AppLocaleOverride
    let actions: () -> Actions

    init(
        title: String,
        introduction: String,
        metricsTitle: String,
        metricsDescription: String,
        performanceTitle: String,
        performanceDescription: String,
        localeOverride: AppLocaleOverride,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.title = title
        self.introduction = introduction
        self.metricsTitle = metricsTitle
        self.metricsDescription = metricsDescription
        self.performanceTitle = performanceTitle
        self.performanceDescription = performanceDescription
        self.localeOverride = localeOverride
        self.actions = actions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                labelsContainer

                settingsCards
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                OnboardingStepIndicator(currentStepID: OnboardingStep.done.rawValue)

                Spacer(minLength: 0)

                actions()
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var labelsContainer: some View {
        VStack(alignment: .leading, spacing: 16) {
            ShatlWordmark(
                initialSelection: .logomark,
                artworkAlignment: .leading,
                isInteractive: false
            )
                .frame(width: 84, height: 84, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .shatlTypography(ShatlTypography.headlineSemibold)
                    .foregroundStyle(ShatlColor.typographyPrimary)

                Text(introduction)
                    .shatlTypography(ShatlTypography.bodyRegular)
                    .foregroundStyle(ShatlColor.typographySecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settingsCards: some View {
        VStack(spacing: 8) {
            OnboardingSettingsCard(
                title: metricsTitle,
                description: metricsDescription
            ) {
                OnboardingMetricsModeIllustration(localeOverride: localeOverride)
            }

            OnboardingSettingsCard(
                title: performanceTitle,
                description: performanceDescription
            ) {
                HStack(spacing: 12) {
                    ForEach(AppPerformanceProfile.allCases) { profile in
                        ShatlPerformanceProfileSpeedometer(profile: profile)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct OnboardingSettingsCard<Illustration: View>: View {
    let title: String
    let description: String
    let illustration: () -> Illustration

    init(
        title: String,
        description: String,
        @ViewBuilder illustration: @escaping () -> Illustration
    ) {
        self.title = title
        self.description = description
        self.illustration = illustration
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .shatlTypography(ShatlTypography.bodySemibold)
                    .foregroundStyle(ShatlColor.typographyPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(description)
                    .shatlTypography(ShatlTypography.captionRegular)
                    .foregroundStyle(ShatlColor.typographySecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)

            illustration()
                .frame(maxWidth: .infinity)
                .padding(12)
        }
        .background {
            GeometryReader { proxy in
                ZStack(alignment: .trailing) {
                    ShatlColor.cardDefault
                    ShatlColor.cardHover
                        .frame(width: proxy.size.width / 2)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct OnboardingMetricsModeIllustration: View {
    private struct Sample {
        let downloadSpeedBytesPerSecond: Int64
        let etaSeconds: Int
    }

    private static let samples = [
        Sample(downloadSpeedBytesPerSecond: 9_750_000, etaSeconds: 2_280),
        Sample(downloadSpeedBytesPerSecond: 13_400_000, etaSeconds: 1_020),
        Sample(downloadSpeedBytesPerSecond: 18_650_000, etaSeconds: 3_180),
    ]

    let localeOverride: AppLocaleOverride

    @State private var sampleIndex = 0

    var body: some View {
        VStack(spacing: 12) {
            ShatlMetricSet(items: metricSet(for: .detailed))
            ShatlMetricSet(items: metricSet(for: .simplified))
        }
        .frame(maxWidth: .infinity)
        .task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }

                guard !Task.isCancelled else { return }

                withAnimation(ShatlMotion.metricResize) {
                    sampleIndex = (sampleIndex + 1) % Self.samples.count
                }
            }
        }
    }

    private func metricSet(for mode: MetricsPresentationMode) -> [MetricItemPresentation] {
        var record = TorrentRecord.previewData[0]
        let sample = Self.samples[sampleIndex]
        record.metrics.downloadSpeedBytesPerSecond = sample.downloadSpeedBytesPerSecond
        record.metrics.etaSeconds = sample.etaSeconds

        return TorrentPresentation.compactTransferMetricSet(
            for: record,
            mode: mode,
            localeOverride: localeOverride
        )?.items ?? []
    }
}

private struct OnboardingStepIndicator: View {
    let currentStepID: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                Circle()
                    .fill(
                        step.rawValue == currentStepID
                            ? ShatlColor.typographyPrimary
                            : ShatlColor.outlinePrimary
                    )
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.leading, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(currentStepID) / \(OnboardingStep.allCases.count)")
    }
}

private struct OnboardingWelcomeCoverPresentation: View {
    var body: some View {
        // `Color.clear` keeps the presentation area flexible. The fixed-size
        // asset is an overlay, so a short window clips the cover rather than
        // pushing the caption (and its bottom padding) outside the window.
        Color.clear
            .overlay {
                Image("onboardingWelcomeCover")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: OnboardingWindowLayout.windowSize.width, height: 340)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipped()
    }
}

#if DEBUG
#Preview("Onboarding Flow") {
    OnboardingFlowView()
        .environmentObject(ShatlAccentState())
        .shatlTypographyProfile(localeOverride: .russian)
        .frame(width: OnboardingWindowLayout.windowSize.width, height: OnboardingWindowLayout.windowSize.height)
}
#endif
