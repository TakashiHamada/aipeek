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

                Text("マウスでさっと描いたスケッチを、Claude Code / Claude.ai / Discord などへ素早く共有するための軽量ツールです。")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                Text("オートセーブONの場合、編集が終わる(描き終わって 500ms 後)たびにファイルが自動保存され、画像とパスがクリップボードへ送られます。Claude Code には一度貼ればその後は「もう一度見て」だけで最新の絵が読まれます。画像を直接貼り付けたいアプリ(Discord / Claude.ai 等)へも、描き終えてすぐ ⌘V するだけで共有できます。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

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
            .padding(28)
            .frame(maxWidth: 440)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 10)
            .padding(40)
        }
    }
}
