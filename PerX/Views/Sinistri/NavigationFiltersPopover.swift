import SwiftUI

// MARK: - Navigation Scope

enum NavigationScope: String, CaseIterable {
    case currentFolder = "Cartella Corrente"
    case sinistroDirectory = "Tutto il Sinistro"
    
    var icon: String {
        switch self {
        case .currentFolder: return "folder"
        case .sinistroDirectory: return "folder.fill.badge.questionmark"
        }
    }
}

// MARK: - Type Filter

enum TypeFilter: String, CaseIterable {
    case all = "Tutti"
    case pdf = "PDF"
    case media = "Media"
    
    var icon: String {
        switch self {
        case .all: return "doc.on.doc"
        case .pdf: return "doc.text"
        case .media: return "photo.on.rectangle"
        }
    }
}

// MARK: - Tag Filter

enum TagFilter: String, CaseIterable {
    case all = "Tutti"
    case tagged = "Taggati"
    case untagged = "Non Taggati"
    
    var icon: String {
        switch self {
        case .all: return "tag"
        case .tagged: return "tag.fill"
        case .untagged: return "tag.slash"
        }
    }
}

// MARK: - Navigation Filters Popover

struct NavigationFiltersPopover: View {
    @Binding var navigationScope: NavigationScope
    @Binding var typeFilter: TypeFilter
    @Binding var tagFilter: TagFilter
    
    let totalFiles: Int
    let filteredCount: Int
    let onReset: () -> Void
    
    @State private var isAnimating = false
    
    init(
        navigationScope: Binding<NavigationScope>,
        typeFilter: Binding<TypeFilter>,
        tagFilter: Binding<TagFilter>,
        totalFiles: Int = 0,
        filteredCount: Int = 0,
        onReset: @escaping () -> Void = {}
    ) {
        self._navigationScope = navigationScope
        self._typeFilter = typeFilter
        self._tagFilter = tagFilter
        self.totalFiles = totalFiles
        self.filteredCount = filteredCount
        self.onReset = onReset
    }
    
    var body: some View {
        GlassmorphicPopover {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                headerView
                
                GlassmorphicDivider()
                
                // Scope Navigation
                scopeSection
                
                // Type Filter
                typeSection
                
                // Tag Filter
                tagSection
                
                GlassmorphicDivider()
                
                // Footer con conteggio e reset
                footerView
            }
            .frame(width: 280)
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14))
                    .foregroundColor(.accentColor)
                
                Text("Filtri Navigazione")
                    .font(.system(size: 15, weight: .semibold))
            }
            
            Spacer()
        }
    }
    
    // MARK: - Scope Section
    
    private var scopeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Scope")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            HStack(spacing: 8) {
                ForEach(NavigationScope.allCases, id: \.self) { scope in
                    FilterChip(
                        title: scope == .currentFolder ? "Cartella" : "Sinistro",
                        icon: scope.icon,
                        isSelected: navigationScope == scope,
                        color: .accentColor
                    ) {
                        withAnimation(GlassmorphismDesignSystem.Animations.spring) {
                            navigationScope = scope
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Type Section
    
    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tipo File")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            HStack(spacing: 8) {
                ForEach(TypeFilter.allCases, id: \.self) { type in
                    FilterChip(
                        title: type.rawValue,
                        icon: type.icon,
                        isSelected: typeFilter == type,
                        color: colorForType(type)
                    ) {
                        withAnimation(GlassmorphismDesignSystem.Animations.spring) {
                            typeFilter = type
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Tag Section
    
    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tag")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
            
            HStack(spacing: 8) {
                ForEach(TagFilter.allCases, id: \.self) { tag in
                    FilterChip(
                        title: tag.rawValue,
                        icon: tag.icon,
                        isSelected: tagFilter == tag,
                        color: colorForTag(tag)
                    ) {
                        withAnimation(GlassmorphismDesignSystem.Animations.spring) {
                            tagFilter = tag
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            // Conteggio file
            HStack(spacing: 6) {
                Image(systemName: "doc")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                Text("\(filteredCount)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .contentTransition(.numericText())
                
                Text("di \(totalFiles)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .animation(GlassmorphismDesignSystem.Animations.spring, value: filteredCount)
            
            Spacer()
            
            // Reset button
            if hasActiveFilters {
                GlassmorphicButton(title: "Reset", icon: "arrow.counterclockwise") {
                    withAnimation(GlassmorphismDesignSystem.Animations.spring) {
                        navigationScope = .currentFolder
                        typeFilter = .all
                        tagFilter = .all
                        onReset()
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private var hasActiveFilters: Bool {
        navigationScope != .currentFolder || typeFilter != .all || tagFilter != .all
    }
    
    private func colorForType(_ type: TypeFilter) -> Color {
        switch type {
        case .all: return .accentColor
        case .pdf: return .red
        case .media: return .green
        }
    }
    
    private func colorForTag(_ tag: TagFilter) -> Color {
        switch tag {
        case .all: return .accentColor
        case .tagged: return .orange
        case .untagged: return .gray
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isSelected ? color :
                        isHovered ? GlassmorphismDesignSystem.Colors.primaryGlass :
                        GlassmorphismDesignSystem.Colors.secondaryGlass
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? color.opacity(0.5) :
                        isHovered ? color.opacity(0.3) :
                        GlassmorphismDesignSystem.Colors.borderLight,
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
            .shadow(
                color: isSelected ? color.opacity(0.3) : .clear,
                radius: 4,
                x: 0,
                y: 2
            )
            .scaleEffect(isHovered && !isSelected ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(GlassmorphismDesignSystem.Animations.quickSpring) {
                isHovered = hovering
            }
        }
    }
}
