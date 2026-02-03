import SwiftUI

// MARK: - Media Viewer Tab Bar

/// Tabbar per gestione file multipli nella stessa finestra (solo stesso sinistro)
struct MediaViewerTabBar: View {
    @Binding var tabs: [MediaTab]
    @Binding var activeTabId: String
    let sinistroReference: String?
    let onTabClose: (String) -> Void
    let onTabSelect: (String) -> Void
    let onTabOpenInNewWindow: ((String) -> Void)?
    let onMergeWindows: (() -> Void)?
    
    @State private var hoveredTabId: String?
    @State private var draggedTabId: String?
    
    var body: some View {
        GlassmorphicToolbar {
            HStack(spacing: 0) {
                // Sinistro indicator
                if let reference = sinistroReference {
                    sinistroIndicator(reference: reference, onMerge: onMergeWindows)
                    
                    GlassmorphicDivider(isVertical: true)
                        .frame(height: 20)
                        .padding(.horizontal, 12)
                }
                
                // Tabs scroll view
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(tabs) { tab in
                            TabItem(
                                tab: tab,
                                isActive: tab.id == activeTabId,
                                isHovered: hoveredTabId == tab.id,
                                onSelect: {
                                    withAnimation(GlassmorphismDesignSystem.Animations.spring) {
                                        activeTabId = tab.id
                                        onTabSelect(tab.id)
                                    }
                                },
                                onClose: {
                                    withAnimation(GlassmorphismDesignSystem.Animations.spring) {
                                        onTabClose(tab.id)
                                    }
                                },
                                onOpenInNewWindow: onTabOpenInNewWindow != nil ? {
                                    onTabOpenInNewWindow?(tab.id)
                                } : nil
                            )
                            .onHover { hovering in
                                hoveredTabId = hovering ? tab.id : nil
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
                
                Spacer()
            }
        }
    }
    
    private func sinistroIndicator(reference: String, onMerge: (() -> Void)?) -> some View {
        HStack(spacing: 8) {
            // Colore distintivo basato su hash del riferimento
            Circle()
                .fill(colorForReference(reference))
                .frame(width: 10, height: 10)
                .shadow(color: colorForReference(reference).opacity(0.5), radius: 3)
            
            Text(reference)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(GlassmorphismDesignSystem.Colors.secondaryGlass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    colorForReference(reference).opacity(0.3),
                    lineWidth: 0.5
                )
        )
        .contextMenu {
            if let onMerge = onMerge {
                Button(action: onMerge) {
                    Label("Riunisci finestre", systemImage: "square.stack.3d.up")
                }
            }
        }
    }
    
    private func colorForReference(_ reference: String) -> Color {
        // Genera colore distintivo basato su hash del riferimento
        let hash = reference.hashValue
        let hue = Double(abs(hash) % 360) / 360.0
        return Color(hue: hue, saturation: 0.6, brightness: 0.8)
    }
}

// MARK: - Media Tab Model

struct MediaTab: Identifiable, Equatable {
    let id: String
    let url: URL
    var title: String
    var hasChanges: Bool = false
    
    init(url: URL, title: String? = nil) {
        self.id = url.path
        self.url = url
        self.title = title ?? url.lastPathComponent
    }
    
    var icon: String {
        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp"].contains(ext) {
            return "photo"
        } else if ext == "pdf" {
            return "doc.text"
        } else if ["mp4", "mov", "avi", "mkv", "m4v"].contains(ext) {
            return "film"
        }
        return "doc"
    }
}

// MARK: - Tab Item

struct TabItem: View {
    let tab: MediaTab
    let isActive: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onOpenInNewWindow: (() -> Void)?
    
    @State private var showCloseButton = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                // File icon
                Image(systemName: tab.icon)
                    .font(.system(size: 11))
                    .foregroundColor(isActive ? .accentColor : .secondary)
                
                // File name
                Text(tab.title)
                    .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 120)
                
                // Modified indicator
                if tab.hasChanges {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                }
                
                // Close button
                if showCloseButton || isActive {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 16, height: 16)
                            .background(
                                Circle()
                                    .fill(Color.secondary.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        isActive ? GlassmorphismDesignSystem.Colors.primaryGlass :
                        isHovered ? GlassmorphismDesignSystem.Colors.secondaryGlass :
                        Color.clear
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        isActive ? Color.accentColor.opacity(0.3) :
                        isHovered ? GlassmorphismDesignSystem.Colors.borderLight :
                        Color.clear,
                        lineWidth: isActive ? 1 : 0.5
                    )
            )
            .shadow(
                color: isActive ? GlassmorphismDesignSystem.Colors.shadowLight : .clear,
                radius: 4,
                x: 0,
                y: 2
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(GlassmorphismDesignSystem.Animations.quickSpring) {
                showCloseButton = hovering
            }
        }
        .contextMenu {
            if let onOpenInNewWindow = onOpenInNewWindow {
                Button(action: onOpenInNewWindow) {
                    Label("Apri in nuova finestra", systemImage: "square.split.2x1")
                }
            }
        }
    }
}

// MARK: - Tab Keyboard Shortcuts

struct TabKeyboardShortcuts: ViewModifier {
    @Binding var tabs: [MediaTab]
    @Binding var activeTabId: String
    let onTabSelect: (String) -> Void
    
    func body(content: Content) -> some View {
        content
            .modifier(TabNumberShortcuts1to4(tabs: $tabs, activeTabId: $activeTabId, onTabSelect: onTabSelect))
            .modifier(TabNumberShortcuts5to9(tabs: $tabs, activeTabId: $activeTabId, onTabSelect: onTabSelect))
            .modifier(TabNavigationShortcuts(tabs: $tabs, activeTabId: $activeTabId, onTabSelect: onTabSelect))
    }
}

private struct TabNumberShortcuts1to4: ViewModifier {
    @Binding var tabs: [MediaTab]
    @Binding var activeTabId: String
    let onTabSelect: (String) -> Void
    
    func body(content: Content) -> some View {
        content
            .onKeyPress(KeyEquivalent("1"), modifiers: [.command]) { selectTab(0); return .handled }
            .onKeyPress(KeyEquivalent("2"), modifiers: [.command]) { selectTab(1); return .handled }
            .onKeyPress(KeyEquivalent("3"), modifiers: [.command]) { selectTab(2); return .handled }
            .onKeyPress(KeyEquivalent("4"), modifiers: [.command]) { selectTab(3); return .handled }
    }
    
    private func selectTab(_ index: Int) {
        guard index < tabs.count else { return }
        activeTabId = tabs[index].id
        onTabSelect(tabs[index].id)
    }
}

private struct TabNumberShortcuts5to9: ViewModifier {
    @Binding var tabs: [MediaTab]
    @Binding var activeTabId: String
    let onTabSelect: (String) -> Void
    
    func body(content: Content) -> some View {
        content
            .onKeyPress(KeyEquivalent("5"), modifiers: [.command]) { selectTab(4); return .handled }
            .onKeyPress(KeyEquivalent("6"), modifiers: [.command]) { selectTab(5); return .handled }
            .onKeyPress(KeyEquivalent("7"), modifiers: [.command]) { selectTab(6); return .handled }
            .onKeyPress(KeyEquivalent("8"), modifiers: [.command]) { selectTab(7); return .handled }
            .onKeyPress(KeyEquivalent("9"), modifiers: [.command]) { selectTab(8); return .handled }
    }
    
    private func selectTab(_ index: Int) {
        guard index < tabs.count else { return }
        activeTabId = tabs[index].id
        onTabSelect(tabs[index].id)
    }
}

private struct TabNavigationShortcuts: ViewModifier {
    @Binding var tabs: [MediaTab]
    @Binding var activeTabId: String
    let onTabSelect: (String) -> Void
    
    func body(content: Content) -> some View {
        content
            .onKeyPress(KeyEquivalent("]"), modifiers: [.command, .shift]) { selectNextTab(); return .handled }
            .onKeyPress(KeyEquivalent("["), modifiers: [.command, .shift]) { selectPreviousTab(); return .handled }
    }
    
    private func selectNextTab() {
        guard let currentIndex = tabs.firstIndex(where: { $0.id == activeTabId }) else { return }
        let nextIndex = (currentIndex + 1) % tabs.count
        selectTab(nextIndex)
    }
    
    private func selectPreviousTab() {
        guard let currentIndex = tabs.firstIndex(where: { $0.id == activeTabId }) else { return }
        let prevIndex = currentIndex == 0 ? tabs.count - 1 : currentIndex - 1
        selectTab(prevIndex)
    }
    
    private func selectTab(_ index: Int) {
        guard index < tabs.count else { return }
        activeTabId = tabs[index].id
        onTabSelect(tabs[index].id)
    }
}

extension View {
    @ViewBuilder
    func onKeyPress(
        _ key: KeyEquivalent,
        modifiers requiredModifiers: EventModifiers = [],
        phases: KeyPress.Phases = .down,
        _ action: @escaping () -> KeyPress.Result
    ) -> some View {
        self.onKeyPress(key, phases: phases) { press in
            // `press.modifiers` can include extra flags (e.g. .numericPad). We only require the requested ones.
            guard press.modifiers.contains(requiredModifiers) else { return .ignored }
            return action()
        }
    }

    func tabKeyboardShortcuts(
        tabs: Binding<[MediaTab]>,
        activeTabId: Binding<String>,
        onTabSelect: @escaping (String) -> Void
    ) -> some View {
        modifier(TabKeyboardShortcuts(
            tabs: tabs,
            activeTabId: activeTabId,
            onTabSelect: onTabSelect
        ))
    }
}
