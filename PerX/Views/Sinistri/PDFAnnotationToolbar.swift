import SwiftUI
import AppKit

// MARK: - PDF Annotation Toolbar

/// Barra contestuale per opzioni annotazioni PDF (appare sotto la tabbar)
struct PDFAnnotationToolbar: View {
    @Binding var annotationMode: AnnotationMode?
    @Binding var strokeColor: Color
    @Binding var fillColor: Color?
    @Binding var strokeWidth: CGFloat
    @Binding var isFilled: Bool
    @Binding var obfuscationIntensity: CGFloat
    
    @State private var showColorPicker = false
    @State private var showFillColorPicker = false
    @State private var showEyedropper = false
    @State private var isPickingColor = false
    
    var body: some View {
        if let mode = annotationMode {
            GlassmorphicToolbar {
                HStack(spacing: 16) {
                    // Tool selector
                    toolSelector(mode: mode)
                    
                    GlassmorphicDivider(isVertical: true)
                        .frame(height: 24)
                    
                    // Color controls
                    colorControls
                    
                    if mode == .shape {
                        GlassmorphicDivider(isVertical: true)
                            .frame(height: 24)
                        
                        // Fill controls
                        fillControls
                    }
                    
                    if mode == .obfuscate {
                        GlassmorphicDivider(isVertical: true)
                            .frame(height: 24)
                        
                        // Intensity control
                        intensityControl
                    }
                    
                    Spacer()
                    
                    // Close button
                    GlassmorphicIconButton(icon: "xmark.circle.fill", size: 24) {
                        withAnimation(GlassmorphismDesignSystem.Animations.spring) {
                            annotationMode = nil
                        }
                    }
                    .help("Chiudi barra annotazioni")
                }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
    
    // MARK: - Tool Selector
    
    @ViewBuilder
    private func toolSelector(mode: AnnotationMode) -> some View {
        HStack(spacing: 8) {
            ToolButton(
                icon: "highlighter",
                title: "Evidenzia",
                isSelected: mode == .highlight,
                color: .yellow
            ) {
                withAnimation(GlassmorphismDesignSystem.Animations.spring) {
                    annotationMode = .highlight
                }
            }
            
            ToolButton(
                icon: "rectangle",
                title: "Forma",
                isSelected: mode == .shape,
                color: .blue
            ) {
                withAnimation(GlassmorphismDesignSystem.Animations.spring) {
                    annotationMode = .shape
                }
            }
            
            ToolButton(
                icon: "eye.slash.fill",
                title: "Oscura",
                isSelected: mode == .obfuscate,
                color: .red
            ) {
                withAnimation(GlassmorphismDesignSystem.Animations.spring) {
                    annotationMode = .obfuscate
                }
            }
        }
    }
    
    // MARK: - Color Controls
    
    private var colorControls: some View {
        HStack(spacing: 8) {
            Text("Colore:")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            
            // Color swatch
            Button {
                showColorPicker.toggle()
            } label: {
                RoundedRectangle(cornerRadius: 6)
                    .fill(strokeColor)
                    .frame(width: 32, height: 24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: strokeColor.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showColorPicker) {
                ColorPickerPopover(
                    color: $strokeColor,
                    showEyedropper: $showEyedropper,
                    isPickingColor: $isPickingColor
                )
            }
            
            // Eyedropper button
            GlassmorphicIconButton(icon: "eyedropper", size: 24) {
                showEyedropper = true
                isPickingColor = true
            }
            .help("Seleziona colore dal file")
        }
    }
    
    // MARK: - Fill Controls
    
    private var fillControls: some View {
        HStack(spacing: 8) {
            Toggle(isOn: $isFilled) {
                Text("Riempimento")
                    .font(.system(size: 12, weight: .medium))
            }
            .toggleStyle(GlassmorphicToggleStyle())
            
            if isFilled {
                Button {
                    showFillColorPicker.toggle()
                } label: {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(fillColor ?? strokeColor)
                        .frame(width: 32, height: 24)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showFillColorPicker) {
                    ColorPickerPopover(
                        color: Binding(
                            get: { fillColor ?? strokeColor },
                            set: { fillColor = $0 }
                        ),
                        showEyedropper: .constant(false),
                        isPickingColor: .constant(false)
                    )
                }
            }
            
            // Stroke width
            HStack(spacing: 4) {
                Text("Spessore:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Slider(value: $strokeWidth, in: 1...10, step: 0.5)
                    .frame(width: 80)
                
                Text("\(Int(strokeWidth))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 20)
            }
        }
    }
    
    // MARK: - Intensity Control
    
    private var intensityControl: some View {
        HStack(spacing: 8) {
            Text("Intensità:")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            
            Slider(value: $obfuscationIntensity, in: 0.3...1.0, step: 0.1)
                .frame(width: 120)
            
            Text("\(Int(obfuscationIntensity * 100))%")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 35)
        }
    }
}

// MARK: - Annotation Mode

enum AnnotationMode: String {
    case highlight
    case shape
    case obfuscate
}

// MARK: - Tool Button

struct ToolButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? color : (isHovered ? GlassmorphismDesignSystem.Colors.primaryGlass : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isSelected ? color.opacity(0.5) : GlassmorphismDesignSystem.Colors.borderLight,
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
            .shadow(
                color: isSelected ? color.opacity(0.3) : .clear,
                radius: 4,
                x: 0,
                y: 2
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

// MARK: - Color Picker Popover

struct ColorPickerPopover: View {
    @Binding var color: Color
    @Binding var showEyedropper: Bool
    @Binding var isPickingColor: Bool
    
    let presetColors: [Color] = [
        .yellow, .orange, .red, .pink, .purple,
        .blue, .cyan, .green, .mint, .gray
    ]
    
    var body: some View {
        GlassmorphicPopover {
            VStack(spacing: 12) {
                // Preset colors
                HStack(spacing: 8) {
                    ForEach(presetColors, id: \.self) { presetColor in
                        Button {
                            color = presetColor
                        } label: {
                            Circle()
                                .fill(presetColor)
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle()
                                        .strokeBorder(
                                            color == presetColor ? Color.white : Color.clear,
                                            lineWidth: 2
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                GlassmorphicDivider()
                
                // Color picker
                ColorPicker("Colore personalizzato", selection: $color)
                    .labelsHidden()
            }
            .padding()
            .frame(width: 280)
        }
    }
}

// MARK: - Eyedropper View

struct EyedropperView: NSViewRepresentable {
    @Binding var isActive: Bool
    let onColorPicked: (NSColor) -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if isActive {
            // Avvia eyedropper
            DispatchQueue.main.async {
                startColorPicking()
            }
        }
    }
    
    private func startColorPicking() {
        // Implementazione eyedropper usando NSScreen e mouse location
        // Per ora usiamo un approccio semplificato
        let event = NSApp.currentEvent
        if let window = NSApp.keyWindow,
           let screen = window.screen {
            let mouseLocation = NSEvent.mouseLocation
            let screenPoint = CGPoint(
                x: mouseLocation.x,
                y: screen.frame.height - mouseLocation.y
            )
            
            // Cattura colore dal pixel (richiede permessi screen recording)
            // Per ora usiamo un fallback
            onColorPicked(.systemBlue)
            isActive = false
        }
    }
}
