import SwiftUI
import AppKit

// MARK: - Glassmorphism Design System per macOS 26

/// Sistema di design unificato con effetti glassmorphism per tutti i componenti
struct GlassmorphismDesignSystem {
    
    // MARK: - Materials
    
    /// Materiali blur per effetti glassmorphism
    enum BlurMaterial {
        case thin
        case regular
        case thick
        case ultraThin
        
        var material: NSVisualEffectView.Material {
            switch self {
            case .ultraThin: return .hudWindow
            case .thin: return .popover
            case .regular: return .menu
            case .thick: return .sidebar
            }
        }
    }
    
    // MARK: - Colors
    
    /// Colori dinamici che si adattano a light/dark mode
    struct Colors {
        static let primaryGlass = Color(NSColor.controlBackgroundColor).opacity(0.8)
        static let secondaryGlass = Color(NSColor.windowBackgroundColor).opacity(0.7)
        static let tertiaryGlass = Color(NSColor.underPageBackgroundColor).opacity(0.6)
        
        static let borderLight = Color.white.opacity(0.2)
        static let borderDark = Color.black.opacity(0.1)
        
        static let shadowLight = Color.black.opacity(0.05)
        static let shadowDark = Color.black.opacity(0.2)
        
        static let glowAccent = Color.accentColor.opacity(0.3)
    }
    
    // MARK: - System Colors (centralizzati per evitare duplicazioni)
    
    /// Colori di sistema NSColor wrappati per SwiftUI
    struct SystemColors {
        /// Background finestra
        static let windowBackground = Color(NSColor.windowBackgroundColor)
        /// Background controlli
        static let controlBackground = Color(NSColor.controlBackgroundColor)
        /// Background testo
        static let textBackground = Color(NSColor.textBackgroundColor)
        /// Label secondaria
        static let secondaryLabel = Color(NSColor.secondaryLabelColor)
        /// Label terziaria
        static let tertiaryLabel = Color(NSColor.tertiaryLabelColor)
        /// Separatore
        static let separator = Color(NSColor.separatorColor)
        /// Grid
        static let grid = Color(NSColor.gridColor)
        /// Selezione
        static let selectedContent = Color(NSColor.selectedContentBackgroundColor)
        /// Testo selezionato
        static let selectedText = Color(NSColor.selectedTextBackgroundColor)
        /// Under page background
        static let underPageBackground = Color(NSColor.underPageBackgroundColor)
        /// Accent blu standard
        static let accentBlue = Color(red: 0.15, green: 0.55, blue: 0.85)
    }
    
    // MARK: - Typography (centralizzati per evitare duplicazioni)
    
    /// Tipografia standardizzata per l'app
    struct Typography {
        /// Body text (13pt)
        static let body = Font.system(size: 13)
        /// Body medium (13pt, medium weight)
        static let bodyMedium = Font.system(size: 13, weight: .medium)
        /// Body semibold (13pt, semibold weight)
        static let bodySemibold = Font.system(size: 13, weight: .semibold)
        /// Caption (12pt)
        static let caption = Font.system(size: 12)
        /// Caption medium (12pt, medium weight)
        static let captionMedium = Font.system(size: 12, weight: .medium)
        /// Small (11pt)
        static let small = Font.system(size: 11)
        /// Small medium (11pt, medium weight)
        static let smallMedium = Font.system(size: 11, weight: .medium)
        /// Small semibold (11pt, semibold weight)
        static let smallSemibold = Font.system(size: 11, weight: .semibold)
        /// Extra small (10pt)
        static let extraSmall = Font.system(size: 10)
        /// Title (15pt, semibold)
        static let title = Font.system(size: 15, weight: .semibold)
        /// Subtitle (14pt, medium)
        static let subtitle = Font.system(size: 14, weight: .medium)
        /// Headline (16pt, semibold)
        static let headline = Font.system(size: 16, weight: .semibold)
    }
    
    // MARK: - Spacing (centralizzati per evitare duplicazioni)
    
    /// Spaziatura standardizzata
    struct Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }
    
    // MARK: - Dimensions
    
    struct Dimensions {
        static let borderWidth: CGFloat = 0.5
        static let borderWidthHeavy: CGFloat = 1.0
        static let cornerRadius: CGFloat = 12
        static let cornerRadiusSmall: CGFloat = 8
        static let cornerRadiusLarge: CGFloat = 16
        
        static let shadowRadius: CGFloat = 10
        static let shadowOffset: CGSize = CGSize(width: 0, height: 4)
    }
    
    // MARK: - Animations
    
    struct Animations {
        static let spring = Animation.spring(response: 0.3, dampingFraction: 0.8)
        static let easeInOut = Animation.easeInOut(duration: 0.25)
        static let quickSpring = Animation.spring(response: 0.2, dampingFraction: 0.9)
    }
}

// MARK: - Glassmorphic Card Modifier

struct GlassmorphicCard: ViewModifier {
    let material: GlassmorphismDesignSystem.BlurMaterial
    let cornerRadius: CGFloat
    let borderWidth: CGFloat
    let shadowRadius: CGFloat
    
    init(
        material: GlassmorphismDesignSystem.BlurMaterial = .regular,
        cornerRadius: CGFloat = GlassmorphismDesignSystem.Dimensions.cornerRadius,
        borderWidth: CGFloat = GlassmorphismDesignSystem.Dimensions.borderWidth,
        shadowRadius: CGFloat = GlassmorphismDesignSystem.Dimensions.shadowRadius
    ) {
        self.material = material
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        self.shadowRadius = shadowRadius
    }
    
    func body(content: Content) -> some View {
        content
            .background(
                VisualEffectBlur(material: material.material)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(GlassmorphismDesignSystem.Colors.primaryGlass)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                GlassmorphismDesignSystem.Colors.borderLight,
                                GlassmorphismDesignSystem.Colors.borderLight.opacity(0.5)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: borderWidth
                    )
            )
            .shadow(
                color: GlassmorphismDesignSystem.Colors.shadowLight,
                radius: shadowRadius,
                x: 0,
                y: GlassmorphismDesignSystem.Dimensions.shadowOffset.height
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Glassmorphic Panel

struct GlassmorphicPanel<Content: View>: View {
    let content: Content
    let material: GlassmorphismDesignSystem.BlurMaterial
    let cornerRadius: CGFloat
    
    init(
        material: GlassmorphismDesignSystem.BlurMaterial = .regular,
        cornerRadius: CGFloat = GlassmorphismDesignSystem.Dimensions.cornerRadius,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.material = material
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        content
            .modifier(GlassmorphicCard(material: material, cornerRadius: cornerRadius))
    }
}

// MARK: - Glassmorphic Button

struct GlassmorphicButton: View {
    let title: String
    let icon: String?
    let action: () -> Void
    
    @State private var isHovered = false
    @State private var isPressed = false
    
    init(title: String, icon: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: GlassmorphismDesignSystem.Dimensions.cornerRadiusSmall)
                    .fill(
                        isPressed ? GlassmorphismDesignSystem.Colors.secondaryGlass :
                        isHovered ? GlassmorphismDesignSystem.Colors.primaryGlass :
                        Color.clear
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: GlassmorphismDesignSystem.Dimensions.cornerRadiusSmall)
                    .strokeBorder(
                        isHovered ? GlassmorphismDesignSystem.Colors.glowAccent :
                        GlassmorphismDesignSystem.Colors.borderLight,
                        lineWidth: GlassmorphismDesignSystem.Dimensions.borderWidth
                    )
            )
            .scaleEffect(isPressed ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(GlassmorphismDesignSystem.Animations.quickSpring) {
                isHovered = hovering
            }
        }
        .pressAction {
            withAnimation(GlassmorphismDesignSystem.Animations.quickSpring) {
                isPressed = true
            }
        } onRelease: {
            withAnimation(GlassmorphismDesignSystem.Animations.quickSpring) {
                isPressed = false
            }
        }
    }
}

// MARK: - Glassmorphic Icon Button

struct GlassmorphicIconButton: View {
    let icon: String
    let action: () -> Void
    let isActive: Bool
    let size: CGFloat
    
    @State private var isHovered = false
    @State private var isPressed = false
    
    init(icon: String, isActive: Bool = false, size: CGFloat = 28, action: @escaping () -> Void) {
        self.icon = icon
        self.isActive = isActive
        self.size = size
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundColor(isActive ? .accentColor : .primary)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(
                            isActive ? GlassmorphismDesignSystem.Colors.glowAccent :
                            isPressed ? GlassmorphismDesignSystem.Colors.secondaryGlass :
                            isHovered ? GlassmorphismDesignSystem.Colors.primaryGlass :
                            Color.clear
                        )
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            isActive ? Color.accentColor.opacity(0.5) :
                            isHovered ? GlassmorphismDesignSystem.Colors.glowAccent :
                            GlassmorphismDesignSystem.Colors.borderLight,
                            lineWidth: GlassmorphismDesignSystem.Dimensions.borderWidth
                        )
                )
                .scaleEffect(isPressed ? 0.92 : 1.0)
                .contentShape(Circle())
        }
        .buttonStyle(.borderless)
        .contentShape(Circle())
        .onHover { hovering in
            withAnimation(GlassmorphismDesignSystem.Animations.quickSpring) {
                isHovered = hovering
            }
        }
        .pressAction {
            withAnimation(GlassmorphismDesignSystem.Animations.quickSpring) {
                isPressed = true
            }
        } onRelease: {
            withAnimation(GlassmorphismDesignSystem.Animations.quickSpring) {
                isPressed = false
            }
        }
    }
}

// MARK: - Glassmorphic Badge

struct GlassmorphicBadge: View {
    let text: String
    let color: Color
    
    init(text: String, color: Color = .accentColor) {
        self.text = text
        self.color = color
    }
    
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(color)
                    .shadow(
                        color: color.opacity(0.3),
                        radius: 4,
                        x: 0,
                        y: 2
                    )
            )
    }
}

// MARK: - Glassmorphic Tag

struct GlassmorphicTag: View {
    let text: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    init(text: String, color: Color, isSelected: Bool = false, action: @escaping () -> Void) {
        self.text = text
        self.color = color
        self.isSelected = isSelected
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .shadow(color: color.opacity(0.5), radius: isSelected ? 4 : 2)
                
                Text(text)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: GlassmorphismDesignSystem.Dimensions.cornerRadiusSmall)
                    .fill(
                        isSelected ? color.opacity(0.15) :
                        isHovered ? GlassmorphismDesignSystem.Colors.primaryGlass :
                        Color.clear
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: GlassmorphismDesignSystem.Dimensions.cornerRadiusSmall)
                    .strokeBorder(
                        isSelected ? color.opacity(0.5) :
                        isHovered ? GlassmorphismDesignSystem.Colors.borderLight :
                        Color.clear,
                        lineWidth: GlassmorphismDesignSystem.Dimensions.borderWidth
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(GlassmorphismDesignSystem.Animations.quickSpring) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Visual Effect Blur (NSVisualEffectView wrapper)

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    init(material: NSVisualEffectView.Material, blendingMode: NSVisualEffectView.BlendingMode = .behindWindow) {
        self.material = material
        self.blendingMode = blendingMode
    }
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Press Action Modifier

struct PressActions: ViewModifier {
    var onPress: () -> Void
    var onRelease: () -> Void
    
    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        onPress()
                    }
                    .onEnded { _ in
                        onRelease()
                    }
            )
    }
}

extension View {
    func pressAction(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        modifier(PressActions(onPress: onPress, onRelease: onRelease))
    }
    
    func glassmorphicCard(
        material: GlassmorphismDesignSystem.BlurMaterial = .regular,
        cornerRadius: CGFloat = GlassmorphismDesignSystem.Dimensions.cornerRadius
    ) -> some View {
        modifier(GlassmorphicCard(material: material, cornerRadius: cornerRadius))
    }
    
    /// Aggiunge interattività hover/press con animazioni standard
    func interactiveButton(
        scaleOnPress: CGFloat = 0.96,
        animation: Animation = GlassmorphismDesignSystem.Animations.quickSpring
    ) -> some View {
        modifier(InteractiveButtonModifier(scaleOnPress: scaleOnPress, animation: animation))
    }
    
    /// Aggiunge solo l'effetto hover
    func hoverEffect(
        animation: Animation = GlassmorphismDesignSystem.Animations.quickSpring,
        onHover: @escaping (Bool) -> Void
    ) -> some View {
        modifier(HoverEffectModifier(animation: animation, onHover: onHover))
    }
}

// MARK: - Interactive Button Modifier

/// Modifier centralizzato per gestire hover e press su bottoni interattivi.
/// Sostituisce i pattern duplicati in 20+ componenti.
struct InteractiveButtonModifier: ViewModifier {
    let scaleOnPress: CGFloat
    let animation: Animation
    
    @State private var isHovered = false
    @State private var isPressed = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? scaleOnPress : 1.0)
            .opacity(isHovered ? 1.0 : 0.9)
            .onHover { hovering in
                withAnimation(animation) {
                    isHovered = hovering
                }
            }
            .pressAction {
                withAnimation(animation) {
                    isPressed = true
                }
            } onRelease: {
                withAnimation(animation) {
                    isPressed = false
                }
            }
    }
}

// MARK: - Hover Effect Modifier

/// Modifier per aggiungere effetto hover con callback
struct HoverEffectModifier: ViewModifier {
    let animation: Animation
    let onHover: (Bool) -> Void
    
    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                withAnimation(animation) {
                    onHover(hovering)
                }
            }
    }
}

// MARK: - Glassmorphic Divider

struct GlassmorphicDivider: View {
    let isVertical: Bool
    
    init(isVertical: Bool = false) {
        self.isVertical = isVertical
    }
    
    var body: some View {
        if isVertical {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            GlassmorphismDesignSystem.Colors.borderLight.opacity(0.3),
                            GlassmorphismDesignSystem.Colors.borderLight,
                            GlassmorphismDesignSystem.Colors.borderLight.opacity(0.3)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 1)
        } else {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            GlassmorphismDesignSystem.Colors.borderLight.opacity(0.3),
                            GlassmorphismDesignSystem.Colors.borderLight,
                            GlassmorphismDesignSystem.Colors.borderLight.opacity(0.3)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
    }
}

// MARK: - Glassmorphic Toolbar

struct GlassmorphicToolbar<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                VisualEffectBlur(material: .headerView)
                    .overlay(
                        GlassmorphismDesignSystem.Colors.primaryGlass
                    )
            )
            .overlay(
                Rectangle()
                    .fill(GlassmorphismDesignSystem.Colors.borderLight)
                    .frame(height: 0.5),
                alignment: .bottom
            )
    }
}

// MARK: - Glassmorphic Popover Container

struct GlassmorphicPopover<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding()
            .background(
                VisualEffectBlur(material: .popover)
                    .overlay(
                        RoundedRectangle(cornerRadius: GlassmorphismDesignSystem.Dimensions.cornerRadius)
                            .fill(GlassmorphismDesignSystem.Colors.primaryGlass)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: GlassmorphismDesignSystem.Dimensions.cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                GlassmorphismDesignSystem.Colors.borderLight,
                                GlassmorphismDesignSystem.Colors.borderLight.opacity(0.3)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: GlassmorphismDesignSystem.Dimensions.borderWidth
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: GlassmorphismDesignSystem.Dimensions.cornerRadius))
            .shadow(
                color: GlassmorphismDesignSystem.Colors.shadowDark,
                radius: 20,
                x: 0,
                y: 10
            )
    }
}

// MARK: - Glassmorphic TextField

struct GlassmorphicTextField: View {
    let placeholder: String
    @Binding var text: String
    let icon: String?
    
    @State private var isFocused = false
    @FocusState private var fieldFocused: Bool
    
    init(_ placeholder: String, text: Binding<String>, icon: String? = nil) {
        self.placeholder = placeholder
        self._text = text
        self.icon = icon
    }
    
    var body: some View {
        HStack(spacing: 8) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($fieldFocused)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: GlassmorphismDesignSystem.Dimensions.cornerRadiusSmall)
                .fill(GlassmorphismDesignSystem.Colors.secondaryGlass)
        )
        .overlay(
            RoundedRectangle(cornerRadius: GlassmorphismDesignSystem.Dimensions.cornerRadiusSmall)
                .strokeBorder(
                    fieldFocused ? Color.accentColor.opacity(0.5) :
                    GlassmorphismDesignSystem.Colors.borderLight,
                    lineWidth: fieldFocused ? 1.5 : GlassmorphismDesignSystem.Dimensions.borderWidth
                )
        )
        .animation(GlassmorphismDesignSystem.Animations.quickSpring, value: fieldFocused)
    }
}

// MARK: - Glassmorphic Toggle

struct GlassmorphicToggle: View {
    let title: String
    @Binding var isOn: Bool
    
    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(.system(size: 13))
                .foregroundColor(.primary)
        }
        .toggleStyle(GlassmorphicToggleStyle())
    }
}

struct GlassmorphicToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            
            Spacer()
            
            ZStack {
                Capsule()
                    .fill(
                        configuration.isOn ?
                        Color.accentColor.opacity(0.3) :
                        GlassmorphismDesignSystem.Colors.secondaryGlass
                    )
                    .frame(width: 44, height: 26)
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                configuration.isOn ?
                                Color.accentColor.opacity(0.5) :
                                GlassmorphismDesignSystem.Colors.borderLight,
                                lineWidth: GlassmorphismDesignSystem.Dimensions.borderWidth
                            )
                    )
                
                Circle()
                    .fill(.white)
                    .shadow(
                        color: GlassmorphismDesignSystem.Colors.shadowLight,
                        radius: 2,
                        x: 0,
                        y: 1
                    )
                    .frame(width: 22, height: 22)
                    .offset(x: configuration.isOn ? 9 : -9)
            }
            .onTapGesture {
                withAnimation(GlassmorphismDesignSystem.Animations.spring) {
                    configuration.isOn.toggle()
                }
            }
        }
    }
}
