import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("環境設定")
                    .font(.title2.bold())
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $settings.autoSave) {
                    Text("オートセーブ")
                        .font(.headline)
                }
                .toggleStyle(.switch)
                Text("描き始めると自動でファイルが作成され、変更のたびに上書き保存されます。ファイル名はセッション中固定なので、Claude Code 等に一度パスを渡せば以降は最新の絵がそのまま読まれます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $settings.autoCopyOnSave) {
                    Text("編集終了時に画像をクリップボードへ自動コピー")
                        .font(.headline)
                }
                .toggleStyle(.switch)
                .disabled(!settings.autoSave)
                Text("ストロークを描き終えて 500ms 後に、保存される PNG と保存先パスを同時にクリップボードへ送ります。OFF の場合はパスのみがクリップボードに入ります(他アプリでコピーした画像を上書きしません)。オートセーブ OFF のときは無効です。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("セッション履歴の保持")
                    .font(.headline)
                Picker("保持日数", selection: $settings.retentionDays) {
                    Text("削除しない(-1)").tag(-1)
                    Text("すべて削除(0)").tag(0)
                    ForEach(1...30, id: \.self) { n in
                        Text("\(n) 日").tag(n)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 240)
                Text("起動時に最新 N 日分のセッションフォルダだけ残します。実行中は削除されません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("保存先")
                    .font(.headline)
                TextField("", text: $settings.customSessionsRoot, prompt: Text("既定の保存先を使う"))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.callout, design: .monospaced))
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                HStack(spacing: 8) {
                    Button("既定に戻す") {
                        settings.customSessionsRoot = ""
                    }
                    .disabled(settings.customSessionsRoot.isEmpty)
                    Spacer()
                    Text("ファイル名: sketch_HH-MM-SS.png")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Text("空欄なら既定 (~/Library/Application Support/com.giftten.aipeek/sessions) を使います。`~` は展開されます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(width: 560, height: 660, alignment: .topLeading)
    }
}
