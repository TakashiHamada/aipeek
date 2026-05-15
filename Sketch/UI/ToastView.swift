import SwiftUI

struct ToastView: View {
    let message: ToastMessage

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(accentDotColor)
                .frame(width: 8, height: 8)
            Text(message.text)
                .font(.callout)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.toolInactive, in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 2)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityLabel(message.text)
    }

    /// A small dot keeps semantic feedback (success/error/etc.) without breaking
    /// the unified espresso background.
    private var accentDotColor: Color {
        switch message.kind {
        case .success: return Color(red: 0.55, green: 0.82, blue: 0.50)
        case .info:    return .white.opacity(0.55)
        case .warning: return Theme.action
        case .error:   return Color(red: 0.96, green: 0.45, blue: 0.40)
        }
    }
}
