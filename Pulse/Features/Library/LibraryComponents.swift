import SwiftUI

/// Tinted folder glyph using the folder's brand color.
struct FolderIcon: View {
    let color: FolderColor
    @Environment(Theme.self) private var theme
    private var tint: Color { theme.folderColor(color) }
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.18))
            Image(systemName: "folder.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 38, height: 38)
    }
}

/// Small "PR" badge.
struct PrTag: View {
    @Environment(Theme.self) private var theme
    var body: some View {
        Text("PR")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(1)
            .foregroundStyle(theme.accent2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(theme.accent2, lineWidth: 1.5))
    }
}

/// Name + sub-line block for a row.
struct RowNameBlock: View {
    let name: String
    let sub: String
    @Environment(Theme.self) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.ink)
                .lineLimit(1)
            if !sub.isEmpty {
                Text(sub)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.inkSoft)
                    .lineLimit(1)
            }
        }
    }
}

/// Standard library list row: optional leading view, content, optional trailing,
/// trailing chevron, tappable. Tap is a no-op when `onTap` is nil.
struct LibraryRow<Leading: View, Content: View>: View {
    @Environment(Theme.self) private var theme
    var onTap: (() -> Void)?
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var content: () -> Content
    var trailing: AnyView?

    init(onTap: (() -> Void)? = nil,
         @ViewBuilder leading: @escaping () -> Leading = { EmptyView() },
         @ViewBuilder content: @escaping () -> Content,
         trailing: AnyView? = nil) {
        self.onTap = onTap
        self.leading = leading
        self.content = content
        self.trailing = trailing
    }

    var body: some View {
        Button { onTap?() } label: {
            HStack(spacing: 12) {
                leading()
                content()
                Spacer()
                if let trailing { trailing }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.inkSoft)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
