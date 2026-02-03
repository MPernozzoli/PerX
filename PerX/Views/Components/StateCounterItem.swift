import SwiftUI

struct StateCounterItem: View {
    let stato: StatoManager.StatoSinistro
    let count: Int
    let isSelected: Bool
    let showFilterLabels: Bool
    var isSubState: Bool = false
    let onTap: () -> Void
    
    @State private var isHovering = false
    
    /// Descrizione da mostrare: variante (suffix) se sotto-stato con varianti semantiche, altrimenti descrizione completa
    private var displayLabel: String {
        if isSubState {
            let variant = stato.variant
            let group = stato.stateGroup
            
            // Se lo stato ha una variante semantica (documentale, videoperizia, ecc.), mostrala
            if !variant.isBase {
                return variant.rawValue
            }
            
            // Se il gruppo ha varianti semantiche e questo stato è "tradizionale", mostra "tradizionale"
            let hasSemanticVariants = group.members.contains { !$0.variant.isBase }
            if hasSemanticVariants {
                return "tradizionale"
            }
            
            // Altrimenti mostra la descrizione completa
            return stato.descrizione
        }
        return stato.descrizione
    }
    
    private var cornerRadius: CGFloat { isSubState ? 6 : 8 }
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: stato.icon)
                .foregroundColor(iconColor)
                .font(isSubState ? .caption : .body)
            
            if showFilterLabels {
                Text(displayLabel)
                    .font(isSubState ? .caption2 : .caption)
                    .lineLimit(1)
                    .foregroundColor(textColor)
            }
            
            Text("\(count)")
                .font(isSubState ? .caption.bold() : .system(.body, design: .rounded).bold())
                .foregroundColor(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .padding(.horizontal, isSubState ? 8 : 10)
        .padding(.vertical, isSubState ? 5 : 6)
        .frame(minWidth: 44, minHeight: 32)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(backgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(borderColor, lineWidth: isSubState ? 1.5 : 2)
                )
        )
        .scaleEffect(scaleValue)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isSelected)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    // MARK: - Computed Colors
    
    private var backgroundColor: Color {
        if isSelected {
            return stato.color.opacity(isSubState ? 0.18 : 0.15)
        } else if isHovering {
            // Hover: stesso colore del selezionato ma al 50%
            return stato.color.opacity(isSubState ? 0.09 : 0.075)
        }
        return Color(NSColor.controlBackgroundColor).opacity(isSubState ? 0.6 : 1)
    }
    
    private var borderColor: Color {
        if isSelected {
            return stato.color
        } else if isHovering {
            return stato.color.opacity(0.5)
        }
        return .clear
    }
    
    private var iconColor: Color {
        if isSelected {
            return stato.color
        } else if isHovering {
            return stato.color.opacity(0.85)
        }
        return stato.color.opacity(0.7)
    }
    
    private var textColor: Color {
        if isSelected {
            return .primary
        } else if isHovering {
            return .primary.opacity(0.8)
        }
        return .secondary
    }
    
    private var scaleValue: CGFloat {
        if isSelected {
            return 1.0
        } else if isHovering {
            return 0.98
        }
        return 0.96
    }
} 