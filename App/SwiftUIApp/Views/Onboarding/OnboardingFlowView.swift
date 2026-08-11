// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

private enum OnboardingThemeLayout {
    static let manualCardsExpandedHeight: CGFloat = 70
}

private enum OnboardingWindowLayout {
    static var closeButtonPadding: CGFloat {
        if #available(macOS 27.0, *) {
            8
        } else {
            16
        }
    }
}

struct OnboardingFlowView: View {
    var localeOverride: AppLocaleOverride = .russian
    var defaultDownloadPath: String = AppPreferences.defaultValue.defaultDownloadPath
    var metricsMode: MetricsPresentationMode = .simplified
    var theme: AppTheme = .system
    var onClose: () -> Void = {}
    var onEnableUsageStatistics: () -> Void = {}
    var onChangeDownloadFolder: () -> Void = {}
    var onMetricsModeChange: (MetricsPresentationMode) -> Void = { _ in }
    var onThemeChange: (AppTheme) -> Void = { _ in }

    @State private var step = OnboardingStep.welcome
    @State private var onboardingTheme: AppTheme?
    @State private var themePersistenceTask: Task<Void, Never>?

    var body: some View {
        onboardingShell
            .frame(width: 400, height: 500)
            .animation(ShatlMotion.onboardingStepChange, value: step)
    }

    private var onboardingShell: some View {
        OnboardingStepShell(
            stepID: step.rawValue,
            progressIndex: step.progressIndex,
            title: stepTitle,
            usesOverlayCaption: step == .theme,
            onClose: finish
        ) {
            onboardingPresentation
        } description: {
            onboardingDescription
        } actions: {
            onboardingActions
        }
    }

    private var stepTitle: String {
        switch step {
        case .welcome:
            localized("onboarding.welcome.title", defaultValue: "Добро пожаловать в Shatl")
        case .downloadFolder:
            localized(
                "onboarding.download_folder.title",
                defaultValue: "Папка сохранения загрузок по умолчанию"
            )
        case .expandedCard:
            localized(
                "onboarding.expanded_card.title",
                defaultValue: "Переход в расширенный вид"
            )
        case .metricsMode:
            localized(
                "onboarding.metrics_mode.title",
                defaultValue: "Режим отображения данных"
            )
        case .theme:
            localized(
                "onboarding.theme.title",
                defaultValue: "Выбор темы оформления"
            )
        case .data:
            localized("onboarding.data.title", defaultValue: "Анонимная статистика")
        case .done:
            localized("onboarding.done.title", defaultValue: "Всё настроено")
        }
    }

    @ViewBuilder
    private var onboardingPresentation: some View {
        switch step {
        case .welcome, .done:
            OnboardingLogoPresentation(stepID: step.rawValue)
        case .downloadFolder:
            OnboardingDownloadFolderPresentation(
                saveToTitle: localized("onboarding.download_folder.save_to", defaultValue: "Сохранять в:"),
                downloadPath: defaultDownloadPath,
                changeTitle: localized("common.change", defaultValue: "Сменить"),
                onChange: onChangeDownloadFolder
            )
        case .expandedCard:
            OnboardingExpandedCardPresentationView(
                localeOverride: localeOverride,
                metricsMode: metricsMode
            )
        case .metricsMode:
            OnboardingExpandedCardPresentationView(
                localeOverride: localeOverride,
                metricsMode: metricsMode,
                initiallyExpanded: true,
                centersExpandedCard: true,
                allowsExpansionToggle: false,
                pulsesMetricSetOutlines: true
            )
        case .theme:
            OnboardingThemePreviewPresentation(
                theme: displayedTheme,
                localeOverride: localeOverride
            )
        case .data:
            DataCollectionInfo(style: .onboarding)
        }
    }

    @ViewBuilder
    private var onboardingDescription: some View {
        switch step {
        case .welcome:
            plainDescription(
                "onboarding.welcome.description",
                defaultValue: "Перед вами лёгкий torrent-клиент для Mac на базе libtorrent. Открытый исходный код, только необходимые функции и аккуратный интерфейс."
            )
        case .downloadFolder:
            plainDescription(
                "onboarding.download_folder.description",
                defaultValue: "По умолчанию файлы сохраняются в папку «Загрузки». Вы можете изменить путь сейчас или позже в Настройках."
            )
        case .expandedCard:
            expandedCardDescription
        case .metricsMode:
            VStack(spacing: 6) {
                plainDescription(
                    "onboarding.metrics_mode.description",
                    defaultValue: "Упрощённый режим показывает округлённые значения, а подробный сохраняет более точные значения."
                )

                metricsModeTumblers
                    .padding(.top, 6)
            }
        case .theme:
            VStack(spacing: 6) {
                plainDescription(
                    "settings.appearance.theme.caption",
                    defaultValue: "Shatl может менять оформление в соответствии с настройками macOS или использовать выбранную тему."
                )

                themeControls
            }
        case .data:
            plainDescription(
                "onboarding.data.description",
                defaultValue: "Вы можете помочь понять, насколько Shatl нужен пользователям. Отправляются только количество запусков, версия приложения и язык интерфейса."
            )
        case .done:
            plainDescription(
                "onboarding.done.description",
                defaultValue: "Shatl готов к работе. Параметры можно изменить в Настройках в любой момент."
            )
        }
    }

    @ViewBuilder
    private var onboardingActions: some View {
        switch step {
        case .welcome, .downloadFolder, .expandedCard, .metricsMode, .theme:
            nextButton
        case .data:
            HStack(spacing: 8) {
                ShatlButton(
                    title: localized("onboarding.action.not_now", defaultValue: "Не сейчас"),
                    role: .borderedNeutral,
                    action: goNext
                )

                ShatlButton(
                    title: localized("onboarding.action.help_development", defaultValue: "Помочь развитию"),
                    role: .borderedMonochrome
                ) {
                    onEnableUsageStatistics()
                    goNext()
                }
            }
        case .done:
            ShatlButton(
                title: localized("onboarding.action.close", defaultValue: "Закрыть"),
                role: .borderedMonochrome,
                action: finish
            )
        }
    }

    private var nextButton: some View {
        ShatlButton(
            title: localized("onboarding.action.next", defaultValue: "Далее"),
            role: .borderedMonochrome,
            action: goNext
        )
    }

    private var metricsModeTumblers: some View {
        HStack(spacing: 6) {
            ForEach(MetricsPresentationMode.allCases) { mode in
                ShatlSettingsInputCard(
                    title: metricsModeTitle(mode),
                    isSelected: metricsMode == mode,
                    labelPlacement: .insideCard
                ) {
                    onMetricsModeChange(mode)
                } content: {
                    EmptyView()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var themeControls: some View {
        let showsManualThemeCards = displayedTheme != .system

        return VStack(spacing: 0) {
            ShatlSettingsParameter {
                ShatlSettingsToggleRow(
                    title: localized(
                        "onboarding.theme.follow_macos",
                        defaultValue: "Следовать настройкам macOS"
                    ),
                    isOn: followsSystemTheme
                )
            }

            HStack(spacing: 6) {
                ForEach([AppTheme.light, AppTheme.dark]) { manualTheme in
                    ShatlSettingsInputCard(
                        title: themeTitle(manualTheme),
                        isSelected: displayedTheme == manualTheme,
                        labelPlacement: .insideCard
                    ) {
                        changeTheme(to: manualTheme)
                    } content: {
                        EmptyView()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .padding(.top, 6)
            .padding(.bottom, 2)
            .scaleEffect(showsManualThemeCards ? 1 : 0.85, anchor: .center)
            .opacity(showsManualThemeCards ? 1 : 0)
            .frame(
                height: showsManualThemeCards
                    ? OnboardingThemeLayout.manualCardsExpandedHeight
                    : 0,
                alignment: .bottom
            )
            .clipped()
            .allowsHitTesting(showsManualThemeCards)
            .accessibilityHidden(!showsManualThemeCards)
            .animation(ShatlMotion.interface, value: showsManualThemeCards)
        }
        .frame(maxWidth: .infinity)
    }

    private var followsSystemTheme: Binding<Bool> {
        Binding(
            get: { displayedTheme == .system },
            set: { followsSystem in
                changeTheme(to: followsSystem ? .system : .light)
            }
        )
    }

    private var displayedTheme: AppTheme {
        onboardingTheme ?? theme
    }

    private func changeTheme(to newTheme: AppTheme) {
        themePersistenceTask?.cancel()

        withAnimation(ShatlMotion.interface) {
            onboardingTheme = newTheme
        }

        themePersistenceTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(700))
            } catch {
                return
            }

            onThemeChange(newTheme)
            themePersistenceTask = nil
        }
    }

    private func themeTitle(_ theme: AppTheme) -> String {
        switch theme {
        case .system:
            localized(
                "settings.appearance.theme.system",
                defaultValue: "Как в системе"
            )
        case .light:
            localized(
                "settings.appearance.theme.light",
                defaultValue: "Светлая"
            )
        case .dark:
            localized(
                "settings.appearance.theme.dark",
                defaultValue: "Тёмная"
            )
        }
    }

    private func metricsModeTitle(_ mode: MetricsPresentationMode) -> String {
        switch mode {
        case .simplified:
            localized(
                "settings.appearance.metrics.simplified",
                defaultValue: "Упрощённо"
            )
        case .detailed:
            localized(
                "settings.appearance.metrics.detailed",
                defaultValue: "Подробно"
            )
        }
    }

    private var expandedCardDescription: some View {
        Text("\(expandedDescriptionPrefix)\(expandedDescriptionIcon)\(expandedDescriptionSuffix)")
            .shatlTypography(ShatlTypography.captionRegular)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var expandedDescriptionPrefix: Text {
        Text(
            localized(
                "onboarding.expanded_card.description.prefix",
                defaultValue: "Нажмите на кнопку "
            )
        )
        .foregroundColor(ShatlColor.typographySecondary)
    }

    private var expandedDescriptionIcon: Text {
        Text(Image(systemName: "arrow.down.left.and.arrow.up.right"))
            .foregroundColor(ShatlColor.metricPulseHighlight)
    }

    private var expandedDescriptionSuffix: Text {
        Text(
            localized(
                "onboarding.expanded_card.description.suffix",
                defaultValue: " в правом верхнем углу, чтобы увидеть больше данных: сиды, пиры, размер и раздачу. Нажмите на кнопку снова, чтобы перевести карточку обратно в компактный вид."
            )
        )
        .foregroundColor(ShatlColor.typographySecondary)
    }

    private func plainDescription(_ key: String, defaultValue: String) -> some View {
        Text(localized(key, defaultValue: defaultValue))
            .shatlTypography(ShatlTypography.captionRegular)
            .foregroundStyle(ShatlColor.typographySecondary)
            .multilineTextAlignment(.center)
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
        persistPendingThemeImmediately()
        onClose()
    }

    private func persistPendingThemeImmediately() {
        themePersistenceTask?.cancel()
        themePersistenceTask = nil

        guard let onboardingTheme, onboardingTheme != theme else { return }
        onThemeChange(onboardingTheme)
    }

}

private enum OnboardingStep: Int, CaseIterable {
    case welcome = 1
    case downloadFolder
    case expandedCard
    case metricsMode
    case theme
    case data
    case done

    static let progressStepCount = allCases.filter { $0 != .done }.count

    var progressIndex: Int? {
        self == .done ? nil : rawValue
    }

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

}

private struct OnboardingStepShell<Presentation: View, Description: View, Actions: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let stepID: Int
    let progressIndex: Int?
    let title: String
    let usesOverlayCaption: Bool
    let onClose: () -> Void
    let presentation: () -> Presentation
    let description: () -> Description
    let actions: () -> Actions

    init(
        stepID: Int,
        progressIndex: Int?,
        title: String,
        usesOverlayCaption: Bool = false,
        onClose: @escaping () -> Void,
        @ViewBuilder presentation: @escaping () -> Presentation,
        @ViewBuilder description: @escaping () -> Description,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.stepID = stepID
        self.progressIndex = progressIndex
        self.title = title
        self.usesOverlayCaption = usesOverlayCaption
        self.onClose = onClose
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
        ZStack {
            presentationBackground

            OnboardingAmbientPresentationBackground(
                showsAccentDots: stepID != OnboardingStep.data.rawValue
            )
                .allowsHitTesting(false)

            presentation()
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: usesOverlayCaption ? .top : .center
                )
                .id(stepID)
        }
        .overlay(alignment: .topTrailing) {
            ShatlModalCloseButton(
                action: onClose,
                iconSize: 17,
                hoverForegroundColor: ShatlColor.typographyTertiary
            )
            .padding(OnboardingWindowLayout.closeButtonPadding)
        }
    }

    private var captionArea: some View {
        VStack(spacing: 16) {
            if let progressIndex {
                ShatlOnboardingProgressDots(
                    currentStep: progressIndex,
                    stepCount: OnboardingStep.progressStepCount
                )
            }

            labelsContainer
                .id(stepID)
                .transition(.blurReplace)

            actions()
                .frame(maxWidth: .infinity, alignment: .center)
                .id(stepID)
                .transition(.blurReplace)
        }
        .padding(.horizontal, 24)
        .padding(.top, usesOverlayCaption ? 16 : 0)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(ShatlColor.onboardingForeground)
        .overlay(alignment: .top) {
            if usesOverlayCaption {
                Rectangle()
                    .fill(ShatlColor.onboardingOutline)
                    .frame(height: 1)
            }
        }
    }

    private var presentationBackground: LinearGradient {
        let colors: [Color] = colorScheme == .dark
            ? [
                Color(red: 17 / 255, green: 24 / 255, blue: 39 / 255),
                Color(red: 55 / 255, green: 65 / 255, blue: 81 / 255),
            ]
            : [
                Color(red: 229 / 255, green: 231 / 255, blue: 235 / 255),
                Color.white,
            ]

        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private var labelsContainer: some View {
        VStack(spacing: 6) {
            Text(title)
                .shatlTypography(ShatlTypography.headlineSemibold)
                .foregroundStyle(ShatlColor.typographyPrimary)
                .multilineTextAlignment(.center)

            description()
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct OnboardingThemePreviewPresentation: View {
    let theme: AppTheme
    let localeOverride: AppLocaleOverride

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    Image(assetName)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 400, height: 431)
                        .id(assetName)
                        .transition(.blurReplace)
                }
                .frame(width: 400, height: 431, alignment: .top)
                .animation(ShatlMotion.onboardingStepChange, value: assetName)
            }
    }

    private var assetName: String {
        "themePreview\(themeAssetComponent)\(localeAssetSuffix)"
    }

    private var themeAssetComponent: String {
        switch theme {
        case .system:
            "System"
        case .light:
            "Light"
        case .dark:
            "Dark"
        }
    }

    private var localeAssetSuffix: String {
        switch localeOverride {
        case .english:
            "En"
        case .russian:
            "Ru"
        case .german:
            "Ge"
        case .spanish:
            "Sp"
        case .french:
            "Fr"
        case .japanese:
            "Ja"
        case .simplifiedChinese:
            "Ch"
        case .system:
            systemLocaleAssetSuffix
        }
    }

    private var systemLocaleAssetSuffix: String {
        let preferredLanguage = Locale.preferredLanguages.first?.lowercased() ?? "en"

        if preferredLanguage.hasPrefix("zh") {
            return "Ch"
        }
        if preferredLanguage.hasPrefix("ru") {
            return "Ru"
        }
        if preferredLanguage.hasPrefix("de") {
            return "Ge"
        }
        if preferredLanguage.hasPrefix("es") {
            return "Sp"
        }
        if preferredLanguage.hasPrefix("fr") {
            return "Fr"
        }
        if preferredLanguage.hasPrefix("ja") {
            return "Ja"
        }

        return "En"
    }
}

private struct OnboardingAmbientPresentationBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bodies: [OnboardingAmbientBody]

    let showsAccentDots: Bool

    init(showsAccentDots: Bool) {
        self.showsAccentDots = showsAccentDots
        _bodies = State(initialValue: Self.makeBodies())
    }

    var body: some View {
        ZStack {
            ForEach(bodies) { body in
                if !body.kind.isAccentDot {
                    ambientBody(body)
                }
            }

            ZStack {
                ForEach(bodies) { body in
                    if body.kind.isAccentDot {
                        ambientBody(body)
                    }
                }
            }
            .opacity(showsAccentDots ? 1 : 0)
            .animation(ShatlMotion.onboardingStepChange, value: showsAccentDots)
        }
        .frame(
            width: OnboardingAmbientMotion.containerSize.width,
            height: OnboardingAmbientMotion.containerSize.height
        )
        .clipped()
        .task {
            await runMotion()
        }
    }

    private func ambientBody(_ body: OnboardingAmbientBody) -> some View {
        demonstrationShape(for: body.kind)
            .frame(width: body.kind.displaySize, height: body.kind.displaySize)
            .blur(radius: body.blurRadius)
            .opacity(body.opacity)
            .rotationEffect(.degrees(body.rotation))
            .position(body.position)
    }

    @ViewBuilder
    private func demonstrationShape(for kind: OnboardingAmbientShapeKind) -> some View {
        switch kind {
        case .oval:
            ShatlOnboardingDemonstrationOvalShape()
                .fill(shapeColor)
        case .rectangle:
            ShatlOnboardingDemonstrationRectangleShape()
                .fill(shapeColor)
        case .star:
            ShatlOnboardingDemonstrationStarShape()
                .fill(shapeColor)
        case .triangle:
            ShatlOnboardingDemonstrationTriangleShape()
                .fill(shapeColor)
        case .accentDotOne, .accentDotTwo, .accentDotThree:
            Circle()
                .fill(ShatlColor.accent.opacity(0.75))
        }
    }

    private var shapeColor: Color {
        colorScheme == .dark
            ? Color(red: 75 / 255, green: 85 / 255, blue: 99 / 255)
            : Color(red: 209 / 255, green: 213 / 255, blue: 219 / 255)
    }

    @MainActor
    private func runMotion() async {
        var previousUpdate = Date()

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(OnboardingAmbientMotion.frameInterval))
            } catch {
                return
            }

            let now = Date()
            let deltaTime = min(
                now.timeIntervalSince(previousUpdate),
                OnboardingAmbientMotion.maximumFrameDuration
            )
            previousUpdate = now

            guard !reduceMotion else { continue }
            updateBodies(deltaTime: deltaTime)
        }
    }

    @MainActor
    private func updateBodies(deltaTime: TimeInterval) {
        let delta = CGFloat(deltaTime)

        for index in bodies.indices {
            bodies[index].position.x += bodies[index].velocity.dx * delta
            bodies[index].position.y += bodies[index].velocity.dy * delta
            bodies[index].rotation += bodies[index].angularVelocity * deltaTime
            updateVisualVariation(at: index, deltaTime: deltaTime)
            resolveContainerCollision(at: index)
        }

        for _ in 0..<OnboardingAmbientMotion.collisionResolutionIterations {
            resolveBodyCollisions()

            for index in bodies.indices {
                resolveContainerCollision(at: index)
            }
        }
    }

    @MainActor
    private func updateVisualVariation(at index: Int, deltaTime: TimeInterval) {
        bodies[index].visualTransitionElapsed += deltaTime

        let duration = bodies[index].visualTransitionDuration
        let linearProgress = min(bodies[index].visualTransitionElapsed / duration, 1)
        let progress = linearProgress * linearProgress * (3 - 2 * linearProgress)

        bodies[index].blurRadius = interpolated(
            from: bodies[index].visualStartBlurRadius,
            to: bodies[index].visualTargetBlurRadius,
            progress: progress
        )

        if bodies[index].kind.usesDynamicOpacity {
            bodies[index].opacity = interpolated(
                from: bodies[index].visualStartOpacity,
                to: bodies[index].visualTargetOpacity,
                progress: progress
            )
        } else {
            bodies[index].opacity = 1
        }

        guard linearProgress >= 1 else { return }

        bodies[index].visualStartBlurRadius = bodies[index].blurRadius
        bodies[index].visualTargetBlurRadius = CGFloat.random(
            in: bodies[index].kind.blurRange
        )
        bodies[index].visualStartOpacity = bodies[index].opacity
        bodies[index].visualTargetOpacity = bodies[index].kind.usesDynamicOpacity
            ? Double.random(in: OnboardingAmbientMotion.opacityRange)
            : 1
        bodies[index].visualTransitionElapsed = 0
        bodies[index].visualTransitionDuration = Double.random(
            in: OnboardingAmbientMotion.visualTransitionDurationRange
        )
    }

    private func interpolated<T: BinaryFloatingPoint>(
        from start: T,
        to end: T,
        progress: Double
    ) -> T {
        start + (end - start) * T(progress)
    }

    @MainActor
    private func resolveContainerCollision(at index: Int) {
        let hitboxHalfSize = bodies[index].kind.hitboxSize / 2
        let minimumX = OnboardingAmbientMotion.contentPadding + hitboxHalfSize
        let maximumX = OnboardingAmbientMotion.containerSize.width
            - OnboardingAmbientMotion.contentPadding
            - hitboxHalfSize
        let minimumY = OnboardingAmbientMotion.contentPadding + hitboxHalfSize
        let maximumY = OnboardingAmbientMotion.containerSize.height
            - OnboardingAmbientMotion.contentPadding
            - hitboxHalfSize

        if bodies[index].position.x < minimumX {
            bodies[index].position.x = minimumX
            bodies[index].velocity.dx = abs(bodies[index].velocity.dx)
        } else if bodies[index].position.x > maximumX {
            bodies[index].position.x = maximumX
            bodies[index].velocity.dx = -abs(bodies[index].velocity.dx)
        }

        if bodies[index].position.y < minimumY {
            bodies[index].position.y = minimumY
            bodies[index].velocity.dy = abs(bodies[index].velocity.dy)
        } else if bodies[index].position.y > maximumY {
            bodies[index].position.y = maximumY
            bodies[index].velocity.dy = -abs(bodies[index].velocity.dy)
        }
    }

    @MainActor
    private func resolveBodyCollisions() {
        guard bodies.count > 1 else { return }

        for firstIndex in bodies.indices.dropLast() {
            for secondIndex in bodies.indices where secondIndex > firstIndex {
                resolveCollision(between: firstIndex, and: secondIndex)
            }
        }
    }

    @MainActor
    private func resolveCollision(between firstIndex: Int, and secondIndex: Int) {
        let deltaX = bodies[secondIndex].position.x - bodies[firstIndex].position.x
        let deltaY = bodies[secondIndex].position.y - bodies[firstIndex].position.y
        let requiredSeparation = (
            bodies[firstIndex].kind.hitboxSize
                + bodies[secondIndex].kind.hitboxSize
        ) / 2
        let overlapX = requiredSeparation - abs(deltaX)
        let overlapY = requiredSeparation - abs(deltaY)

        guard overlapX > 0, overlapY > 0 else { return }

        if overlapX < overlapY {
            let direction: CGFloat = deltaX >= 0 ? 1 : -1
            let separation = overlapX / 2
            bodies[firstIndex].position.x -= separation * direction
            bodies[secondIndex].position.x += separation * direction

            if (bodies[secondIndex].velocity.dx - bodies[firstIndex].velocity.dx) * direction < 0 {
                let firstVelocity = bodies[firstIndex].velocity.dx
                bodies[firstIndex].velocity.dx = bodies[secondIndex].velocity.dx
                bodies[secondIndex].velocity.dx = firstVelocity
            }
        } else {
            let direction: CGFloat = deltaY >= 0 ? 1 : -1
            let separation = overlapY / 2
            bodies[firstIndex].position.y -= separation * direction
            bodies[secondIndex].position.y += separation * direction

            if (bodies[secondIndex].velocity.dy - bodies[firstIndex].velocity.dy) * direction < 0 {
                let firstVelocity = bodies[firstIndex].velocity.dy
                bodies[firstIndex].velocity.dy = bodies[secondIndex].velocity.dy
                bodies[secondIndex].velocity.dy = firstVelocity
            }
        }

        bodies[firstIndex].velocity = normalizedVelocity(bodies[firstIndex].velocity)
        bodies[secondIndex].velocity = normalizedVelocity(bodies[secondIndex].velocity)
    }

    private func normalizedVelocity(_ velocity: CGVector) -> CGVector {
        let magnitude = hypot(velocity.dx, velocity.dy)
        guard magnitude > 0 else {
            return CGVector(dx: OnboardingAmbientMotion.linearSpeed, dy: 0)
        }

        let scale = OnboardingAmbientMotion.linearSpeed / magnitude
        return CGVector(dx: velocity.dx * scale, dy: velocity.dy * scale)
    }

    private static func makeBodies() -> [OnboardingAmbientBody] {
        let placements: [(OnboardingAmbientShapeKind, CGPoint)] = [
            (.rectangle, CGPoint(x: 58, y: 52)),
            (.oval, CGPoint(x: 202, y: 52)),
            (.star, CGPoint(x: 58, y: 158)),
            (.triangle, CGPoint(x: 202, y: 158)),
            (.accentDotOne, CGPoint(x: 130, y: 40)),
            (.accentDotTwo, CGPoint(x: 130, y: 105)),
            (.accentDotThree, CGPoint(x: 130, y: 170)),
        ]

        return placements.enumerated().map { index, placement in
            let angle = Double.random(in: 0..<(2 * .pi))
            let direction = index.isMultiple(of: 2) ? 1.0 : -1.0
            let initialBlurRadius = CGFloat.random(in: placement.0.blurRange)
            let initialOpacity = placement.0.usesDynamicOpacity
                ? Double.random(in: OnboardingAmbientMotion.opacityRange)
                : 1

            return OnboardingAmbientBody(
                kind: placement.0,
                position: placement.1,
                velocity: CGVector(
                    dx: OnboardingAmbientMotion.linearSpeed * CGFloat(cos(angle)),
                    dy: OnboardingAmbientMotion.linearSpeed * CGFloat(sin(angle))
                ),
                rotation: Double.random(in: 0..<360),
                angularVelocity: OnboardingAmbientMotion.angularSpeed * direction,
                blurRadius: initialBlurRadius,
                opacity: initialOpacity,
                visualStartBlurRadius: initialBlurRadius,
                visualTargetBlurRadius: CGFloat.random(in: placement.0.blurRange),
                visualStartOpacity: initialOpacity,
                visualTargetOpacity: placement.0.usesDynamicOpacity
                    ? Double.random(in: OnboardingAmbientMotion.opacityRange)
                    : 1,
                visualTransitionElapsed: 0,
                visualTransitionDuration: Double.random(
                    in: OnboardingAmbientMotion.visualTransitionDurationRange
                )
            )
        }
    }
}

private enum OnboardingAmbientMotion {
    static let containerSize = CGSize(width: 260, height: 210)
    static let contentPadding: CGFloat = 8
    static let shapeSize: CGFloat = 64
    static let accentDotSize: CGFloat = 6
    static let blurRange: ClosedRange<CGFloat> = 1...4
    static let accentDotBlurRange: ClosedRange<CGFloat> = 2...8
    static let opacityRange: ClosedRange<Double> = 0.24...0.46
    static let visualTransitionDurationRange: ClosedRange<Double> = 3...6
    static let linearSpeed: CGFloat = 8
    static let angularSpeed = 5.0
    static let frameInterval = 1.0 / 30.0
    static let maximumFrameDuration = 1.0 / 15.0
    static let collisionResolutionIterations = 3
}

private enum OnboardingAmbientShapeKind: Hashable {
    case oval
    case rectangle
    case star
    case triangle
    case accentDotOne
    case accentDotTwo
    case accentDotThree

    var isAccentDot: Bool {
        switch self {
        case .accentDotOne, .accentDotTwo, .accentDotThree:
            true
        case .oval, .rectangle, .star, .triangle:
            false
        }
    }

    var displaySize: CGFloat {
        isAccentDot
            ? OnboardingAmbientMotion.accentDotSize
            : OnboardingAmbientMotion.shapeSize
    }

    var hitboxSize: CGFloat {
        displaySize
    }

    var blurRange: ClosedRange<CGFloat> {
        isAccentDot
            ? OnboardingAmbientMotion.accentDotBlurRange
            : OnboardingAmbientMotion.blurRange
    }

    var usesDynamicOpacity: Bool {
        !isAccentDot
    }
}

private struct OnboardingAmbientBody: Identifiable {
    var id: OnboardingAmbientShapeKind { kind }

    let kind: OnboardingAmbientShapeKind
    var position: CGPoint
    var velocity: CGVector
    var rotation: Double
    let angularVelocity: Double
    var blurRadius: CGFloat
    var opacity: Double
    var visualStartBlurRadius: CGFloat
    var visualTargetBlurRadius: CGFloat
    var visualStartOpacity: Double
    var visualTargetOpacity: Double
    var visualTransitionElapsed: TimeInterval
    var visualTransitionDuration: TimeInterval
}

private struct OnboardingLogoPresentation: View {
    let stepID: Int

    var body: some View {
        ShatlWordmark(
            renderingMode: .flat,
            initialSelection: .logomark
        )
            .id(stepID)
            .frame(width: 400, height: 163)
    }
}

private struct OnboardingDownloadFolderPresentation: View {
    let saveToTitle: String
    let downloadPath: String
    let changeTitle: String
    let onChange: () -> Void

    private var folderName: String {
        let name = URL(fileURLWithPath: downloadPath).lastPathComponent
        return name.isEmpty ? downloadPath : name
    }

    private var folderTitle: String {
        "\(saveToTitle) \(folderName)"
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: folderTitle)
                    .shatlTypography(ShatlTypography.bodyMedium)
                    .foregroundStyle(ShatlColor.typographyPrimary)
                    .lineLimit(1)

                Text(verbatim: downloadPath)
                    .shatlTypography(ShatlTypography.bodyRegular)
                    .foregroundStyle(ShatlColor.typographySecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ShatlButton(
                title: changeTitle,
                role: .borderedNeutral,
                action: onChange
            )
        }
        .padding(12)
        .frame(width: 380, alignment: .leading)
        .background(ShatlColor.onboardingForeground)
        .clipShape(RoundedRectangle(cornerRadius: ShatlCornerRadius.container, style: .continuous))
        .shatlShadow(ShatlShadow.onboardingCard)
    }
}

#if DEBUG
#Preview("Onboarding Flow") {
    OnboardingFlowView()
        .environmentObject(ShatlAccentState())
        .shatlTypographyProfile(localeOverride: .russian)
}
#endif
