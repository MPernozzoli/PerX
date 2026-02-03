import SwiftUI

struct ColumnMappingView: View {
    let importData: ImportService.ImportData
    @Binding var columnMappings: [ImportService.ColumnMapping]
    let onNext: () -> Void
    
    @State private var localMappings: [String: ImportService.DatabaseField?] = [:]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Associa le colonne del file ai campi del database")
                .font(.title3)
            
            Text("PerX ha provato a indovinare le associazioni in base ai nomi delle colonne. Cerca e seleziona il campo corretto per ogni colonna.")
                .foregroundColor(.secondary)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(importData.headers, id: \.self) { header in
                        ColumnMappingRowView(
                            header: header,
                            selectedField: Binding(
                                get: { localMappings[header] ?? nil },
                                set: { localMappings[header] = $0 }
                            ),
                            suggestedField: getSuggestedField(for: header)
                        )
                    }
                }
                .padding()
            }
            
            HStack {
                Spacer()
                Button("Avanti") {
                    saveMappingsAndProceed()
                }
                .keyboardShortcut(.return)
                .disabled(!isRiferimentoMapped)
            }
        }
        .padding(40)
        .onAppear {
            initializeMappings()
        }
    }
    
    private var isRiferimentoMapped: Bool {
        localMappings.values.contains { $0 == .riferimento }
    }
    
    private func initializeMappings() {
        // Pre-compila i mapping basandosi sui mapping salvati e su una logica euristica
        let savedMappings = ImportService.shared.savedColumnMappings
        
        for header in importData.headers {
            if let targetFieldRaw = savedMappings[header],
               let targetField = ImportService.DatabaseField(rawValue: targetFieldRaw) {
                localMappings[header] = targetField
            } else {
                // Logica euristica per indovinare
                let suggested = getSuggestedField(for: header)
                localMappings[header] = suggested
            }
        }
    }
    
    private func getSuggestedField(for header: String) -> ImportService.DatabaseField? {
        // Prima prova con il sistema di memoria (con matching fuzzy)
        if let savedField = ImportService.shared.findSavedColumnMapping(for: header) {
            return savedField
        }
        
        // Logica euristica deterministica basata sul mapping Python
        // PRIORITÀ: match esatti e sinonimi comuni per evitare associazioni errate
        let normalized = header.lowercased()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "_", with: " ")
        
        // Mappatura esplicita per evitare swap (basata su Python)
        let explicitMappings: [(keywords: [String], field: ImportService.DatabaseField)] = [
            // Riferimento (priorità massima)
            (["riferimento", "rif.", "rif interno", "riferimento interno", "codice pratica"], .riferimento),
            
            // Numero sinistro compagnia (NON confondere con agenzia)
            (["numero sinistro", "n. sinistro", "sinistro compagnia", "numero sinistro compagnia", 
              "n sinistro", "num sinistro", "cod sinistro"], .numeroSinistroCompagnia),
            
            // Agenzia (NON confondere con numero sinistro)
            (["agenzia", "nome agenzia", "agenzia assicurativa"], .agenzia),
            (["codice agenzia", "cod agenzia", "cod. agenzia"], .codiceAgenzia),
            
            // Compagnia
            (["compagnia", "nome compagnia", "compagnia assicurativa", "assicurazione"], .nomeCompagnia),
            (["gruppo", "gruppo assicurativo"], .gruppo),
            (["area"], .area),
            
            // Stato
            (["stato", "stato sinistro", "status"], .stato),
            
            // Date
            (["data sinistro", "data evento", "data del sinistro"], .dataSinistro),
            (["data apertura", "data apertura gestione", "data inizio", "data gestione"], .dataAperturaGestione),
            (["data incarico", "data assegnazione"], .dataIncarico),
            (["data denuncia"], .dataDenuncia),
            (["data sopralluogo", "data visita"], .dataSopralluogo),
            (["data chiusura", "data fine"], .dataChiusura),
            (["data invio atto", "data atto"], .dataInvioAtto),
            (["data revoca"], .dataRevoca),
            
            // Attori
            (["assicurato", "nome assicurato", "nominativo assicurato"], .nomeAssicurato),
            (["contraente", "nome contraente"], .nomeContraente),
            (["danneggiato", "nome danneggiato"], .nomeDanneggiato),
            
            // Contatti
            (["telefono assicurato", "tel assicurato", "telefono"], .telefonoAssicurato),
            (["email assicurato", "mail assicurato", "email"], .emailAssicurato),
            (["indirizzo assicurato", "indirizzo"], .indirizzoAssicurato),
            (["telefono contraente", "tel contraente"], .telefonoContraente),
            (["email contraente", "mail contraente"], .emailContraente),
            (["indirizzo contraente"], .indirizzoContraente),
            
            // Importi
            (["richiesta", "importo richiesto", "richiesto"], .richiesta),
            (["liquidato", "importo liquidato"], .liquidato),
            (["danno accertato", "danno"], .dannoAccertato),
            (["danno netto", "danno accertato netto"], .dannoAccertatoNetto),
            (["stima", "stima danno"], .stimaDanno),
            
            // Polizza
            (["polizza", "numero polizza", "n. polizza"], .numeroPolizza),
            (["tipo polizza", "tipologia polizza"], .tipoPolizza),
            
            // Altro
            (["definizione", "esito"], .definizione)
        ]
        
        // Cerca match esatto o contenuto nelle keywords
        for mapping in explicitMappings {
            for keyword in mapping.keywords {
                // Match esatto
                if normalized == keyword {
                    return mapping.field
                }
                // Match contenuto (ma solo se il keyword è abbastanza lungo)
                if keyword.count >= 5 && normalized.contains(keyword) {
                    return mapping.field
                }
            }
        }
        
        // Fallback: match parziale sui rawValue/displayName (solo per campi non ambigui)
        // ESCLUDI agenzia e numeroSinistroCompagnia dal fallback per evitare swap
        let safeFields = ImportService.DatabaseField.allCases.filter { field in
            field != .agenzia && 
            field != .codiceAgenzia && 
            field != .numeroSinistroCompagnia
        }
        
        return safeFields.first { field in
            let fieldNormalized = field.rawValue.lowercased()
            let displayNormalized = field.displayName.lowercased().replacingOccurrences(of: " ", with: "")
            return normalized.contains(fieldNormalized) || 
                   normalized.contains(displayNormalized)
        }
    }
    
    private func saveMappingsAndProceed() {
        columnMappings = localMappings.compactMap { header, field in
            guard let field = field else { return nil }
            
            // Salva il mapping nella memoria
            ImportService.shared.saveColumnMapping(columnName: header, targetField: field)
            
            return ImportService.ColumnMapping(
                sourceColumn: header,
                targetField: field,
                isRequired: field.isRequired
            )
        }
        
        onNext()
    }
} 