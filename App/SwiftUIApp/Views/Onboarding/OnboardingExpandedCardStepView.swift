// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

struct OnboardingExpandedCardPresentationView: View {
    var localeOverride: AppLocaleOverride = .russian
    var metricsMode: MetricsPresentationMode = .simplified
    var initiallyExpanded = false
    var centersExpandedCard = false
    var allowsExpansionToggle = true
    var pulsesMetricSetOutlines = false

    init(
        localeOverride: AppLocaleOverride = .russian,
        metricsMode: MetricsPresentationMode = .simplified,
        initiallyExpanded: Bool = false,
        centersExpandedCard: Bool = false,
        allowsExpansionToggle: Bool = true,
        pulsesMetricSetOutlines: Bool = false
    ) {
        self.localeOverride = localeOverride
        self.metricsMode = metricsMode
        self.initiallyExpanded = initiallyExpanded
        self.centersExpandedCard = centersExpandedCard
        self.allowsExpansionToggle = allowsExpansionToggle
        self.pulsesMetricSetOutlines = pulsesMetricSetOutlines
    }

    var body: some View {
        TorrentCardPreviewView(
            localeOverride: localeOverride,
            metricsMode: metricsMode,
            initiallyExpanded: initiallyExpanded,
            centersExpandedCard: centersExpandedCard,
            allowsExpansionToggle: allowsExpansionToggle,
            showsExpansionToggle: true,
            pulsesMetricSetOutlines: pulsesMetricSetOutlines,
            usesProductionProgressColors: true,
            usesProductionCardColors: true,
            cardOutlineColorOverride: .clear
        )
    }
}

#if DEBUG
#Preview("Expanded Card Step") {
    OnboardingExpandedCardPresentationView()
        .frame(width: 440, height: 300)
        .background(ShatlColor.onboardingBackground)
        .shatlTypographyProfile(localeOverride: .russian)
}
#endif
