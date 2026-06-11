import SwiftUI

struct WatchRestView: View {
    let model: WatchSessionModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let s = model.snapshot
            let remaining = s.remainingRest(now: context.date)
            let fraction = s.restFraction(now: context.date)
            VStack(spacing: 8) {
                ZStack {
                    Circle().stroke(.gray.opacity(0.3), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(.tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(timeString(remaining)).font(.system(size: 30, weight: .bold))
                }
                .frame(width: 92, height: 92)

                HStack(spacing: 4) {
                    chip("−15") { model.adjustRest(-15) }
                    chip("+15") { model.adjustRest(15) }
                    chip("+30") { model.adjustRest(30) }
                }
                Button("Skip") { model.skipRest() }
                    .buttonStyle(.bordered)
                if let next = s.nextExerciseName {
                    Text("UP NEXT · \(next)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func chip(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .font(.system(.caption2, design: .monospaced))
            .buttonStyle(.bordered)
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t.rounded()); return String(format: "%d:%02d", s / 60, s % 60)
    }
}
