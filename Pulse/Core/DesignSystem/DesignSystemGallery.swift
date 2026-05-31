import SwiftUI

#if DEBUG
/// DEBUG-only gallery used as the UI-test host for the design-system primitives.
/// Presented when the app launches with `-uiTestGallery` (see AppShell).
struct DesignSystemGallery: View {
    @Environment(Theme.self) private var theme
    @State private var sheetOpen = false
    @State private var fired = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("DESIGN SYSTEM").pulseStyle(.eyebrow).foregroundStyle(theme.inkSoft)

                Lockup(value: "7", top: "DAY 23", bottom: "Chest & Tris.", size: 96)
                    .padding(18)
                    .background(theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.ink, lineWidth: 2))
                    .accessibilityIdentifier("gallery-lockup")

                Lockup(value: "0", top: "TO FAILURE", bottom: "Reps", size: 96, failure: true)
                    .accessibilityIdentifier("gallery-lockup-failure")

                Button("Start →") { fired += 1 }
                    .buttonStyle(PressableButtonStyle(variant: .primary, size: .lg))
                    .accessibilityIdentifier("gallery-primary-lg")
                Button("Log set →") { fired += 1 }
                    .buttonStyle(PressableButtonStyle(variant: .primary, size: .md))
                    .accessibilityIdentifier("gallery-primary-md")
                Button("Skip") { fired += 1 }
                    .buttonStyle(PressableButtonStyle(variant: .primary, size: .sm))
                    .accessibilityIdentifier("gallery-primary-sm")
                Button("Cancel") { fired += 1 }
                    .buttonStyle(PressableButtonStyle(variant: .secondary, size: .md))
                    .accessibilityIdentifier("gallery-secondary")
                Button("Disabled") { fired += 1 }
                    .buttonStyle(PressableButtonStyle(variant: .primary, size: .md))
                    .disabled(true)
                    .accessibilityIdentifier("gallery-disabled")

                Text("Fired: \(fired)")
                    .pulseStyle(.rowSub).foregroundStyle(theme.inkSoft)
                    .accessibilityIdentifier("gallery-fired-count")

                Button("Open sheet") { sheetOpen = true }
                    .buttonStyle(PressableButtonStyle(variant: .primary, size: .md))
                    .accessibilityIdentifier("gallery-open-sheet")

                // Palette picker (Task 9).
                PaletteView()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg)
        .fadeInOnMount(id: theme.palette)
        .pulseSheet(isPresented: $sheetOpen, eyebrow: "EDIT", title: "Set editor.") {
            Text("Sheet body").pulseStyle(.rowName).foregroundStyle(theme.ink)
                .accessibilityIdentifier("sheet-body")
        }
        .accessibilityIdentifier("design-system-gallery")
    }
}
#endif
