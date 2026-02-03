import SwiftUI
import AppKit

/// Un ViewModifier che presenta una vista come un pop-up centrato sopra il contenuto.
public struct Popup<PopupContent: View>: ViewModifier {
    
    @Binding var isPresented: Bool
    let view: () -> PopupContent
    
    // MARK: - Private Properties
    
    @State private var presenterContentRect: CGRect = .zero
    @State private var sheetContentRect: CGRect = .zero
    
    private var screenWidth: CGFloat {
        NSScreen.main?.frame.size.width ?? 1000
    }
    
    private var screenHeight: CGFloat {
        NSScreen.main?.frame.size.height ?? 1000
    }
    
    private var displayedOffset: CGFloat {
        -presenterContentRect.midY + screenHeight / 2
    }
    
    private var hiddenOffset: CGFloat {
        if presenterContentRect.isEmpty {
            return 1000
        }
        return screenHeight - presenterContentRect.midY + sheetContentRect.height / 2 + 5
    }
    
    private var currentOffset: CGFloat {
        isPresented ? displayedOffset : hiddenOffset
    }
    
    // MARK: - Body
    
    public func body(content: Content) -> some View {
        ZStack {
            content
                .frameGetter($presenterContentRect)
        }
        .overlay(sheet())
    }
    
    // MARK: - Private Methods
    
    private func sheet() -> some View {
        ZStack {
            if isPresented {
                // Sfondo oscurato
                Color.black.opacity(0.4)
                    .edgesIgnoringSafeArea(.all)
                    .transition(.opacity)
                    .onTapGesture {
                        dismiss()
                    }
                
                // Contenuto del popup
                self.view()
                    .simultaneousGesture(TapGesture().onEnded {
                        // Impedisce al tap di propagarsi allo sfondo
                    })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isPresented)
    }
    
    private func dismiss() {
        isPresented = false
    }
}

// MARK: - View Extension

extension View {
    
    /// Presenta una vista come un pop-up.
    public func popup<PopupContent: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder view: @escaping () -> PopupContent
    ) -> some View {
        self.modifier(
            Popup(isPresented: isPresented, view: view)
        )
    }
    
    /// Helper per ottenere il frame di una vista.
    func frameGetter(_ frame: Binding<CGRect>) -> some View {
        modifier(FrameGetter(frame: frame))
    }
}

private struct FrameGetter: ViewModifier {
    
    @Binding var frame: CGRect
    
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy -> AnyView in
                    let rect = proxy.frame(in: .global)
                    // Evita un loop infinito di layout
                    if rect.integral != self.frame.integral {
                        DispatchQueue.main.async {
                            self.frame = rect
                        }
                    }
                    return AnyView(EmptyView())
                }
            )
    }
} 