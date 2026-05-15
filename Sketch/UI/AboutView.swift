import SwiftUI

struct AboutView: View {
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text("AIPeek")
                        .font(.title.bold())
                    Text("ver 1.0")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Text("マウスでさっと描いたスケッチを、Claude Code / Claude.ai / Discord などへ素早く共有するための軽量ツールです。オートセーブONの場合、編集が終わる(描き終わって 500ms 後)たびにファイルが自動保存され、画像とパスがクリップボードへ送られます。Claude Code には一度貼ればその後は「もう一度見て」だけで最新の絵が読まれます。画像を直接貼り付けたいアプリ(Discord / Claude.ai 等)へも、描き終えてすぐ ⌘V するだけで共有できます。")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                Text("ツール")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 10) {
                    iconRow(systemImage: "pencil.tip", label: "ペン(P)")
                    iconRow(systemImage: "eraser", label: "消しゴム(E)")
                    iconRow(systemImage: "doc.badge.plus", label: "新規(⌘N) — キャンバスをクリアして新しいファイル名を予約")
                    iconRow(systemImage: "questionmark", label: "このヘルプ")
                    iconRow(systemImage: "gear", label: "環境設定(⌘,)")
                }
                .font(.callout)

                Divider()

                Text("保存先")
                    .font(.headline)
                Text("~/Library/Application Support/com.giftten.aipeek/sessions/YYYY-MM-DD/sketch_HH-MM-SS.png")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Built with SwiftUI + PencilKit on Mac Catalyst.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("© 2026 gift10  /  Takashi Hamada")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: 460)
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
    private func iconRow(systemImage: String, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Theme.toolInactive, in: Circle())
            Text(label)
        }
    }
}
