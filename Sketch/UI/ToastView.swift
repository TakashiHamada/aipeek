import SwiftUI

struct ToastView: View {
    let message: ToastMessage

    var body: some View {
        Text(message.text)
            .font(.callout)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .foregroundStyle(.white)
            .background(backgroundColor, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 2)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityLabel(message.text)
    }

    private var backgroundColor: Color {
        switch message.kind {
        case .success: return .green.opacity(0.85)
        case .info: return .gray.opacity(0.85)
        case .warning: return .orange.opacity(0.9)
        case .error: return .red.opacity(0.9)
        }
    }
}
