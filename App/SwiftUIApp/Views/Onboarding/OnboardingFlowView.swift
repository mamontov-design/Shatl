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
                renderingMode: .glass,
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

#if DEBUG
#Preview("Onboarding Flow") {
    OnboardingFlowView()
        .environmentObject(ShatlAccentState())
        .shatlTypographyProfile(localeOverride: .russian)
        .frame(width: OnboardingWindowLayout.windowSize.width, height: OnboardingWindowLayout.windowSize.height)
}
#endif
