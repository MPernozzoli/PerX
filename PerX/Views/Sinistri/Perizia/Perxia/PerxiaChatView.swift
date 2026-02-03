import SwiftUI
import AppKit

struct PerxiaStructuredBene: Identifiable {
    let id = UUID()
    let titolo: String
    let anno: String?
    let modello: String?
    let componenti: [String]
    let osservazioni: String?
    let test: String?
    let compatibilita: String?
    let stima: String?
    let note: String?
    let certezze: [String: Double]
}

struct PerxiaChatView: View {
    @ObservedObject var analisi: PerxiaAnalisi
    @ObservedObject var sinistro: Sinistro
    @Environment(\.managedObjectContext) private var viewContext
    private let perxiaService = PerxiaService.shared
    
    @State private var files: [URL] = []
    @State private var fulminazioneToggle: Bool = false
    @State private var sopralluogoToggle: Bool = false
    @State private var structuredBeni: [PerxiaStructuredBene] = []
    @State private var relazioneBozza: String = ""
@State private var beniResult: PerxiaService.PhiBeniResult?
    @State private var isProcessing = false
    @State private var versions: [Int] = [1]
    @State private var selectedVersion: Int = 1
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            versioning
            PerxiaFileSelectorView(files: $files)
            actions
            beniSection
            relazioneSection
        }
        .onAppear {
            fulminazioneToggle = sinistro.fulminazione == "Si" || sinistro.fulminazione == "Sì"
            sopralluogoToggle = sinistro.sopralluogo
        }
        .padding()
    }
    
    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading) {
                Text("Complessità stimata")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(sinistro.complessita ?? "Non calcolata")
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.15)))
            }
            VStack(alignment: .leading) {
                Text("Ubicazione rischio")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(sinistro.ubicazioneValidata ? "Validata" : "Non validata")
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(sinistro.ubicazioneValidata ? Color.green.opacity(0.2) : Color.orange.opacity(0.2)))
                if let note = sinistro.ubicazioneNote, !note.isEmpty {
                    Text(note).font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            Toggle("Fulminazione", isOn: $fulminazioneToggle)
                .toggleStyle(.switch)
            Toggle("Sopralluogo", isOn: $sopralluogoToggle)
                .toggleStyle(.switch)
                .padding(.leading, 8)
        }
    }
    
    private var versioning: some View {
        HStack {
            Text("Versione")
            Picker("Versione", selection: $selectedVersion) {
                ForEach(versions, id: \.self) { v in
                    Text("v\(v)").tag(v)
                }
            }
            .pickerStyle(.segmented)
            Spacer()
            Button {
                let next = (versions.max() ?? 1) + 1
                versions.append(next)
                selectedVersion = next
            } label: {
                Label("Nuova versione", systemImage: "plus.circle")
                    }
            .buttonStyle(.bordered)
        }
    }
    
    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                Task { await runBeniAnalysis() }
            } label: {
                if isProcessing {
                    ProgressView()
                } else {
                    Label("Rigenera descrizioni beni", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isProcessing || files.isEmpty)
            
            Button {
                Task { await runRelationOnly() }
            } label: {
                Label("Rigenera relazione", systemImage: "text.append")
            }
            .buttonStyle(.bordered)
            .disabled(isProcessing || beniResult == nil)
        }
    }
    
    private var beniSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Beni")
                .font(.headline)
            if structuredBeni.isEmpty {
                Text("Nessun bene rilevato")
                    .foregroundColor(.secondary)
            } else {
                ForEach(structuredBeni) { bene in
                    PerxiaBeneCardView(
                        titolo: bene.titolo,
                        anno: bene.anno,
                        fields: [
                            .init(label: "Componenti", value: bene.componenti.joined(separator: ", "), confidence: bene.certezze["componenti"]),
                            .init(label: "Modello", value: bene.modello, confidence: bene.certezze["modello"]),
                            .init(label: "Osservazioni", value: bene.osservazioni, confidence: bene.certezze["osservazioni"]),
                            .init(label: "Test e misure", value: bene.test, confidence: bene.certezze["test"]),
                            .init(label: "Compatibilità garanzia", value: bene.compatibilita, confidence: bene.certezze["compatibilita"]),
                            .init(label: "Stima economica", value: bene.stima, confidence: bene.certezze["stima"]),
                            .init(label: "Note", value: bene.note, confidence: 1.0)
                        ]
                    )
                }
            }
        }
    }
    
    private var relazioneSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Bozza Relazione")
                    .font(.headline)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(relazioneBozza, forType: .string)
                } label: {
                    Label("Copia", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .disabled(relazioneBozza.isEmpty)
            }
            TextEditor(text: $relazioneBozza)
                .frame(minHeight: 160)
                .border(Color.secondary.opacity(0.3))
        }
    }
    
    private func runBeniAnalysis() async {
        guard !files.isEmpty else { return }
        isProcessing = true
        let immagini = files.filter { ["jpg","jpeg","png","gif","webp","heic","heif"].contains($0.pathExtension.lowercased()) }
        let docs = files.filter { $0.pathExtension.lowercased() == "pdf" }
        
        let result = await perxiaService.analizzaBeniSinistro(
                sinistro: sinistro,
            fulminazione: fulminazioneToggle,
            sopralluogo: sopralluogoToggle,
            ubicazione: sinistro.indirizzoAssicurato ?? "",
            propensionePerito: sinistro.propensionePerito ?? "",
            documenti: docs,
            foto: immagini,
            streamCallback: { _ in },
            progressCallback: { _ in },
            partialBeniCallback: { partial in
                beniResult = partial
                
                // Semplifica la mappatura spezzando l'espressione complessa
                let mappedBeni = partial.beni.map { bene -> PerxiaStructuredBene in
                    // Crea il dizionario certezze separatamente
                    var certezze: [String: Double] = [:]
                    certezze["nome"] = bene.certezzaNome ?? 0
                    certezze["modello"] = bene.certezzaModello ?? 0
                    certezze["anno"] = bene.certezzaAnno ?? 0
                    certezze["osservazioni"] = bene.certezzaOsservazioni ?? 0
                    certezze["test"] = bene.certezzaTest ?? 0
                    certezze["compatibilita"] = bene.certezzaCompatibilita ?? 0
                    certezze["stima"] = bene.certezzaStima ?? 0
                    
                    return PerxiaStructuredBene(
                        titolo: bene.nome,
                        anno: bene.anno ?? bene.annoStimato,
                        modello: bene.modello,
                        componenti: bene.componenti ?? [],
                        osservazioni: bene.osservazioni,
                        test: bene.test,
                        compatibilita: bene.compatibilitaDanno,
                        stima: bene.stima,
                        note: bene.note,
                        certezze: certezze
                    )
                }
                
                structuredBeni = mappedBeni
            }
            )
            
            await MainActor.run {
                isProcessing = false
                switch result {
                case .success(let payload):
                    beniResult = payload.beni
                    relazioneBozza = payload.beniText ?? ""
                    
                    // Semplifica la mappatura spezzando l'espressione complessa
                    let mappedBeni = payload.beni.beni.map { bene -> PerxiaStructuredBene in
                        // Crea il dizionario certezze separatamente
                        var certezze: [String: Double] = [:]
                        certezze["nome"] = bene.certezzaNome ?? 0
                        certezze["modello"] = bene.certezzaModello ?? 0
                        certezze["anno"] = bene.certezzaAnno ?? 0
                        certezze["osservazioni"] = bene.certezzaOsservazioni ?? 0
                        certezze["test"] = bene.certezzaTest ?? 0
                        certezze["compatibilita"] = bene.certezzaCompatibilita ?? 0
                        certezze["stima"] = bene.certezzaStima ?? 0
                        
                        return PerxiaStructuredBene(
                            titolo: bene.nome,
                            anno: bene.anno ?? bene.annoStimato,
                            modello: bene.modello,
                            componenti: bene.componenti ?? [],
                            osservazioni: bene.osservazioni,
                            test: bene.test,
                            compatibilita: bene.compatibilitaDanno,
                            stima: bene.stima,
                            note: bene.note,
                            certezze: certezze
                        )
                    }
                    
                    structuredBeni = mappedBeni
            case .failure(let error):
                relazioneBozza = "Errore: \(error.localizedDescription)"
                structuredBeni = []
                beniResult = nil
                }
            }
        }
    
    private func runRelationOnly() async {
        guard let beniResult = beniResult else { return }
        isProcessing = true
        let result = await perxiaService.generaRelazioneDaBeni(
            sinistro: sinistro,
            beni: beniResult,
            fulminazione: fulminazioneToggle,
            sopralluogo: sopralluogoToggle,
            ubicazione: sinistro.indirizzoAssicurato ?? "",
            propensionePerito: sinistro.propensionePerito ?? "",
            streamCallback: { _ in }
        )
        await MainActor.run {
            isProcessing = false
            switch result {
            case .success(let relazione):
                relazioneBozza = relazione
            case .failure(let error):
                relazioneBozza = "Errore: \(error.localizedDescription)"
            }
        }
    }
}