import SwiftUI

/// View compatta per visualizzare e modificare il tag di categoria di un'email
struct EmailCategoryTagView: View {
    
    let emailId: String
    
    @StateObject private var tagManager = EmailTagManager.shared
    @State private var showTagPicker = false
    @State private var isProcessing = false
    
    private var currentTag: EmailCategoryTag? {
        tagManager.getTag(forEmailId: emailId)
    }
    
    var body: some View {
        HStack(spacing: 6) {
            if let tag = currentTag {
                // Tag badge (categoria)
                tagBadge(for: tag)
                
                // Processing status badge
                processingStatusBadge(for: tag)
            } else {
                // Nessun tag - mostra placeholder
                noTagBadge
            }
        }
        .popover(isPresented: $showTagPicker) {
            EmailCategoryPickerView(
                emailId: emailId,
                currentCategory: currentTag?.category,
                currentTag: currentTag,
                onSelect: { category in
                    applyTag(category)
                },
                onClear: {
                    clearTag()
                },
                onForceReprocess: {
                    forceReprocess()
                }
            )
        }
    }
    
    // MARK: - Tag Badge
    
    @ViewBuilder
    private func tagBadge(for tag: EmailCategoryTag) -> some View {
        Button(action: { showTagPicker.toggle() }) {
            HStack(spacing: 4) {
                // Icona categoria con stato
                categoryIcon(for: tag)
                
                Text(tag.displayName)
                    .font(.system(size: 10, weight: .medium))
                
                if tag.isManual {
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(tag.color.opacity(tag.processingStatus == .inCoda ? 0.1 : 0.2))
            )
            .overlay(
                Capsule()
                    .stroke(tag.processingStatus == .errore ? Color.red : tag.color, 
                           lineWidth: tag.processingStatus == .errore ? 1.5 : 1)
            )
            .foregroundColor(tag.processingStatus == .inCoda ? .gray : tag.color)
            .opacity(tag.processingStatus == .inCoda ? 0.7 : 1.0)
        }
        .buttonStyle(.plain)
        .help(tooltipText(for: tag))
    }
    
    @ViewBuilder
    private func categoryIcon(for tag: EmailCategoryTag) -> some View {
        ZStack {
            Image(systemName: tag.iconName)
                .font(.system(size: 10))
            
            // Overlay stato errore
            if tag.processingStatus == .errore {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 6))
                    .foregroundColor(.red)
                    .offset(x: 5, y: -5)
            }
        }
    }
    
    // MARK: - Processing Status Badge
    
    @State private var isProcessingAnimationActive = false
    
    @ViewBuilder
    private func processingStatusBadge(for tag: EmailCategoryTag) -> some View {
        Button(action: {
            // Permetti interazione solo per stati modificabili manualmente
            if tag.processingStatus.canBeManuallyChanged {
                forceReprocess()
            }
        }) {
            ZStack {
                // Icona principale
                Image(systemName: tag.processingStatus.iconName)
                    .font(.system(size: 10))
                    .foregroundColor(tag.processingStatus.color)
                
                // Animazione pulsante per "in corso"
                if tag.processingStatus == .inCorso {
                    Circle()
                        .stroke(tag.processingStatus.color.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 14, height: 14)
                        .scaleEffect(isProcessingAnimationActive ? 1.3 : 1.0)
                        .opacity(isProcessingAnimationActive ? 0.0 : 0.6)
                        .animation(
                            Animation.easeInOut(duration: 1.0)
                                .repeatForever(autoreverses: false),
                            value: isProcessingAnimationActive
                        )
                        .onAppear {
                            isProcessingAnimationActive = true
                        }
                }
            }
            .padding(3)
            .background(
                Circle()
                    .fill(tag.processingStatus.color.opacity(0.15))
            )
        }
        .buttonStyle(.plain)
        .help(processingStatusTooltip(for: tag))
        .disabled(!tag.processingStatus.canBeManuallyChanged)
        .opacity(tag.processingStatus.canBeManuallyChanged ? 1.0 : 0.6)
        .onChange(of: tag.processingStatus) { oldValue, newValue in
            // Reset animazione quando cambia stato
            if newValue == .inCorso {
                isProcessingAnimationActive = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isProcessingAnimationActive = true
                }
            } else {
                isProcessingAnimationActive = false
            }
        }
    }
    
    private var noTagBadge: some View {
        Button(action: { showTagPicker.toggle() }) {
            HStack(spacing: 4) {
                Image(systemName: "tag")
                    .font(.system(size: 10))
                
                Text("Aggiungi tag")
                    .font(.system(size: 10))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.gray.opacity(0.1))
            )
            .overlay(
                Capsule()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Status Helpers
    
    private func getActionText(for status: EmailProcessingStatus) -> String {
        switch status {
        case .inCoda: return "Prioritizza"
        case .errore: return "Riprova"
        case .saltata: return "Processa"
        default: return "Processa"
        }
    }
    
    private func getActionIcon(for status: EmailProcessingStatus) -> String {
        switch status {
        case .inCoda: return "arrow.up.circle"
        case .errore: return "arrow.clockwise"
        case .saltata: return "play.circle"
        default: return "play.circle"
        }
    }
    
    private func getOpacityForStatus(_ status: EmailProcessingStatus) -> Double {
        switch status {
        case .inCoda, .saltata: return 0.7
        case .inCorso: return 1.0
        case .processata: return 1.0
        case .errore: return 0.9
        }
    }
    
    private func getBorderColorForStatus(_ status: EmailProcessingStatus) -> Color {
        switch status {
        case .errore: return .red
        case .saltata: return .orange
        case .inCorso: return .blue
        default: return .clear
        }
    }
    
    // MARK: - Actions
    
    private func applyTag(_ category: EmailCategory) {
        guard !isProcessing else { return }
        isProcessing = true
        
        Task {
            await tagManager.setManualTag(category: category, toEmailId: emailId)
            isProcessing = false
            showTagPicker = false
        }
    }
    
    private func clearTag() {
        guard !isProcessing else { return }
        isProcessing = true
        
        Task {
            await tagManager.clearManualTag(forEmailId: emailId)
            isProcessing = false
            showTagPicker = false
        }
    }
    
    private func forceReprocess() {
        guard !isProcessing else { return }
        isProcessing = true
        
        Task {
            await tagManager.forceReprocess(emailId: emailId)
            isProcessing = false
        }
    }
    
    // MARK: - Helpers
    
    private func tooltipText(for tag: EmailCategoryTag) -> String {
        var text = tag.displayName
        if tag.isManual {
            text += " (impostato manualmente)"
        } else {
            text += " (automatico, confidenza: \(Int(tag.confidence * 100))%)"
        }
        return text
    }
    
    private func processingStatusTooltip(for tag: EmailCategoryTag) -> String {
        switch tag.processingStatus {
        case .inCoda:
            return "In coda per elaborazione. Clicca per dare priorità."
        case .inCorso:
            return "In corso di elaborazione..."
        case .processata:
            if let result = tag.processingResult {
                return "Elaborata: \(result)"
            }
            return "Email elaborata correttamente"
        case .errore:
            if let error = tag.processingError {
                return "Errore: \(error). Clicca per riprovare."
            }
            return "Errore durante l'elaborazione. Clicca per riprovare."
        case .saltata:
            if let reason = tag.processingError {
                return "Saltata: \(reason). Clicca per processare manualmente."
            }
            return "Email saltata. Clicca per processare manualmente."
        }
    }
}

// MARK: - Category Picker View

/// Popover per selezionare una categoria email
struct EmailCategoryPickerView: View {
    
    let emailId: String
    let currentCategory: EmailCategory?
    let currentTag: EmailCategoryTag?
    let onSelect: (EmailCategory) -> Void
    let onClear: () -> Void
    let onForceReprocess: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    // Categorie raggruppate per tipo
    private var inboundCategories: [EmailCategory] {
        [.assignment, .revocation, .documentationReceived, .actReceived, 
         .reminderReceived, .clarificationRequest, .controlled, .revisionRequested,
         .surveyReturned]
    }
    
    private var outboundCategories: [EmailCategory] {
        [.actSent, .reminderSent, .outcomeSent, .documentationRequest,
         .surveyScheduled, .videocallScheduled]
    }
    
    private var studioCategories: [EmailCategory] {
        [.studioNews, .internalInfo, .procedure, .meeting, .training, .administrative]
    }
    
    private var genericCategories: [EmailCategory] {
        [.genericCommunication]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Seleziona categoria")
                    .font(.headline)
                
                Spacer()
                
                if currentCategory != nil {
                    Button(action: { onClear() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                            Text("Rimuovi")
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Stato di processamento (se presente)
            if let tag = currentTag {
                processingStatusSection(for: tag)
            }
            
            Divider()
            
            // Categorie con layout a griglia
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Sinistri - In arrivo
                    categorySection(
                        title: "📥 Sinistri - In arrivo",
                        categories: inboundCategories
                    )
                    
                    // Sinistri - Inviate
                    categorySection(
                        title: "📤 Sinistri - Inviate",
                        categories: outboundCategories
                    )
                    
                    Divider()
                    
                    // Studio (non sinistri)
                    categorySection(
                        title: "🏢 Studio",
                        categories: studioCategories
                    )
                    
                    // Altro
                    categorySection(
                        title: "📧 Altro",
                        categories: genericCategories
                    )
                }
            }
            .frame(maxHeight: 400)
        }
        .padding(16)
        .frame(width: 360)
        .background(Color(.windowBackgroundColor))
    }
    
    // MARK: - Processing Status Section
    
    @ViewBuilder
    private func processingStatusSection(for tag: EmailCategoryTag) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stato elaborazione")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                // Stato badge
                HStack(spacing: 6) {
                    Image(systemName: tag.processingStatus.iconName)
                        .font(.system(size: 14))
                        .foregroundColor(tag.processingStatus.color)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tag.processingStatus.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(tag.processingStatus.color)
                        
                        if let error = tag.processingError {
                            Text(error)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        } else if let result = tag.processingResult {
                            Text(result)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                
                Spacer()
                
                // Pulsante azione (solo per stati modificabili manualmente)
                if tag.processingStatus.canBeManuallyChanged {
                    processingActionButton(for: tag.processingStatus, color: tag.processingStatus.color, action: onForceReprocess)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(tag.processingStatus.color.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(tag.processingStatus.color.opacity(0.3), lineWidth: 1)
            )
        }
    }
    
    @ViewBuilder
    private func categorySection(title: String, categories: [EmailCategory]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            // Usa LazyVGrid per layout robusto
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 6)
            ], alignment: .leading, spacing: 6) {
                ForEach(categories, id: \.rawValue) { category in
                    categoryButton(for: category)
                }
            }
        }
    }
    
    @ViewBuilder
    private func categoryButton(for category: EmailCategory) -> some View {
        let isSelected = currentCategory == category
        let color = EmailCategoryTag(
            category: category,
            isManual: false,
            confidence: 1.0,
            appliedDate: Date(),
            sinistroId: nil,
            processingStatus: .processata
        ).color
        
        Button(action: { onSelect(category) }) {
            HStack(spacing: 4) {
                Image(systemName: category.iconName)
                    .font(.system(size: 10))
                
                Text(category.displayName)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? color.opacity(0.2) : Color(.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? color : Color(.separatorColor), lineWidth: isSelected ? 1.5 : 0.5)
            )
            .foregroundColor(isSelected ? color : .primary)
        }
        .buttonStyle(.plain)
    }
    
    private func getActionText(for status: EmailProcessingStatus) -> String {
        switch status {
        case .inCoda: return "Prioritizza"
        case .errore: return "Riprova"
        case .saltata: return "Processa"
        default: return "Processa"
        }
    }
    
    private func getActionIcon(for status: EmailProcessingStatus) -> String {
        switch status {
        case .inCoda: return "arrow.up.circle"
        case .errore: return "arrow.clockwise"
        case .saltata: return "play.circle"
        default: return "play.circle"
        }
    }
    
    @ViewBuilder
    private func processingActionButton(for status: EmailProcessingStatus, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: getActionIcon(for: status))
                Text(getActionText(for: status))
            }
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(0.15))
            )
            .foregroundColor(color)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compact Tag View (per liste)

/// Versione compatta del tag per le righe email
struct EmailCategoryTagCompact: View {
    
    let emailId: String
    var showProcessingStatus: Bool = true
    
    @StateObject private var tagManager = EmailTagManager.shared
    @State private var isProcessingAction = false
    
    private var tag: EmailCategoryTag? {
        tagManager.getTag(forEmailId: emailId)
    }
    
    var body: some View {
        if let tag = tag {
            HStack(spacing: 4) {
                // Icona categoria con overlay stato
                categoryIconWithStatus(for: tag)
                    .onTapGesture {
                        if tag.processingStatus != .processata && !isProcessingAction {
                            forceReprocess()
                        }
                    }
            }
            .help(tooltipText(for: tag))
        }
    }
    
    @ViewBuilder
    private func categoryIconWithStatus(for tag: EmailCategoryTag) -> some View {
        ZStack(alignment: .bottomTrailing) {
            // Icona categoria principale
            HStack(spacing: 3) {
                Image(systemName: tag.iconName)
                    .font(.system(size: 9))
                
                if tag.isManual {
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.system(size: 7))
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(tag.color.opacity(getOpacityForStatus(tag.processingStatus)))
            )
            .foregroundColor(getForegroundColorForStatus(tag.processingStatus, baseColor: tag.color))
            .opacity(getOpacityForStatus(tag.processingStatus))
            .overlay(
                // Bordo colorato per stato
                Capsule()
                    .stroke(getBorderColorForStatus(tag.processingStatus), lineWidth: getBorderWidthForStatus(tag.processingStatus))
            )
            
            // Badge stato (solo se non processata e showProcessingStatus attivo)
            if showProcessingStatus && tag.processingStatus != .processata {
                Circle()
                    .fill(tag.processingStatus.color)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Image(systemName: getStatusBadgeIcon(for: tag.processingStatus))
                            .font(.system(size: 5, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .offset(x: 3, y: 3)
            }
        }
    }
    
    private func getOpacityForStatus(_ status: EmailProcessingStatus) -> Double {
        switch status {
        case .inCoda: return 0.6
        case .inCorso: return 1.0
        case .processata: return 1.0
        case .errore: return 0.8
        case .saltata: return 0.5
        }
    }
    
    private func getForegroundColorForStatus(_ status: EmailProcessingStatus, baseColor: Color) -> Color {
        switch status {
        case .inCoda, .saltata: return .gray
        default: return baseColor
        }
    }
    
    private func getBorderColorForStatus(_ status: EmailProcessingStatus) -> Color {
        switch status {
        case .errore: return .red
        case .saltata: return .orange
        case .inCorso: return .blue
        default: return .clear
        }
    }
    
    private func getBorderWidthForStatus(_ status: EmailProcessingStatus) -> CGFloat {
        switch status {
        case .errore, .inCorso: return 1.5
        case .saltata: return 1
        default: return 0
        }
    }
    
    private func getStatusBadgeIcon(for status: EmailProcessingStatus) -> String {
        switch status {
        case .inCoda: return "clock"
        case .inCorso: return "arrow.clockwise"
        case .errore: return "exclamationmark"
        case .saltata: return "forward"
        case .processata: return "checkmark"
        }
    }
    
    private func forceReprocess() {
        // Verifica se lo stato permette modifica manuale
        guard tag?.processingStatus.canBeManuallyChanged ?? false else {
            return
        }
        
        isProcessingAction = true
        Task {
            await tagManager.forceReprocess(emailId: emailId)
            isProcessingAction = false
        }
    }
    
    private func tooltipText(for tag: EmailCategoryTag) -> String {
        var text = tag.displayName
        if tag.isManual {
            text += " (manuale)"
        }
        
        switch tag.processingStatus {
        case .inCoda:
            text += " - In coda (clicca per prioritizzare)"
        case .inCorso:
            text += " - In corso di elaborazione..."
        case .processata:
            if let result = tag.processingResult {
                text += " - \(result)"
            }
        case .errore:
            text += " - Errore (clicca per riprovare)"
            if let error = tag.processingError {
                text += ": \(error)"
            }
        case .saltata:
            text += " - Saltata"
            if let reason = tag.processingError {
                text += ": \(reason)"
            }
            text += " (clicca per processare)"
        }
        
        return text
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        EmailCategoryTagView(emailId: "test-email-1")
        EmailCategoryTagCompact(emailId: "test-email-2")
    }
    .padding()
}
