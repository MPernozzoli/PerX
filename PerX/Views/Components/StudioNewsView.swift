import SwiftUI

struct StudioNewsView: View {
    @StateObject private var newsService = StudioNewsService.shared
    @State private var selectedNews: StudioNewsItem?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "newspaper")
                    .foregroundColor(.blue)
                Text("Notizie dello Studio")
                    .font(.headline)
                Spacer()
                
                if !newsService.news.isEmpty {
                    Text("\(newsService.newsForDashboard(limit: 50).count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            
            if newsService.news.isEmpty {
                VStack(spacing: 10) {
                    Text("Le notizie dello studio appariranno qui")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Quando arrivano mail interne non legate ad un sinistro, le trasformiamo in un box cliccabile con eventuali CTA.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)
                .padding(.bottom)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(newsService.newsForDashboard(limit: 50)) { item in
                            Button {
                                selectedNews = item
                            } label: {
                                NewsCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .sheet(item: $selectedNews) { news in
            StudioNewsDetailView(
                news: news,
                onScheduleCTA: {
                    newsService.scheduleCTA(for: news)
                }
            )
        }
    }
}

private struct NewsCard: View {
    let item: StudioNewsItem
    @StateObject private var profileService = UserProfileService.shared
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar per compleanni, icona per altri
            if item.isBirthday, let userEmail = item.userEmail {
                AvatarView(profile: profileService.profile(for: userEmail), size: 36)
            } else {
                Image(systemName: item.icon)
                    .font(.title2)
                    .foregroundColor(iconColor)
                    .frame(width: 36, height: 36)
                    .background(iconColor.opacity(0.15))
                    .clipShape(Circle())
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(item.summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                if !item.isBirthday {
                    Text(dateString)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if item.cta != nil {
                Image(systemName: "bolt.circle")
                    .foregroundColor(.orange)
            }
        }
        .padding()
        .background(cardBackground)
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
        .overlay {
            if item.isBirthday {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        LinearGradient(
                            colors: [.pink, .purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            }
        }
    }
    
    private var iconColor: Color {
        switch item.newsType {
        case .birthday: return .pink
        case .event: return .orange
        case .announcement: return .purple
        case .general: return .blue
        }
    }
    
    private var cardBackground: some View {
        Group {
            if item.isBirthday {
                LinearGradient(
                    colors: [
                        Color.pink.opacity(0.08),
                        Color.purple.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                Color(NSColor.controlBackgroundColor)
            }
        }
    }
    
    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        if let eventDate = item.eventDate {
            return formatter.string(from: eventDate)
        }
        return formatter.string(from: item.createdAt)
    }
}

private struct StudioNewsDetailView: View {
    let news: StudioNewsItem
    let onScheduleCTA: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: news.icon)
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(news.title)
                        .font(.title3)
                        .fontWeight(.semibold)
                    if let sender = news.sender {
                        Text(sender)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button("Chiudi") { dismiss() }
                    .buttonStyle(.bordered)
            }
            
            if let eventDate = news.eventDate {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                    Text(dateFormatter.string(from: eventDate))
                    Spacer()
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            ScrollView {
                Text(news.sourceBody ?? news.summary)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 260)
            
            if let cta = news.cta {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Azione suggerita")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Button(action: {
                        onScheduleCTA()
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cta.title)
                                if let deadline = cta.deadline {
                                    Text("Scadenza: \(dateFormatter.string(from: deadline))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            
            Spacer()
        }
        .padding()
        .frame(minWidth: 400, minHeight: 320)
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
}

