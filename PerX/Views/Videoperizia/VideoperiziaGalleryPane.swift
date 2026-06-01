import SwiftUI

/// Anteprima delle foto/clip catturate durante la videoperizia.
/// Usa lo `signed_url` di Supabase per il rendering.
@MainActor
struct VideoperiziaGalleryPane: View {
    let media: [VideoperiziaMediaDTO]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Catturati")
                    .font(.headline)
                Spacer()
                Text("\(media.count)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if media.isEmpty {
                Text("Nessuna cattura ancora.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(media) { item in
                        VideoperiziaMediaThumb(item: item)
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.windowBackgroundColorCompat))
    }
}

private struct VideoperiziaMediaThumb: View {
    let item: VideoperiziaMediaDTO

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let urlString = item.signed_url, let url = URL(string: urlString), !item.isClip {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:    ProgressView()
                        case .success(let image): image.resizable().scaledToFill()
                        case .failure:  Image(systemName: "photo")
                        @unknown default: EmptyView()
                        }
                    }
                } else {
                    Image(systemName: item.isClip ? "video.fill" : "photo")
                        .font(.title2).foregroundStyle(.tint)
                }
            }
            .frame(width: 96, height: 72)
            .clipped()

            if item.processing_status != "done" {
                Text(processingLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(Color.black.opacity(0.6))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .padding(4)
            }
        }
        .frame(width: 96, height: 72)
        .background(Color.windowBackgroundColorCompat)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var processingLabel: String {
        switch item.processing_status {
        case "pending_hub": return "in coda"
        case "processing": return "IA…"
        case "failed":     return "errore"
        default:           return item.processing_status
        }
    }
}

private extension Color {
    static var windowBackgroundColorCompat: Color {
        #if os(macOS)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(uiColor: .secondarySystemBackground)
        #endif
    }
}
