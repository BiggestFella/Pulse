import SwiftUI

/// Styled chrome for a bottom sheet's content: drag handle, eyebrow+title+✕
/// header, and a scrollable body. Wrap your sheet content in this.
struct SheetChrome<Content: View>: View {
    let eyebrow: String
    let title: String
    let onClose: () -> Void
    @ViewBuilder var content: () -> Content
    @Environment(Theme.self) private var theme

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(theme.inkFaint)
                .frame(width: 42, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 8)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(eyebrow).pulseStyle(.eyebrow).foregroundStyle(theme.inkSoft)
                    Text(title).pulseStyle(.h1).foregroundStyle(theme.ink)
                }
                Spacer()
                Button(action: onClose) { Text("✕") }
                    .buttonStyle(IconButtonStyle())
                    .accessibilityIdentifier("sheet-close")
            }
            .padding(.horizontal, 18)
            ScrollView {
                content().padding(.horizontal, 18).padding(.top, 6)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bg)
        .overlay(alignment: .top) {
            // 2px ink border, no bottom edge; 26pt top corners.
            UnevenRoundedRectangle(topLeadingRadius: theme.radiusSheet,
                                   topTrailingRadius: theme.radiusSheet)
                .stroke(theme.ink, lineWidth: 2)
                .ignoresSafeArea(edges: .bottom)
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: theme.radiusSheet,
                                          topTrailingRadius: theme.radiusSheet))
    }
}

private struct PulseSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let eyebrow: String
    let title: String
    @ViewBuilder var sheetContent: () -> SheetContent
    @Environment(Theme.self) private var theme

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            SheetChrome(eyebrow: eyebrow, title: title,
                        onClose: { isPresented = false }) {
                sheetContent()
            }
            .environment(theme)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden) // we draw our own handle
            .presentationBackground(.clear)     // scrim/background is ours
            .accessibilityIdentifier("pulse-sheet")
        }
    }
}

extension View {
    /// Present a styled Pulse bottom sheet. Tapping outside (system scrim) or the
    /// ✕ dismisses it.
    func pulseSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        eyebrow: String,
        title: String,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        modifier(PulseSheetModifier(isPresented: isPresented,
                                    eyebrow: eyebrow, title: title,
                                    sheetContent: content))
    }
}

#Preview("BottomSheet") {
    struct Demo: View {
        @State private var open = false
        let theme = Theme()
        var body: some View {
            VStack {
                Button("Open sheet") { open = true }
                    .buttonStyle(PressableButtonStyle(variant: .primary, size: .md))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.bg)
            .environment(theme)
            .pulseSheet(isPresented: $open, eyebrow: "EDIT", title: "Set editor.") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<6) { i in
                        Text("Set \(i + 1)").pulseStyle(.rowName).foregroundStyle(theme.ink)
                    }
                }
            }
        }
    }
    return Demo()
}
