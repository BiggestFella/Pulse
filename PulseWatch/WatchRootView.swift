import SwiftUI

struct WatchRootView: View {
    let model: WatchSessionModel

    var body: some View {
        switch model.snapshot.phase {
        case .active:
            WatchSetView(model: model)
        case .rest:
            WatchRestView(model: model)
        case .idle, .summary:
            WatchIdleView()
        }
    }
}

struct WatchIdleView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone").font(.title2).foregroundStyle(.secondary)
            Text("Open Pulse on your phone to start a workout")
                .font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .padding()
    }
}
