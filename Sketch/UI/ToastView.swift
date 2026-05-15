import SwiftUI

struct ToastView: View {
    let message: ToastMessage

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(accentDotColor)
                .frame(width: 6, height: 6)
            Text(message.text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.toolInactive.opacity(0.88), in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 1)
        .accessibilityLabel(message.text)
    }

    private var accentDotColor: Color {
        switch message.kind {
        case .success: return Color(red: 0.42, green: 0.82, blue: 0.40)   // green
        case .info:    return .white.opacity(0.55)
        case .warning: return Theme.action                                 // mustard
        case .error:   return Color(red: 0.96, green: 0.25, blue: 0.22)   // saturated red
        }
    }
}
