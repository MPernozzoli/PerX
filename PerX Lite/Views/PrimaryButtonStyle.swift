import SwiftUI

/// Visible feedback on press: subtle scale + opacity change, plus haptic.
struct PrimaryButtonStyle: ButtonStyle {
    var isLoading: Bool = false
    var background: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            if isLoading {
                ProgressView().tint(.white)
            }
            configuration.label
                .font(.headline)
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(background)
                .opacity(configuration.isPressed ? 0.78 : 1.0)
        )
        .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
        .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        .onChange(of: configuration.isPressed) { _, pressed in
            if pressed {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }
}

/// Lightweight loading overlay shown over a parent view when work is in flight.
struct WorkingOverlay: View {
    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(Color(.black).opacity(0.75))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .transition(.opacity)
    }
}
