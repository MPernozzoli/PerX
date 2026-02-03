import SwiftUI

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let canClose: Bool
    let onSelect: () -> Void
    let onClose: (() -> Void)?
    let icon: String?
    let isSuggested: Bool
    let badgeCount: Int?
    
    init(title: String, isSelected: Bool, canClose: Bool, onSelect: @escaping () -> Void, onClose: (() -> Void)? = nil, icon: String? = nil, isSuggested: Bool = false, badgeCount: Int? = nil) {
        self.title = title
        self.isSelected = isSelected
        self.canClose = canClose
        self.onSelect = onSelect
        self.onClose = onClose
        self.icon = icon
        self.isSuggested = isSuggested
        self.badgeCount = badgeCount
    }
    
    private var tabIcon: String {
        if let icon = icon {
            return icon
        }
        
        switch title {
        case "Sinistri":
            return "list.bullet"
        case "Dettagli":
            return "info.circle"
        case "Diario":
            return "book.closed"
        case "Fulminazione":
            return "bolt.fill"
        case "Cartella":
            return "folder"
        case "Perizia":
            return "doc.text"
        default:
            return ""
        }
    }
    
    var body: some View {
        HStack(spacing: 6) {
            if !tabIcon.isEmpty {
                Image(systemName: tabIcon)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? 
                        Color(red: 0.15, green: 0.55, blue: 0.85) : 
                        Color(NSColor.secondaryLabelColor))
            }
            
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .lineLimit(1)
                .foregroundColor(isSelected ? 
                    Color(red: 0.15, green: 0.55, blue: 0.85) : 
                    Color(NSColor.secondaryLabelColor))
            
            if canClose && title != "Dettagli" {
                Button(action: { onClose?() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(isSelected ? 
                            Color(red: 0.15, green: 0.55, blue: 0.85) : 
                            .secondary)
                }
                .buttonStyle(.plain)
                .opacity(isSelected ? 1 : 0)
                .padding(.leading, 4)
            }
            
            // Badge notifiche (se presente e > 0)
            if let count = badgeCount, count > 0 {
                Text(count > 99 ? "99+" : "\(count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.red)
                    )
                    .padding(.leading, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(
            Group {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.92, green: 0.96, blue: 1.0).opacity(0.95),
                                    Color(red: 0.88, green: 0.94, blue: 1.0).opacity(0.9)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(red: 0.65, green: 0.8, blue: 0.95).opacity(0.5),
                                            Color(red: 0.5, green: 0.7, blue: 0.9).opacity(0.3)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.5
                                )
                        )
                        .shadow(color: Color(red: 0.15, green: 0.55, blue: 0.85).opacity(0.15), radius: 3, x: 0, y: 1)
                        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 0)
                } else if isSuggested {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    Color(NSColor.secondaryLabelColor).opacity(0.3),
                                    style: StrokeStyle(lineWidth: 0.5, dash: [3, 2])
                                )
                        )
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    Color(NSColor.separatorColor).opacity(0.4),
                                    lineWidth: 0.5
                                )
                        )
                }
            }
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture(perform: onSelect)
    }
} 