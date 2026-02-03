//
//  iPadComponents.swift
//  PerX per iPad
//
//  Componenti riutilizzabili ottimizzati per touch.
//

import SwiftUI

// MARK: - Action Button

/// Pulsante azione grande touch-friendly
struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(color)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Info Card

/// Card per visualizzare info con icona
struct InfoCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(.subheadline.bold())
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Loading View

/// Vista loading con messaggio
struct LoadingView: View {
    let message: String
    
    init(_ message: String = "Caricamento...") {
        self.message = message
    }
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Empty State View

/// Vista stato vuoto personalizzabile
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 56))
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.title3.bold())
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            if let actionTitle = actionTitle, let action = action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Badge

/// Badge colorato per stati
struct StatusBadge: View {
    let text: String
    let color: Color
    var size: BadgeSize = .medium
    
    enum BadgeSize {
        case small, medium, large
        
        var font: Font {
            switch self {
            case .small: return .caption2
            case .medium: return .caption
            case .large: return .subheadline
            }
        }
        
        var padding: EdgeInsets {
            switch self {
            case .small: return EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6)
            case .medium: return EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
            case .large: return EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            }
        }
    }
    
    var body: some View {
        Text(text)
            .font(size.font.weight(.semibold))
            .padding(size.padding)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(size == .small ? 4 : 8)
    }
}

// MARK: - Swipe Actions Container

/// Container per azioni swipe touch-friendly
struct SwipeActionsContainer<Content: View, LeadingActions: View, TrailingActions: View>: View {
    @ViewBuilder let content: () -> Content
    @ViewBuilder let leadingActions: () -> LeadingActions
    @ViewBuilder let trailingActions: () -> TrailingActions
    
    var body: some View {
        content()
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                leadingActions()
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                trailingActions()
            }
    }
}

// MARK: - Pull to Refresh Header

/// Header personalizzato per pull to refresh
struct RefreshHeader: View {
    let lastUpdate: Date?
    let isRefreshing: Bool
    
    var body: some View {
        HStack {
            if isRefreshing {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Aggiornamento...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if let lastUpdate = lastUpdate {
                Text("Ultimo aggiornamento: \(lastUpdate, style: .relative)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}

// MARK: - Searchable Header

/// Header con ricerca
struct SearchHeader: View {
    @Binding var searchText: String
    let placeholder: String
    var onClear: (() -> Void)?
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField(placeholder, text: $searchText)
                .textFieldStyle(.plain)
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    onClear?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding()
    }
}

// MARK: - Segmented Tab Bar

/// Tab bar segmentata touch-friendly
struct SegmentedTabBar<T: Hashable>: View {
    let tabs: [(id: T, title: String, icon: String?)]
    @Binding var selected: T
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.id) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selected = tab.id
                    }
                } label: {
                    VStack(spacing: 6) {
                        if let icon = tab.icon {
                            Image(systemName: icon)
                                .font(.title3)
                        }
                        
                        Text(tab.title)
                            .font(.caption)
                    }
                    .foregroundColor(selected == tab.id ? .accentColor : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        VStack {
                            Spacer()
                            if selected == tab.id {
                                Rectangle()
                                    .fill(Color.accentColor)
                                    .frame(height: 3)
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
    }
}

// MARK: - Avatar View

/// Avatar con iniziali
struct AvatarView: View {
    let name: String
    var size: CGFloat = 40
    var backgroundColor: Color = .accentColor
    
    private var initials: String {
        let components = name.components(separatedBy: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
    
    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor.opacity(0.2))
            
            Text(initials)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundColor(backgroundColor)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Date Picker Row

/// Riga con date picker inline
struct DatePickerRow: View {
    let label: String
    @Binding var date: Date
    var displayedComponents: DatePickerComponents = [.date]
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            
            Spacer()
            
            DatePicker("", selection: $date, displayedComponents: displayedComponents)
                .labelsHidden()
        }
    }
}

// MARK: - Toggle Row

/// Riga con toggle
struct ToggleRow: View {
    let label: String
    @Binding var isOn: Bool
    var subtitle: String?
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
    }
}

// MARK: - Currency Display

/// Display formattato per valute
struct CurrencyDisplay: View {
    let value: Double
    var style: CurrencyStyle = .normal
    var showSign: Bool = false
    
    enum CurrencyStyle {
        case small, normal, large, hero
        
        var font: Font {
            switch self {
            case .small: return .caption
            case .normal: return .subheadline
            case .large: return .title3
            case .hero: return .largeTitle
            }
        }
    }
    
    private var formattedValue: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        
        if style == .hero {
            formatter.maximumFractionDigits = 0
        }
        
        let formatted = formatter.string(from: NSNumber(value: abs(value))) ?? "€0"
        
        if showSign && value != 0 {
            return value > 0 ? "+\(formatted)" : "-\(formatted)"
        }
        
        return formatted
    }
    
    private var textColor: Color {
        if !showSign { return .primary }
        if value > 0 { return .green }
        if value < 0 { return .red }
        return .primary
    }
    
    var body: some View {
        Text(formattedValue)
            .font(style.font.weight(.semibold))
            .foregroundColor(textColor)
    }
}
