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

                Text("Be the eyes of your AI.")
                    .font(.title3.weight(.semibold))

                Text("Sketch what you want to show, and it lands in your AI's hands the moment your pen lifts.")
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
