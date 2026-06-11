import SwiftUI

struct WatchSetView: View {
    let model: WatchSessionModel

    var body: some View {
        let s = model.snapshot
        VStack(alignment: .leading, spacing: 6) {
            if let ss = s.ssLabel {
                Text(ss).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
            }
            Text(s.exerciseName).font(.headline).lineLimit(2)
            Text("SET \(s.setIndex) OF \(s.totalSets)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(model.repsLabel).font(.system(size: 34, weight: .bold))
                Text("reps").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(model.weightLabel).font(.title3.bold())
            }
            .padding(.vertical, 2)
            Button("Log set") { model.logSet() }
                .buttonStyle(.borderedProminent)
            Button("Skip set") { model.skipSet() }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 4)
    }
}
