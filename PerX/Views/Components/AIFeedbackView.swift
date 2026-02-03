import SwiftUI

/// Componente UI per il feedback su risultati AI
struct AIFeedbackView: View {
    let result: AIResult
    let task: AITask
    var userContext: [String: Any]? = nil
    var onFeedbackSubmitted: ((AIFeedbackType) -> Void)? = nil
    
    @State private var showFeedbackSheet = false
    @State private var selectedFeedbackType: AIFeedbackType?
    @State private var additionalComments = ""
    @State private var selectedIssues: Set<String> = []
    @State private var suggestedImprovements = ""
    
    private let commonIssues = [
        "Risultato impreciso",
        "Risultato incompleto",
        "Risultato non pertinente",
        "Linguaggio inappropriato",
        "Mancano informazioni importanti",
        "Troppo generico",
        "Troppo tecnico",
        "Troppo verboso",
        "Altro"
    ]
    
    var body: some View {
        HStack(spacing: 8) {
            // Pollice su
            Button(action: {
                selectedFeedbackType = .positive
                submitPositiveFeedback()
            }) {
                Image(systemName: "hand.thumbsup.fill")
                    .foregroundColor(.green)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Feedback positivo")
            
            // Pollice giù
            Button(action: {
                selectedFeedbackType = .negative
                showFeedbackSheet = true
            }) {
                Image(systemName: "hand.thumbsdown.fill")
                    .foregroundColor(.red)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Feedback negativo")
        }
        .sheet(isPresented: $showFeedbackSheet) {
            FeedbackDetailSheet(
                result: result,
                task: task,
                userContext: userContext,
                additionalComments: $additionalComments,
                selectedIssues: $selectedIssues,
                suggestedImprovements: $suggestedImprovements,
                onSubmit: {
                    submitNegativeFeedback()
                },
                onCancel: {
                    showFeedbackSheet = false
                }
            )
        }
    }
    
    private func submitPositiveFeedback() {
        AIFeedbackService.shared.submitPositiveFeedback(
            for: result,
            task: task,
            additionalComments: nil,
            userContext: userContext
        )
        
        onFeedbackSubmitted?(.positive)
        
        // Mostra conferma breve
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Feedback visivo (può essere migliorato con notifica)
        }
    }
    
    private func submitNegativeFeedback() {
        let issues = Array(selectedIssues)
        let improvements = suggestedImprovements.isEmpty ? nil : suggestedImprovements
        let comments = additionalComments.isEmpty ? nil : additionalComments
        
        AIFeedbackService.shared.submitNegativeFeedback(
            for: result,
            task: task,
            additionalComments: comments,
            specificIssues: issues.isEmpty ? nil : issues,
            suggestedImprovements: improvements,
            userContext: userContext
        )
        
        onFeedbackSubmitted?(.negative)
        showFeedbackSheet = false
        
        // Reset form
        additionalComments = ""
        selectedIssues = []
        suggestedImprovements = ""
    }
}

/// Sheet dettagliato per feedback negativo
struct FeedbackDetailSheet: View {
    let result: AIResult
    let task: AITask
    var userContext: [String: Any]? = nil
    
    @Binding var additionalComments: String
    @Binding var selectedIssues: Set<String>
    @Binding var suggestedImprovements: String
    
    var onSubmit: () -> Void
    var onCancel: () -> Void
    
    private let commonIssues = [
        "Risultato impreciso",
        "Risultato incompleto",
        "Risultato non pertinente",
        "Linguaggio inappropriato",
        "Mancano informazioni importanti",
        "Troppo generico",
        "Troppo tecnico",
        "Troppo verboso",
        "Altro"
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Text("Feedback Negativo")
                    .font(.title2)
                    .bold()
                Spacer()
                Button("Annulla", action: onCancel)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Problemi specifici
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Quali problemi hai riscontrato?")
                            .font(.headline)
                        
                        ForEach(commonIssues, id: \.self) { issue in
                            HStack {
                                Button(action: {
                                    if selectedIssues.contains(issue) {
                                        selectedIssues.remove(issue)
                                    } else {
                                        selectedIssues.insert(issue)
                                    }
                                }) {
                                    Image(systemName: selectedIssues.contains(issue) ? "checkmark.square.fill" : "square")
                                        .foregroundColor(selectedIssues.contains(issue) ? .blue : .secondary)
                                }
                                .buttonStyle(.plain)
                                
                                Text(issue)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    .padding()
                    
                    Divider()
                    
                    // Commenti aggiuntivi
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Commenti aggiuntivi (opzionale)")
                            .font(.headline)
                        
                        TextEditor(text: $additionalComments)
                            .frame(height: 100)
                            .padding(8)
                            .background(Color(.textBackgroundColor))
                            .cornerRadius(8)
                    }
                    .padding()
                    
                    Divider()
                    
                    // Suggerimenti miglioramenti
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Come potremmo migliorare? (opzionale)")
                            .font(.headline)
                        
                        TextEditor(text: $suggestedImprovements)
                            .frame(height: 100)
                            .padding(8)
                            .background(Color(.textBackgroundColor))
                            .cornerRadius(8)
                    }
                    .padding()
                }
            }
            
            Divider()
            
            // Footer con pulsanti
            HStack {
                Spacer()
                Button("Annulla", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Invia Feedback", action: onSubmit)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 600, height: 700)
    }
}

/// Wrapper per mostrare feedback inline in una view
struct AIFeedbackInlineView: View {
    let result: AIResult
    let task: AITask
    var userContext: [String: Any]? = nil
    
    var body: some View {
        HStack {
            Text("Questo risultato ti è stato utile?")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            AIFeedbackView(
                result: result,
                task: task,
                userContext: userContext
            )
        }
        .padding(.vertical, 4)
    }
}

