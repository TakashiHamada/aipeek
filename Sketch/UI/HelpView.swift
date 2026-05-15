import SwiftUI

struct HelpView: View {
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text("ヘルプ")
                        .font(.title2.bold())
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Text("ツール")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 10) {
                    iconRow(systemImage: "pencil.tip", label: "ペン", shortcut: "P")
                    iconRow(systemImage: "eraser", label: "消しゴム", shortcut: "E")
                    iconRow(systemImage: "doc.badge.plus", label: "新規", shortcut: "⌘N")
                    iconRow(systemImage: "questionmark", label: "このヘルプ", shortcut: nil)
                    iconRow(systemImage: "gear", label: "環境設定", shortcut: "⌘,")
                }
                .font(.callout)

                Divider()

                Text("その他のショートカット")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 8) {
                    shortcutRow(label: "取り消す", keys: "⌘Z")
                    shortcutRow(label: "やり直す", keys: "⌘⇧Z")
                }
                .font(.callout)
            }
            .padding(24)
            .frame(maxWidth: 480)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 10)
            .padding(40)
        }
    }

    @ViewBuilder
    private func iconRow(systemImage: String, label: String, shortcut: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Theme.toolInactive, in: Circle())
            Text(label)
            Spacer()
            if let shortcut {
                Text(shortcut)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
            }
        }
    }

    @ViewBuilder
    private func shortcutRow(label: String, keys: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(keys)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
        }
    }
}
