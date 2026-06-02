import SwiftUI

struct SwapSheet: View {
    let model: ActiveWorkoutModel
    @Environment(Theme.self) private var theme
    @State private var alts: [Exercise] = []

    private var exIdx: Int { model.currentStep.exIdx }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            Text("SWAP EXERCISE")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(theme.inkSoft)
            Text("By muscle group")
                .font(.title3.bold()).foregroundStyle(theme.ink)

            row(name: model.displayName(forExercise: exIdx), tag: "NOW", action: nil, id: "swap.now")

            ForEach(Array(alts.enumerated()), id: \.offset) { i, alt in
                row(name: alt.name, tag: nil,
                    action: { model.swap(exerciseIndex: exIdx, to: alt) },
                    id: "swap.alt.\(i)")
            }
            Spacer()
        }
        .padding(theme.spacing[5])
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bg)
        .task { alts = await model.alternatives(for: exIdx) }
    }

    private func row(name: String, tag: String?, action: (() -> Void)?, id: String) -> some View {
        Button { action?() } label: {
            HStack {
                Text(name).foregroundStyle(theme.ink)
                Spacer()
                if let tag {
                    Text(tag).font(.system(.caption2, design: .monospaced)).foregroundStyle(theme.accent2)
                }
            }
            .padding(theme.spacing[2])
            .frame(maxWidth: .infinity)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusCard))
        }
        .disabled(action == nil)
        .accessibilityIdentifier(id)
    }
}
