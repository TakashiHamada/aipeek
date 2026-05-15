import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var settings: AppSettings
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Preferences")
                        .font(.title2.bold())
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: $settings.autoSave) {
                        Text("Auto save")
                            .font(.headline)
                    }
                    .toggleStyle(.switch)
                    Text("Save the sketch automatically as you draw.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: $settings.autoCopyOnSave) {
                        Text("Copy to clipboard on save")
                            .font(.headline)
                    }
                    .toggleStyle(.switch)
                    .disabled(!settings.autoSave)
                    Text("Send the image + path. Off: path only.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("History")
                        .font(.headline)
                    HStack(spacing: 10) {
                        TextField("", value: $settings.retentionDays, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.callout, design: .monospaced))
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $settings.retentionDays, in: -1...3650)
                            .labelsHidden()
                        Text("days")
                            .foregroundStyle(.secondary)
                    }
                    Text("Keep recent N days. -1 = keep all, 0 = delete all.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Save location")
                        .font(.headline)
                    HStack(spacing: 8) {
                        TextField("", text: $settings.customSessionsRoot)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.callout, design: .monospaced))
                            .autocorrectionDisabled(true)
                            .textInputAutocapitalization(.never)
                        Button {
                            settings.resetSessionsRootToDefault()
                        } label: {
                            Label("Reset", systemImage: "arrow.uturn.backward")
                                .labelStyle(.titleAndIcon)
                        }
                        .help("Reset to default save location")
                    }
                    Text("Folder for PNG files. `~` = home.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .frame(maxWidth: 540)
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
