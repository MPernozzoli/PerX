import SwiftUI

struct ActiveCallBanner: View {
    @ObservedObject private var session = CallSessionService.shared

    var body: some View {
        if session.activeSessionId != nil {
            HStack(spacing: 10) {
                Image(systemName: "waveform.circle.fill")
                    .foregroundStyle(.white)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Chiamata in corso").font(.caption.bold()).foregroundStyle(.white)
                    Text(session.roomState.capitalized).font(.caption2).foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Button {
                    Task { await session.endActive() }
                } label: {
                    Image(systemName: "phone.down.fill")
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Color.red)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.green.gradient)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 8)
            .padding(.bottom, 2)
        }
    }
}
