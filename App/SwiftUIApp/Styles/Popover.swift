// SPDX-FileCopyrightText: 2026 Mamontov Design
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

extension View {
    /// A popover whose content speaks its window's language. On macOS a
    /// popover keeps every value its window was given but the locale, which
    /// it takes from the system: with the language chosen in Debug its texts
    /// stayed in the system's language (found 2026-11-12; `PopoverLocaleTests`).
    func shatlPopover<PopoverContent: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> PopoverContent
    ) -> some View {
        modifier(ShatlLocalePopover(isPresented: isPresented, popoverContent: content))
    }
}

private struct ShatlLocalePopover<PopoverContent: View>: ViewModifier {
    @Environment(\.locale) private var locale
    @Binding var isPresented: Bool
    let popoverContent: () -> PopoverContent

    func body(content: Content) -> some View {
        content.popover(isPresented: $isPresented) {
            popoverContent()
                .environment(\.locale, locale)
        }
    }
}
