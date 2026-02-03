import SwiftUI

// MARK: - Animation Utilities

/// Utilities per animazioni fluide e consistenti in tutta l'applicazione

// MARK: - Custom Animations

extension Animation {
    
    /// Animazione spring veloce per interazioni rapide (hover, press)
    static let quickSpring = Animation.spring(response: 0.2, dampingFraction: 0.9)
    
    /// Animazione spring standard per transizioni UI
    static let defaultSpring = Animation.spring(response: 0.3, dampingFraction: 0.8)
    
    /// Animazione spring lenta per movimenti fluidi
    static let gentleSpring = Animation.spring(response: 0.4, dampingFraction: 0.7)
    
    /// Animazione bouncy per feedback visivo
    static let bouncySpring = Animation.spring(response: 0.35, dampingFraction: 0.65)
    
    /// Animazione ease-in-out veloce
    static let quickEaseInOut = Animation.easeInOut(duration: 0.2)
    
    /// Animazione ease-in-out standard
    static let defaultEaseInOut = Animation.easeInOut(duration: 0.25)
    
    /// Animazione ease-in-out lenta
    static let slowEaseInOut = Animation.easeInOut(duration: 0.4)
    
    /// Animazione per apertura/chiusura panel
    static let panelToggle = Animation.spring(response: 0.35, dampingFraction: 0.8)
    
    /// Animazione per transizione file
    static let fileTransition = Animation.easeInOut(duration: 0.25)
    
    /// Animazione per zoom
    static let zoomAnimation = Animation.spring(response: 0.25, dampingFraction: 0.85)
}

// MARK: - Transition Modifiers

struct SlideAndFade: ViewModifier {
    let edge: Edge
    let isPresented: Bool
    
    func body(content: Content) -> some View {
        content
            .transition(.asymmetric(
                insertion: .move(edge: edge).combined(with: .opacity),
                removal: .opacity.combined(with: .scale(scale: 0.95))
            ))
    }
}

struct ScaleAndFade: ViewModifier {
    let isPresented: Bool
    
    func body(content: Content) -> some View {
        content
            .transition(.asymmetric(
                insertion: .scale(scale: 0.9, anchor: .center).combined(with: .opacity),
                removal: .scale(scale: 1.05, anchor: .center).combined(with: .opacity)
            ))
    }
}

// MARK: - Animation View Modifiers

struct AnimatedVisibility: ViewModifier {
    let isVisible: Bool
    
    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .scaleEffect(isVisible ? 1 : 0.95)
            .animation(.defaultSpring, value: isVisible)
    }
}

struct PulseOnChange<Value: Equatable>: ViewModifier {
    let value: Value
    @State private var isPulsing = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.05 : 1.0)
            .animation(.bouncySpring, value: isPulsing)
            .onChange(of: value) { _ in
                isPulsing = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isPulsing = false
                }
            }
    }
}

struct ShakeOnError: ViewModifier {
    let shakeAmount: CGFloat
    @State private var shakeOffset: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .offset(x: shakeOffset)
    }
    
    func shake() {
        withAnimation(.linear(duration: 0.05)) {
            shakeOffset = shakeAmount
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.linear(duration: 0.05)) {
                shakeOffset = -shakeAmount
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.linear(duration: 0.05)) {
                shakeOffset = shakeAmount / 2
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.linear(duration: 0.05)) {
                shakeOffset = 0
            }
        }
    }
}

struct FadeTransition: ViewModifier {
    let id: String
    
    func body(content: Content) -> some View {
        content
            .id(id)
            .transition(.opacity)
    }
}

// MARK: - View Extensions

extension View {
    
    /// Animazione di visibilità fluida
    func animatedVisibility(_ isVisible: Bool) -> some View {
        modifier(AnimatedVisibility(isVisible: isVisible))
    }
    
    /// Effetto pulse quando il valore cambia
    func pulseOnChange<Value: Equatable>(_ value: Value) -> some View {
        modifier(PulseOnChange(value: value))
    }
    
    /// Slide da un edge con fade
    func slideAndFade(from edge: Edge, isPresented: Bool = true) -> some View {
        modifier(SlideAndFade(edge: edge, isPresented: isPresented))
    }
    
    /// Scale con fade
    func scaleAndFade(isPresented: Bool = true) -> some View {
        modifier(ScaleAndFade(isPresented: isPresented))
    }
    
    /// Transizione fade per contenuto che cambia
    func fadeTransition(id: String) -> some View {
        modifier(FadeTransition(id: id))
    }
    
    /// Animazione spring per hover
    func hoverScaleEffect(_ isHovered: Bool, scale: CGFloat = 1.02) -> some View {
        self
            .scaleEffect(isHovered ? scale : 1.0)
            .animation(.quickSpring, value: isHovered)
    }
    
    /// Animazione press
    func pressScaleEffect(_ isPressed: Bool, scale: CGFloat = 0.96) -> some View {
        self
            .scaleEffect(isPressed ? scale : 1.0)
            .animation(.quickSpring, value: isPressed)
    }
    
    /// Combinazione hover + press
    func interactiveScaleEffect(isHovered: Bool, isPressed: Bool, hoverScale: CGFloat = 1.02, pressScale: CGFloat = 0.96) -> some View {
        self
            .scaleEffect(isPressed ? pressScale : (isHovered ? hoverScale : 1.0))
            .animation(.quickSpring, value: isHovered)
            .animation(.quickSpring, value: isPressed)
    }
    
    /// Animazione opacity per elementi che appaiono/scompaiono
    func fadeAnimation(_ isVisible: Bool, duration: Double = 0.25) -> some View {
        self
            .opacity(isVisible ? 1 : 0)
            .animation(.easeInOut(duration: duration), value: isVisible)
    }
}

// MARK: - Animated Counter

struct AnimatedCounter: View {
    let value: Int
    let font: Font
    let color: Color
    
    init(_ value: Int, font: Font = .body, color: Color = .primary) {
        self.value = value
        self.font = font
        self.color = color
    }
    
    var body: some View {
        Text("\(value)")
            .font(font)
            .foregroundColor(color)
            .contentTransition(.numericText())
            .animation(.defaultSpring, value: value)
    }
}

// MARK: - Loading Shimmer Effect

struct ShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.2),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: -geometry.size.width + (geometry.size.width * 2 * phase))
                }
            )
            .mask(content)
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerEffect())
    }
}

// MARK: - Staggered Animation

struct StaggeredAnimation: ViewModifier {
    let index: Int
    let baseDelay: Double
    let animation: Animation
    @State private var isVisible = false
    
    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 10)
            .animation(animation.delay(Double(index) * baseDelay), value: isVisible)
            .onAppear {
                isVisible = true
            }
    }
}

extension View {
    func staggeredAppearance(index: Int, baseDelay: Double = 0.05, animation: Animation = .defaultSpring) -> some View {
        modifier(StaggeredAnimation(index: index, baseDelay: baseDelay, animation: animation))
    }
}
