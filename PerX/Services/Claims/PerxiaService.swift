import Foundation
import CoreData

class PerxiaService: ObservableObject {
    static let shared = PerxiaService()
    
    let cloudAIService = CloudAIService.shared
    let htmlParser = PerxiaHTMLParser.shared
    let fileTagManager = FileTagManager.shared
    let fileService = FileService.shared
    let knowledgeService = AIKnowledgeService.shared
    let localModelService = LocalModelService.shared
    
    private init() {}
    
    struct FileAnalysisResult: Codable {
        let path: String
        let tipo: String
        let descrizione: String
        let contesto: String?
        let misure: String?
        let validitaMisura: String?
        let anomalieVisive: String?
        let tagSuggerito: String?  // ID del tag (es. "foto_bene", "foto_componente")
        let tagCommento: String?  // Componente: testo aggiuntivo per tag che richiedono descrizione (es. "scheda elettronica" per foto_componente)
        let beneRiferimento: String?  // Bene: nome del bene a cui appartiene (es. "caldaia" per foto_componente, foto_test_funzionale, foto_ripristino)
        let daAllegare: Bool  // Se true, da includere nella documentazione per la compagnia
    }
    
    // MARK: - Nuova Pipeline a Fasi
    
    /// Descrizione approfondita di una singola foto
    struct PhotoDescription: Codable {
        let path: String
        let beneRiferimento: String?       // Nome del bene (da tag)
        let componente: String?             // Nome del componente (da tag)
        let descrizioneDettagliata: String  // Descrizione molto accurata del contenuto
        let elementiVisibili: [String]      // Lista elementi visibili (es. "scheda elettronica", "bruciatura", "misura multimetro")
        let testoLeggibile: String?         // Testo/etichette/targhette visibili nella foto
        let misureStrumentali: MisuraStrumentale?
        let anomalieVisive: [String]        // Anomalie visive rilevate
        let qualitaFoto: String             // buona/media/scarsa
    }
    
    struct MisuraStrumentale: Codable {
        let tipoStrumento: String           // es. "multimetro", "megger", "pinza amperometrica"
        let valoreRilevato: String          // es. "12.5 Ω", "0.1 MΩ"
        let unitaMisura: String
        let posizionamentoPuntali: String   // corretto/scorretto/non_valutabile
        let impostazioniStrumento: String   // corrette/scorrette/non_valutabile
        let misuraRisolutiva: Bool          // se la misura è risolutiva per diagnosi FE
        let interpretazione: String         // interpretazione tecnica della misura
    }
    
    /// Analisi completa di un bene con indicatori di confidenza
    struct BeneAnalysis: Codable {
        let nome: String                    // Nome del bene (es. "caldaia")
        let marca: String?
        let modello: String?
        let anno: String?
        let annoStimato: Bool               // true se l'anno è stimato
        let componentiDanneggiati: [String]
        let osservazioniVisive: String      // Descrizione danni visivi
        let testEseguiti: String            // Descrizione test e loro esiti
        let compatibilitaFE: CompatibilitaFE
        let stimaEconomica: StimaEconomica?
        let fotoAssociate: [String]         // Path delle foto
        
        // Indicatori di confidenza (0.0 - 1.0)
        let confidenzaMarca: Double
        let confidenzaModello: Double
        let confidenzaAnno: Double
        let confidenzaOsservazioni: Double
        let confidenzaTest: Double
        let confidenzaCompatibilita: Double
        let confidenzaStima: Double
    }
    
    struct CompatibilitaFE: Codable {
        let esito: String                   // "compatibile", "poco_probabile", "non_compatibile", "indeterminato"
        let motivazione: String             // Spiegazione tecnica dell'esito
        let evidenzeAFavore: [String]       // Elementi che supportano FE
        let evidenzeContrarie: [String]     // Elementi che non supportano FE
    }
    
    struct StimaEconomica: Codable {
        let importo: Double?
        let descrizione: String             // es. "sostituzione scheda elettronica"
        let baseStima: String               // es. "preventivo", "listino", "stima peritale"
        let note: String?
    }
    
    /// Risultato completo dell'analisi sinistro
    struct AnalisiSinistroCompleta: Codable {
        let beni: [BeneAnalysis]
        let complessita: ComplessitaSinistro
        let denuncia: AnalisiDenuncia?
        let giustificativi: AnalisiGiustificativi?
        let verificaUbicazione: VerificaUbicazione?
        let sopralluogo: Bool
        let fulminazione: Bool
        let noteGenerali: String?
    }
    
    // MARK: - Strutture per analisi preliminare
    
    /// Analisi della denuncia di sinistro
    struct AnalisiDenuncia: Codable {
        let ubicazione: UbicazioneDenuncia
        let dataSinistro: String?
        let tipoSinistro: String            // "domestico", "aziendale", "condominiale"
        let descrizioneEvento: String?
        let beniDichiarati: [String]        // Beni menzionati nella denuncia
        let importoRichiesto: Double?
    }
    
    struct UbicazioneDenuncia: Codable {
        let indirizzo: String?
        let civico: String?
        let cap: String?
        let citta: String?
        let provincia: String?
        let indirizzoCompleto: String
    }
    
    /// Analisi dei giustificativi (fatture/preventivi)
    struct AnalisiGiustificativi: Codable {
        let vociPerBene: [VoceGiustificativo]
        let beniNonInFoto: [String]         // Beni nei giustificativi ma non nelle foto
        let vociNonFE: [VoceNonFE]          // Voci non da fenomeno elettrico
        let totaleGiustificativi: Double
        let totaleFECompatibile: Double
        let totaleNonFE: Double
    }
    
    struct VoceGiustificativo: Codable {
        let bene: String                    // Nome del bene
        let componente: String?             // Componente specifico se presente
        let descrizione: String             // Descrizione della voce
        let importo: Double
        let tipoImporto: String             // "ricambio", "manodopera", "a_corpo"
        let fonteDocumento: String          // Path del documento
    }
    
    struct VoceNonFE: Codable {
        let descrizione: String
        let importo: Double
        let motivoEsclusione: String        // es. "pulizia", "programmazione", "opera idraulica"
        let fonteDocumento: String
    }
    
    /// Verifica corrispondenza ubicazione denuncia vs foto
    struct VerificaUbicazione: Codable {
        let corrispondenza: String          // "confermata", "parziale", "non_verificabile", "discrepanza"
        let evidenzeTrovate: [String]       // es. "numero civico visibile", "nome su citofono"
        let discrepanze: [String]           // Eventuali differenze rilevate
        let confidenza: Double
        let note: String?
    }
    
    /// Complessità calcolata del sinistro
    struct ComplessitaSinistro: Codable {
        let livello: String                 // "semplice", "media", "complessa"
        let punteggio: Int                  // 1-10
        let fattori: [String]               // Fattori che determinano la complessità
        let importoTotale: Double
        let numeroBeni: Int
        let tipologieBeni: [String]
    }
    
    // MARK: - Nuove Strutture per Analisi Streaming con Tracciabilità
    
    /// Dato con confidenza e fonte
    struct DatoTracciato<T: Codable>: Codable {
        let valore: T
        let confidenza: Double              // 0.0 - 1.0
        let fontiFoto: [String]             // Path delle foto da cui è stato estratto
        
        /// Livello confidenza per UI
        var livelloConfidenza: LivelloConfidenza {
            if confidenza < 0.6 { return .nonDisponibile }
            if confidenza < 0.76 { return .bassa }
            if confidenza < 0.91 { return .media }
            return .alta
        }
        
        /// Indica se il dato deve essere mostrato (confidenza >= 0.6)
        var daVisualizzare: Bool { confidenza >= 0.6 }
    }
    
    enum LivelloConfidenza: String, Codable {
        case nonDisponibile = "non_disponibile"
        case bassa = "bassa"
        case media = "media"
        case alta = "alta"
        
        var colore: String {
            switch self {
            case .nonDisponibile: return "gray"
            case .bassa: return "orange"
            case .media: return "yellow"
            case .alta: return "green"
            }
        }
        
        var icona: String {
            switch self {
            case .nonDisponibile: return "questionmark.circle"
            case .bassa: return "exclamationmark.triangle"
            case .media: return "checkmark.circle"
            case .alta: return "checkmark.seal.fill"
            }
        }
    }
    
    /// Analisi dettagliata di una singola foto (prima chiamata IA)
    struct AnalisiDettaglioFoto: Codable, Identifiable {
        var id: String { path }
        let path: String
        let tipoFoto: TipoFoto
        
        // Contenuto comune a tutti i tipi
        let descrizioneGenerale: String
        let qualitaFoto: QualitaFoto
        
        // Contenuto specifico per tipo
        let analisiBene: AnalisiFotoBene?
        let analisiScheda: AnalisiFotoScheda?
        let analisiMisura: AnalisiFotoMisura?
        let analisiUbicazione: AnalisiFotoUbicazione?
    }
    
    enum TipoFoto: String, Codable {
        case beneGenerale = "bene_generale"      // Foto panoramica del bene
        case beneDettaglio = "bene_dettaglio"    // Foto dettaglio bene
        case scheda = "scheda"                    // Foto scheda/componente elettronico
        case misura = "misura"                    // Foto di misura strumentale
        case ubicazione = "ubicazione"            // Foto ubicazione/stabile
        case giustificativo = "giustificativo"    // Foto documento
        case altro = "altro"
    }
    
    enum QualitaFoto: String, Codable {
        case buona = "buona"
        case media = "media"
        case scarsa = "scarsa"
    }
    
    /// Analisi specifica per foto di bene generale/dettaglio
    struct AnalisiFotoBene: Codable {
        let ubicazioneInterna: String?          // Dove si trova il bene (es. "locale caldaia")
        let statoManutenzione: String           // Descrizione stato manutenzione
        let marcaVisibile: String?              // Marca se visibile
        let modelloVisibile: String?            // Modello se visibile
        let annoVisibile: String?               // Anno se leggibile
        let targhettaVisibile: Bool             // Se c'è targhetta visibile
        let testoTarghetta: String?             // Testo della targhetta se leggibile
        let segniDanno: [String]                // Segni di danno visibili
        let condizioniDettagliate: String?      // Descrizione dettagliata di usura, bruciature, manomissioni
        let ambienteDescrizione: String?        // Descrizione dettagliata dell'ambiente
        let ambienteConsono: String?            // "sì"/"no"/"parzialmente" - se l'ambiente è consono
        let problemiAmbientali: [String]?        // Lista problemi ambientali
        let confidenzaMarca: Double
        let confidenzaModello: Double
        let confidenzaAnno: Double
    }
    
    /// Analisi specifica per foto di scheda elettronica
    struct AnalisiFotoScheda: Codable {
        let tipoScheda: String                  // es. "scheda alimentazione", "scheda controllo"
        let segniDannoElettrico: [SegnoElettrico]
        let segniDannoNonElettrico: [SegnoNonElettrico]
        let componentiVisibili: [String]        // Componenti identificabili
        let componentiDanneggiati: [String]     // Componenti visibilmente danneggiati
        let valutazioneGenerale: String         // Riassunto analisi
    }
    
    struct SegnoElettrico: Codable {
        let tipo: String                        // "annerimento", "componente_esploso", "bruciatura", "arco_elettrico"
        let descrizione: String
        let posizione: String?                  // Posizione sulla scheda
        let confidenza: Double
        let fotoPath: String?                   // Path della foto da cui è stato identificato
        
        // Codable compatibility: default a nil se non presente
        init(tipo: String, descrizione: String, posizione: String?, confidenza: Double, fotoPath: String? = nil) {
            self.tipo = tipo
            self.descrizione = descrizione
            self.posizione = posizione
            self.confidenza = confidenza
            self.fotoPath = fotoPath
        }
    }
    
    struct SegnoNonElettrico: Codable {
        let tipo: String                        // "usura", "umidita", "spaccatura", "decadimento_dielettrico", "corrosione"
        let descrizione: String
        let posizione: String?
        let confidenza: Double
        let fotoPath: String?                   // Path della foto da cui è stato identificato
        
        // Codable compatibility: default a nil se non presente
        init(tipo: String, descrizione: String, posizione: String?, confidenza: Double, fotoPath: String? = nil) {
            self.tipo = tipo
            self.descrizione = descrizione
            self.posizione = posizione
            self.confidenza = confidenza
            self.fotoPath = fotoPath
        }
    }
    
    /// Analisi specifica per foto di misura strumentale
    struct AnalisiFotoMisura: Codable {
        let tipoStrumento: String               // "multimetro", "megger", "pinza_amperometrica", "termocamera"
        let marcaStrumento: String?
        let modelloStrumento: String?
        
        let valoreDisplay: String?              // Valore letto sul display
        let unitaMisura: String?
        let tipoMisura: String                  // "resistenza", "isolamento", "continuita", "tensione", "corrente"
        let dettagliTest: String?               // Descrizione dettagliata di puntali, impostazioni, condizioni, metodologia
        
        let puntaliImpostatiCorretti: ValiditaTest
        let impostazioniCorrette: ValiditaTest
        let valoreCoerente: ValiditaTest       // Coerenza con bene/componente testato
        
        let interpretazione: String             // Interpretazione tecnica del risultato e se aiuta a determinare FE
        let indicaDanno: Bool?                  // true=indica danno, false=OK, nil=non valutabile
        
        let testValido: Bool                    // Se il test è considerato valido complessivamente
        let motivoInvalidita: String?           // Breve relazione (2-3 frasi) sul perché il test non è valido o non aiuta a determinare FE
        let relazioneTest: String?              // Relazione (2-3 frasi) che spiega se e come il test aiuta a determinare se è FE (sempre presente, sia per test validi che non validi)
        
        let confidenzaLettura: Double
        let confidenzaInterpretazione: Double
    }
    
    enum ValiditaTest: String, Codable {
        case corretto = "corretto"
        case scorretto = "scorretto"
        case nonValutabile = "non_valutabile"
    }
    
    /// Analisi specifica per foto ubicazione/stabile
    struct AnalisiFotoUbicazione: Codable {
        // Elementi identificativi
        let indirizzoVisibile: String?          // Indirizzo se leggibile
        let civicoVisibile: String?             // Numero civico se leggibile
        let nomeCitofonoVisibile: String?       // Nome su citofono se leggibile
        let altriElementiIdentificativi: [String]
        
        // Descrizione stabile (per Quadro Contrattuale)
        let tipoFabbricato: String?             // "appartamento", "villa", "condominio", "capannone"...
        let numeroPiani: Int?
        let annoCostruzioneStimato: String?
        let tipoCopertura: String?              // "tegole", "lamiera", "terrazza"...
        let materialeCostruzione: String?       // "muratura", "prefabbricato"...
        let statoGenerale: String?              // "buono", "discreto", "da ristrutturare"
        let altreCaratteristiche: [String]
        
        // Match con dati noti
        let matchIndirizzo: MatchVerifica?
        let matchNome: MatchVerifica?
        
        // Confidenze
        let confidenzaDescrizione: Double
    }
    
    struct MatchVerifica: Codable {
        let trovato: Bool
        let valoreNoto: String                  // Valore che avevamo noi
        let valoreTrovato: String?              // Valore trovato in foto
        let esito: String                       // "confermato", "parziale", "non_corrisponde", "non_trovato"
        let note: String?
    }
    
    // MARK: - Nuova struttura BeneAnalysis con streaming
    
    /// Analisi completa di un bene con tutti i dati tracciati (nuova versione)
    struct BeneAnalysisStreaming: Codable, Identifiable {
        var id: String { nome }
        let nome: String
        
        // Dati con tracciabilità
        let marca: DatoTracciato<String>?
        let modello: DatoTracciato<String>?
        let anno: DatoTracciato<String>?
        let annoStimato: Bool
        
        // Ubicazione e stato
        let ubicazioneInterna: String?
        let statoManutenzione: DatoTracciato<String>?
        
        // Analisi visiva
        let osservazioniVisive: DatoTracciato<String>
        let segniDannoElettrico: [SegnoElettrico]
        let segniDannoNonElettrico: [SegnoNonElettrico]
        
        // Test strumentali
        let reportMisure: ReportMisure?
        
        // Compatibilità FE
        let compatibilitaFE: CompatibilitaFETracciata
        
        // Stima economica
        let stimaEconomica: StimaEconomicaTracciata?
        
        // Foto associate (per tipo)
        let fotoGenerali: [String]
        let fotoSchede: [String]
        let fotoMisure: [String]
    }
    
    struct ReportMisure: Codable {
        let misureRilevate: [MisuraRilevata]
        let testValidi: Bool                    // Almeno un test è valido
        let sintesiRisultati: String            // Sintesi testuale dei risultati
        let testInvalidiMotivo: String?         // Se tutti invalidi, perché
    }
    
    struct MisuraRilevata: Codable, Identifiable {
        var id: String { fotoPath }
        let fotoPath: String
        let tipoMisura: String
        let strumento: String
        let valore: String
        let unitaMisura: String?
        let dettagliTest: String?              // Descrizione dettagliata di puntali, impostazioni, condizioni, metodologia
        let testValido: Bool
        let motivoInvalidita: String?          // Breve relazione sul perché il test non è valido o non aiuta a determinare FE
        let relazioneTest: String?            // Relazione che spiega se e come il test aiuta a determinare se è FE (sempre presente)
        let interpretazione: String
        let indicaDanno: Bool?
        let confidenzaLettura: Double
        let confidenzaInterpretazione: Double
    }
    
    struct CompatibilitaFETracciata: Codable {
        let esito: String                       // "compatibile", "poco_probabile", "non_compatibile", "indeterminato"
        let motivazione: String
        let evidenzeAFavore: [EvidenzaTracciata]
        let evidenzeContrarie: [EvidenzaTracciata]
        let confidenza: Double
    }
    
    struct EvidenzaTracciata: Codable {
        let descrizione: String
        let fotoFonte: [String]                 // Da quali foto
        let peso: Double                        // Peso dell'evidenza (0-1)
    }
    
    struct StimaEconomicaTracciata: Codable {
        let importo: DatoTracciato<Double>?
        let descrizione: String
        let baseStima: String                   // "preventivo", "listino", "stima_peritale"
        let note: String?
        let vociDettaglio: [VoceStima]?
    }
    
    struct VoceStima: Codable {
        let descrizione: String
        let importo: Double
        let tipo: String                        // "ricambio", "manodopera", "trasporto"
        let fonte: String?                      // Path documento fonte
    }
    
    // MARK: - Analisi Ubicazione per Quadro Contrattuale
    
    struct AnalisiQuadroContrattuale: Codable {
        let tipoFabbricato: DatoTracciato<String>?
        let numeroPiani: DatoTracciato<Int>?
        let annoCostruzione: DatoTracciato<String>?
        let tipoCopertura: DatoTracciato<String>?
        let materialeCostruzione: DatoTracciato<String>?
        let statoGenerale: DatoTracciato<String>?
        let superficie: DatoTracciato<String>?
        let altreCaratteristiche: [String]
        let verificaIndirizzo: MatchVerifica?
        let verificaNome: MatchVerifica?
    }
    
    struct PhiBeniResult: Codable {
        struct Bene: Codable {
            let nome: String  // SOLO nome del bene, senza marca
            let tipoBene: String?
            let marca: String?  // Marca separata dal nome
            let componenti: [String]?
            let modello: String?
            let anno: String?  // Anno se certo
            let annoStimato: String?  // Anno stimato (mostrare con "(stima)")
            let osservazioni: String?
            let test: String?
            let compatibilitaDanno: String?  // Solo questo, non compatibilitaGaranzia
            let stima: String?
            let note: String?  // Ubicazione interna (non mostrare in UI)
            let certezzaNome: Double?
            let certezzaModello: Double?
            let certezzaAnno: Double?
            let certezzaOsservazioni: Double?
            let certezzaTest: Double?
            let certezzaCompatibilita: Double?
            let certezzaStima: Double?
            let foto: [String]?  // Foto generali del bene
            let fonti: [String]?  // Fonti generali
            let fotoOsservazioni: [String]?  // Foto specifiche per osservazioni
            let fotoTest: [String]?  // Foto specifiche per test
            let fotoComponenti: [String]?  // Foto specifiche per componenti
            let componentiDettaglio: [Bene]?
            // Compatibilità Garanzia rimosso - non più utilizzato
        }
        
        let beni: [Bene]
        let complessita: String?
        let ubicazioneValidata: Bool?
        let ubicazioneNote: String?
    }
    
    private struct StaticTemplate: Codable {
        let titolo: String
        let contenuto: String
        let condSopralluogo: Bool?
        let condFulminazione: Bool?
        let condIndennizzo: Bool?
    }
    
    private var defaultTemplates: [StaticTemplate] {
        [
            StaticTemplate(
                titolo: "Sopralluogo, FE, indennizzo",
                contenuto: """
A seguito dell'incarico ricevuto è stato effettuato sopralluogo presso l'ubicazione del rischio previa disponibilità da parte dell’Assicurato.

Al sopralluogo abbiamo preso visione dei beni lamentati danneggiati a seguito del sinistro in oggetto, come di seguito riportati: [ELENCO_BENI con marca e anno se disponibili].
Dalle verifiche tecniche effettuate [visive sicuro, ma poi aggiungere se ci sono state prove strumentali o funzionali] riteniamo il lamentato danno riconducibile ad un fenomeno elettrico.
Si evidenzia la presenza di fulminazioni atmosferiche al suolo in prossimità del rischio assicurato nella data del sinistro.
[OSSERVAZIONI_SINTETICHE]
La stima del danno è stata redatta prendendo altresì in considerazione i giustificativi presentati da parte dell'Assicurato [se abbiamo giustificativi] ed i prezzi medi di mercato per ripristini similari per prestazioni e funzionalità.
La stima è al netto di opere non indennizzabili in garanzia FE (es. danni consequenziali, meccanici, idraulici, programmazione, ricerca guasto, trasporto).
""",
                condSopralluogo: true,
                condFulminazione: true,
                condIndennizzo: true
            ),
            StaticTemplate(
                titolo: "Sopralluogo, no FE",
                contenuto: """
A seguito dell'incarico ricevuto è stato effettuato sopralluogo presso l'ubicazione del rischio previa disponibilità da parte dell’Assicurato.

Al sopralluogo abbiamo preso visione dei beni lamentati danneggiati a seguito del sinistro in oggetto, come di seguito riportati: [ELENCO_BENI con marca e anno se disponibili.].
Dalle verifiche tecniche effettuate (visive, strumentali, funzionali) non riteniamo siano emersi elementi per poter ricondurre il lamentato danno ad un fenomeno elettrico.
[OSSERVAZIONI_SINTETICHE]
La stima del danno è stata redatta prendendo altresì in considerazione i giustificativi presentati da parte dell'Assicurato ed i prezzi medi di mercato per ripristini similari per prestazioni e funzionalità.
La stima è al netto di opere non indennizzabili in garanzia FE (es. danni consequenziali, meccanici, idraulici, programmazione, ricerca guasto, trasporto).
""",
                condSopralluogo: true,
                condFulminazione: false,
                condIndennizzo: false
            ),
            StaticTemplate(
                titolo: "Sopralluogo, residui assenti, beni ripristinati",
                contenuto: """
A seguito dell'incarico ricevuto è stato effettuato sopralluogo presso l'ubicazione del rischio previa disponibilità da parte dell’Assicurato.

Al sopralluogo abbiamo preso visione dei beni oggetto del sinistro già ripristinati, ma non ci sono stati mostrati residui di tali ripristini.
La mancanza dei residui non ci permette di dare indicazioni circa l’origine e la natura del lamentato danno.
[OSSERVAZIONI_SINTETICHE]
La stima del danno è stata redatta per puro scopo di calcolo, prendendo altresì in considerazione i giustificativi presentati da parte dell'Assicurato ed i prezzi medi di mercato per ripristini similari per prestazioni e funzionalità.
La stima è al netto di opere non indennizzabili in garanzia FE (es. danni consequenziali, meccanici, idraulici, programmazione, ricerca guasto, trasporto).
""",
                condSopralluogo: true,
                condFulminazione: nil,
                condIndennizzo: nil
            ),
            StaticTemplate(
                titolo: "Documentale, FE",
                contenuto: """
A seguito dell'incarico ricevuto abbiamo contattato l'Assicurato al fine di acquisire le informazioni necessarie allo svolgimento dell'attività peritale. 

Sulla base di quanto emerso in fase di primo contatto con l’Assicurato, ricorrendo le condizioni previste, abbiamo ritenuto opportuno espletare l’incarico in Authority mediante Perizia Documentale.
È stata acquisita la documentazione fotografica dei beni lamentati danneggiati, come segue: [ELENCO_BENI, marca e anno se disponibile], unitamente ai giustificativi di ripristino del danno [se li abbiamo].
Sulla base di quanto emerso riteniamo il danno riconducibile ad un fenomeno elettrico.
[OSSERVAZIONI_SINTETICHE]
La stima del danno è stata effettuata considerando il prezzo medio di mercato di componenti equivalenti per prestazioni, rendimento e funzionalità.
Non ci risultano aperte altre posizioni di sinistro sui medesimi beni.
La stima è al netto di opere non indennizzabili in garanzia FE (es. danni consequenziali, meccanici, idraulici, programmazione, ricerca guasto, trasporto).
""",
                condSopralluogo: false,
                condFulminazione: true,
                condIndennizzo: true
            ),
            StaticTemplate(
                titolo: "Documentale, no FE",
                contenuto: """
A seguito dell'incarico ricevuto abbiamo contattato l'Assicurato al fine di acquisire le informazioni necessarie allo svolgimento dell'attività peritale. 

Sulla base di quanto emerso in fase di primo contatto con l’Assicurato, ricorrendo le condizioni previste, abbiamo ritenuto opportuno espletare l’incarico in Authority mediante Perizia Documentale.
È stata acquisita la documentazione fotografica dei beni lamentati danneggiati, come segue: [ELENCO_BENI, marca e anno se disponibile], unitamente ai giustificativi di ripristino del danno. [se li abbiamo]
Sulla base di quanto emerso non riteniamo siano emersi elementi per poter ricondurre il lamentato danno ad un fenomeno elettrico.
[OSSERVAZIONI_SINTETICHE]
La stima del danno è stata effettuata considerando il prezzo medio di mercato di componenti equivalenti per prestazioni, rendimento e funzionalità.
Non ci risultano aperte altre posizioni di sinistro sui medesimi beni.
La stima è al netto di opere non indennizzabili in garanzia FE (es. danni consequenziali, meccanici, idraulici, programmazione, ricerca guasto, trasporto).
""",
                condSopralluogo: false,
                condFulminazione: false,
                condIndennizzo: false
            )
        ]
    }
    
    private func templatesJSON() -> String {
        if let data = try? JSONEncoder().encode(defaultTemplates),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return "[]"
    }
    
    private func selectTemplate(sopralluogo: Bool, fulminazione: Bool, indennizzo: Bool) -> String {
        // Cerca template che corrisponde alle condizioni
        let matching = defaultTemplates.first { template in
            let matchSopralluogo = template.condSopralluogo == nil || template.condSopralluogo == sopralluogo
            let matchFulminazione = template.condFulminazione == nil || template.condFulminazione == fulminazione
            let matchIndennizzo = template.condIndennizzo == nil || template.condIndennizzo == indennizzo
            return matchSopralluogo && matchFulminazione && matchIndennizzo
        }
        return matching?.contenuto ?? defaultTemplates.first?.contenuto ?? ""
    }
    
    // MARK: - Nuova Pipeline a 5 Fasi
    
    /// Errore per documentazione mancante
    enum PeriziaPrerequisiteError: Error, LocalizedError {
        case noPhotosInFolder
        case noTaggedPhotos
        case autoTaggingFailed
        case sinistroChiuso
        
        var errorDescription: String? {
            switch self {
            case .noPhotosInFolder:
                return "Nessuna documentazione fotografica presente nella cartella del sinistro."
            case .noTaggedPhotos:
                return "Nessuna foto taggata trovata. Eseguire prima l'autotagging."
            case .autoTaggingFailed:
                return "Autotagging fallito. Nessuna foto analizzabile trovata."
            case .sinistroChiuso:
                return "Sinistro chiuso: analisi disabilitata."
            }
        }
    }
    
    /// Verifica prerequisiti per la perizia e avvia autotagging se necessario
    /// - Returns: true se i prerequisiti sono soddisfatti, false altrimenti
    func verificaPrerequisiti(
        sinistro: Sinistro,
        streamCallback: @escaping @MainActor (String) -> Void
    ) async -> Result<Bool, PeriziaPrerequisiteError> {
        print("[PerxiaService] 🔍 Verifica prerequisiti per sinistro \(sinistro.riferimento ?? "N/A")")

        if (sinistro.stato ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .contains("chius") {
            print("[PerxiaService] ⏭️ Sinistro chiuso: skip prerequisiti/autotagging")
            return .failure(.sinistroChiuso)
        }
        
        // PRIMA verifica se ci sono foto taggate (più veloce e diretto)
        let hasTagged = await MainActor.run { AutoCheckService.shared.hasTaggedPhotos(for: sinistro) }
        print("[PerxiaService] 🏷️ Foto taggate: \(hasTagged)")
        
        if hasTagged {
            print("[PerxiaService] ✅ Foto taggate trovate, prerequisiti OK")
            return .success(true)
        }
        
        // Se non ci sono foto taggate, verifica se ci sono foto nella cartella
        let hasPhotos = await MainActor.run { AutoCheckService.shared.hasPhotosInFolder(for: sinistro) }
        print("[PerxiaService] 📸 Foto nella cartella: \(hasPhotos)")
        
        guard hasPhotos else {
            print("[PerxiaService] ❌ Nessuna foto nella cartella")
            await streamCallback("❌ Nessuna documentazione fotografica presente nella cartella.\n")
            return .failure(.noPhotosInFolder)
        }
        
        // Ci sono foto ma non taggate, avvia autotagging
        print("[PerxiaService] ⚠️ Nessuna foto taggata, avvio autotagging...")
        await streamCallback("⚠️ Nessuna foto taggata trovata. Avvio autotagging automatico...\n")
        
        let taggedCount = await AutoCheckService.shared.runPhotoAutoTagging(for: sinistro, forceReanalyze: false)
        print("[PerxiaService] ✅ Autotagging completato: \(taggedCount) foto taggate")
        
        if taggedCount == 0 {
            print("[PerxiaService] ❌ Autotagging fallito: nessuna foto analizzata")
            await streamCallback("❌ Autotagging completato ma nessuna foto analizzata.\n")
            return .failure(.autoTaggingFailed)
        }
        
        await streamCallback("✅ Autotagging completato: \(taggedCount) foto taggate.\n")
        print("[PerxiaService] ✅ Prerequisiti verificati con successo")
        return .success(true)
    }
    
    /// Pipeline principale: analizza sinistro in 5 fasi
    /// Fase 0: Analisi preliminare (denuncia, giustificativi, foto ubicazione)
    /// Fase 1: Descrizione approfondita foto beni
    /// Fase 2: Raggruppamento per bene (usa tag)
    /// Fase 3: Analisi FE per ogni bene (con info giustificativi)
    /// Fase 4: Generazione relazione + calcolo complessità (parallelo)
    func analizzaSinistroCompleto(
        sinistro: Sinistro,
        fulminazione: Bool,
        sopralluogo: Bool,
        ubicazione: String,
        streamCallback: @escaping @MainActor (String) -> Void,
        progressCallback: @escaping @MainActor (Double) -> Void = { _ in },
        beneCallback: @escaping @MainActor (BeneAnalysis) -> Void = { _ in }
    ) async -> Result<(analisi: AnalisiSinistroCompleta, relazione: String), AIError> {
        print("[PerxiaService] 🚀 analizzaSinistroCompleto avviato per \(sinistro.riferimento ?? "N/A")")

        if sinistro.stato?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "chiuso" {
            print("[PerxiaService] ⏭️ Sinistro chiuso: skip analizzaSinistroCompleto")
            return .failure(.processingError("Sinistro chiuso"))
        }
        
        guard let riferimento = sinistro.riferimento,
              let rootPath = fileService.getSinistroPath(riferimento: riferimento) else {
            print("[PerxiaService] ❌ Cartella sinistro non trovata")
            return .failure(.processingError("Cartella sinistro non trovata"))
        }
        
        print("[PerxiaService] 📁 Cartella sinistro: \(rootPath)")
        
        // Verifica prerequisiti (foto taggate)
        print("[PerxiaService] 🔍 Verifica prerequisiti...")
        let prerequisitiResult = await verificaPrerequisiti(sinistro: sinistro, streamCallback: streamCallback)
        switch prerequisitiResult {
        case .failure(let error):
            print("[PerxiaService] ❌ Prerequisiti falliti: \(error.localizedDescription)")
            return .failure(.processingError(error.localizedDescription))
        case .success:
            print("[PerxiaService] ✅ Prerequisiti OK, procedo con l'analisi")
            break
        }
        
        // FASE 0: Analisi preliminare (denuncia, giustificativi, foto ubicazione)
        await MainActor.run {
            streamCallback("📋 Fase 0: Analisi documentazione preliminare...\n")
            progressCallback(0.02)
        }
        
        // Raccogli lista beni/componenti dai tag per passarla all'analisi giustificativi
        let beniComponentiTaggati = await raccogliBeniComponentiDaTag(rootPath: rootPath)
        
        // Trova documenti per analisi preliminare
        let denunciaPath = await trovaFileDenuncia(rootPath: rootPath)
        let giustificativiPaths = await trovaFileGiustificativi(rootPath: rootPath)
        let fotoUbicazionePaths = await trovaFotoUbicazione(rootPath: rootPath)
        
        // Analizza denuncia
        var analisiDenuncia: AnalisiDenuncia? = nil
        if let denunciaPath = denunciaPath {
            await MainActor.run {
                streamCallback("  → Analisi denuncia...\n")
            }
            analisiDenuncia = await fase0_analizzaDenuncia(path: denunciaPath, sinistro: sinistro)
        }
        
        // Analizza giustificativi
        var analisiGiustificativi: AnalisiGiustificativi? = nil
        if !giustificativiPaths.isEmpty {
            await MainActor.run {
                streamCallback("  → Analisi giustificativi (\(giustificativiPaths.count) documenti)...\n")
            }
            analisiGiustificativi = await fase0_analizzaGiustificativi(
                paths: giustificativiPaths,
                beniTaggati: beniComponentiTaggati.beni,
                componentiTaggati: beniComponentiTaggati.componenti,
                sinistro: sinistro
            )
        }
        
        // Analizza foto ubicazione per verifica
        var verificaUbicazione: VerificaUbicazione? = nil
        if !fotoUbicazionePaths.isEmpty, let denuncia = analisiDenuncia {
            await MainActor.run {
                streamCallback("  → Verifica ubicazione (\(fotoUbicazionePaths.count) foto)...\n")
            }
            verificaUbicazione = await fase0_verificaUbicazione(
                fotoUbicazione: fotoUbicazionePaths,
                denuncia: denuncia,
                sinistro: sinistro
            )
        }
        
        await MainActor.run {
            progressCallback(0.10)
        }
        
        // FASE 1: Descrizione approfondita foto beni
        await MainActor.run {
            streamCallback("\n🔍 Fase 1: Analisi approfondita foto beni...\n")
        }
        
        let fotoDescriptions = await fase1_analizzaFotoApprofondite(
            sinistro: sinistro,
            rootPath: rootPath,
            streamCallback: streamCallback,
            progressCallback: { p in progressCallback(0.10 + p * 0.25) }
        )
        
        // FASE 2: Raggruppamento per bene
        await MainActor.run {
            streamCallback("\n📦 Fase 2: Raggruppamento per bene...\n")
            progressCallback(0.35)
        }
        
        let fotoPerBene = fase2_raggruppaPerBene(
            descrizioni: fotoDescriptions,
            rootPath: rootPath
        )
        
        await MainActor.run {
            let beniCount = fotoPerBene.keys.count
            streamCallback("Trovati \(beniCount) beni da analizzare\n")
            progressCallback(0.38)
        }
        
        // FASE 3: Analisi FE per ogni bene (con info giustificativi)
        await MainActor.run {
            streamCallback("\n⚡ Fase 3: Analisi FE per bene...\n")
        }
        
        var beniAnalizzati: [BeneAnalysis] = []
        // Ordina i beni alfabeticamente, ma metti "Bene non identificato" per ultimo
        let beniList = Array(fotoPerBene.keys).sorted { b1, b2 in
            if b1 == "Bene non identificato" { return false }
            if b2 == "Bene non identificato" { return true }
            return b1.localizedCaseInsensitiveCompare(b2) == .orderedAscending
        }
        
        for (index, bene) in beniList.enumerated() {
            let fotoDelBene = fotoPerBene[bene] ?? []
            
            // Estrai info giustificativi per questo bene
            let vociGiustificativo = analisiGiustificativi?.vociPerBene.filter { 
                $0.bene.lowercased() == bene.lowercased() 
            } ?? []
            
            await MainActor.run {
                let giustInfo = vociGiustificativo.isEmpty ? "" : " + giustificativi"
                streamCallback("  → Analisi: \(bene) (\(fotoDelBene.count) foto\(giustInfo))...\n")
            }
            
            if let analisi = await fase3_analizzaBeneFE(
                nomeBene: bene,
                foto: fotoDelBene,
                vociGiustificativo: vociGiustificativo,
                sinistro: sinistro,
                fulminazione: fulminazione,
                sopralluogo: sopralluogo,
                streamCallback: streamCallback
            ) {
                beniAnalizzati.append(analisi)
                await MainActor.run {
                    beneCallback(analisi)
                }
            }
            
            let progress = 0.38 + (Double(index + 1) / Double(max(1, beniList.count))) * 0.40
            await MainActor.run { progressCallback(progress) }
        }
        
        // FASE 4: Generazione relazione + calcolo complessità (parallelo)
        await MainActor.run {
            streamCallback("\n📝 Fase 4: Generazione relazione e calcolo complessità...\n")
            progressCallback(0.80)
        }
        
        // Esegui in parallelo: relazione e complessità
        async let complessitaTask = calcolaComplessitaSinistro(
            beni: beniAnalizzati,
            giustificativi: analisiGiustificativi
        )
        
        let complessita = await complessitaTask
        
        let analisiCompleta = AnalisiSinistroCompleta(
            beni: beniAnalizzati,
            complessita: complessita,
            denuncia: analisiDenuncia,
            giustificativi: analisiGiustificativi,
            verificaUbicazione: verificaUbicazione,
            sopralluogo: sopralluogo,
            fulminazione: fulminazione,
            noteGenerali: nil
        )
        
        // Salva analisi in Core Data
        salvaAnalisiCompleta(sinistro: sinistro, analisi: analisiCompleta)
        
        let relazioneResult = await fase4_generaRelazione(
            sinistro: sinistro,
            analisi: analisiCompleta,
            ubicazione: ubicazione,
            streamCallback: streamCallback
        )
        
        await MainActor.run { progressCallback(1.0) }
        
        switch relazioneResult {
        case .success(let relazione):
            return .success((analisiCompleta, relazione))
        case .failure(let error):
            return .failure(error)
        }
    }
    
    // MARK: - Fase 0: Analisi preliminare
    
    private func raccogliBeniComponentiDaTag(rootPath: String) async -> (beni: [String], componenti: [String]) {
        // Usa dizionario per normalizzare case-insensitive
        var beniMap: [String: String] = [:] // chiave normalizzata -> nome formattato
        var componentiMap: [String: String] = [:]
        
        let fotoTaggate = await trovaTutteLesFotoTaggate(rootPath: rootPath)
        
        for (path, tags) in fotoTaggate {
            if let bene = await estraiBeneDaTag(path: path, tags: tags), !bene.isEmpty {
                let chiave = bene.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if beniMap[chiave] == nil {
                    // Capitalizza la prima lettera
                    beniMap[chiave] = bene.prefix(1).uppercased() + bene.dropFirst().lowercased()
                }
            }
            if let comp = await estraiComponenteDaTag(path: path, tags: tags), !comp.isEmpty {
                let chiave = comp.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if componentiMap[chiave] == nil {
                    componentiMap[chiave] = comp.prefix(1).uppercased() + comp.dropFirst().lowercased()
                }
            }
        }
        
        return (Array(beniMap.values).sorted(), Array(componentiMap.values).sorted())
    }
    
    private func trovaFileDenuncia(rootPath: String) async -> String? {
        let denunciaTag = FileTagManager.FileTag.availableTags.first { $0.id == "denuncia" }
        if let tag = denunciaTag {
            let files = await fileTagManager.getFilesWithTag(tag)
            return files.first { $0.hasPrefix(rootPath) }
        }
        return nil
    }
    
    private func trovaFileGiustificativi(rootPath: String) async -> [String] {
        var result: [String] = []
        
        let fatturaTag = FileTagManager.FileTag.availableTags.first { $0.id == "fattura" }
        let preventivoTag = FileTagManager.FileTag.availableTags.first { $0.id == "preventivo" }
        
        if let tag = fatturaTag {
            let files = await fileTagManager.getFilesWithTag(tag)
            result.append(contentsOf: files.filter { $0.hasPrefix(rootPath) })
        }
        if let tag = preventivoTag {
            let files = await fileTagManager.getFilesWithTag(tag)
            result.append(contentsOf: files.filter { $0.hasPrefix(rootPath) })
        }
        
        return result
    }
    
    private func trovaFotoUbicazione(rootPath: String) async -> [String] {
        var result: [String] = []
        
        let ubicazioneTags = ["foto_ubicazione_rischio", "foto_ubicazione_tecnico", "foto_ubicazione_altra"]
        
        for tagId in ubicazioneTags {
            if let tag = FileTagManager.FileTag.availableTags.first(where: { $0.id == tagId }) {
                let files = await fileTagManager.getFilesWithTag(tag)
                result.append(contentsOf: files.filter { $0.hasPrefix(rootPath) })
            }
        }
        
        return result
    }
    
    func fase0_analizzaDenuncia(path: String, sinistro: Sinistro) async -> AnalisiDenuncia? {
        let prompt = """
        Analizza questa denuncia di sinistro ed estrai le informazioni chiave.
        
        ESTRAI:
        1. UBICAZIONE: indirizzo completo del sinistro (via, civico, CAP, città, provincia)
        2. DATA SINISTRO: data in cui si è verificato l'evento
        3. TIPO SINISTRO: domestico/aziendale/condominiale/agricolo
        4. DESCRIZIONE: breve descrizione dell'evento denunciato
        5. BENI DICHIARATI: elenco beni menzionati come danneggiati
        6. IMPORTO RICHIESTO: se indicato un importo di richiesta danni
        
        RISPONDI SOLO CON JSON:
        {
            "ubicazione": {
                "indirizzo": "via/piazza",
                "civico": "numero",
                "cap": "CAP",
                "citta": "città",
                "provincia": "sigla",
                "indirizzoCompleto": "indirizzo completo su una riga"
            },
            "dataSinistro": "data o null",
            "tipoSinistro": "domestico/aziendale/condominiale/agricolo",
            "descrizioneEvento": "descrizione breve",
            "beniDichiarati": ["bene1", "bene2"],
            "importoRichiesto": null
        }
        """
        
        let isImage = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp"].contains(URL(fileURLWithPath: path).pathExtension.lowercased())
        
        var parameters: [String: AnyCodable] = [
            "prompt": AnyCodable(prompt),
            "stream": AnyCodable(false)
        ]
        if isImage {
            parameters["images"] = AnyCodable([path])
        }
        
        let task = AITask(
            type: isImage ? .documentAnalysis : .textGeneration,
            priority: .secondary,
            preferredProvider: isImage ? .localMultimodal : .cloudOpenAI,
            fallbackProviders: isImage ? [.cloudOpenAI] : [.localText],
            allowFallback: true,
            parameters: parameters,
            requiresKnowledge: false
        )
        
        let result: Result<AIResult, AIError> = await withCheckedContinuation { cont in
            Task { @MainActor in
                var resumed = false
                AIManager.shared.enqueue(task, completion: { aiResult in
                    if resumed { return }
                    resumed = true
                    cont.resume(returning: aiResult.success ? .success(aiResult) : .failure(aiResult.error ?? .processingError("Errore")))
                })
            }
        }
        
        guard case .success(let aiResult) = result,
              let text = aiResult.result?.value as? String else { return nil }
        
        return parseAnalisiDenuncia(text)
    }
    
    private func parseAnalisiDenuncia(_ text: String) -> AnalisiDenuncia? {
        struct RawDenuncia: Codable {
            let ubicazione: UbicazioneDenuncia
            let dataSinistro: String?
            let tipoSinistro: String
            let descrizioneEvento: String?
            let beniDichiarati: [String]?
            let importoRichiesto: Double?
        }
        
        guard let raw: RawDenuncia = decodeJSONResult(text) else {
            print("[Perxia] ❌ Errore parsing denuncia")
            return nil
        }
        
        return AnalisiDenuncia(
            ubicazione: raw.ubicazione,
            dataSinistro: raw.dataSinistro,
            tipoSinistro: raw.tipoSinistro,
            descrizioneEvento: raw.descrizioneEvento,
            beniDichiarati: raw.beniDichiarati ?? [],
            importoRichiesto: raw.importoRichiesto
        )
    }
    
    func fase0_analizzaGiustificativi(
        paths: [String],
        beniTaggati: [String],
        componentiTaggati: [String],
        sinistro: Sinistro
    ) async -> AnalisiGiustificativi? {
        var tutteLeVoci: [VoceGiustificativo] = []
        var vociNonFE: [VoceNonFE] = []
        var beniGiustificativi = Set<String>()
        
        for path in paths {
            if let result = await analizzaSingoloGiustificativo(
                path: path,
                beniTaggati: beniTaggati,
                componentiTaggati: componentiTaggati
            ) {
                tutteLeVoci.append(contentsOf: result.voci)
                vociNonFE.append(contentsOf: result.vociNonFE)
                result.voci.forEach { beniGiustificativi.insert($0.bene) }
            }
        }
        
        // Trova beni nei giustificativi che non sono nelle foto
        let beniTaggatiSet = Set(beniTaggati.map { $0.lowercased() })
        let beniNonInFoto = beniGiustificativi.filter { !beniTaggatiSet.contains($0.lowercased()) }
        
        let totaleGiust = tutteLeVoci.reduce(0) { $0 + $1.importo }
        let totaleNonFE = vociNonFE.reduce(0) { $0 + $1.importo }
        
        return AnalisiGiustificativi(
            vociPerBene: tutteLeVoci,
            beniNonInFoto: Array(beniNonInFoto).sorted(),
            vociNonFE: vociNonFE,
            totaleGiustificativi: totaleGiust,
            totaleFECompatibile: totaleGiust - totaleNonFE,
            totaleNonFE: totaleNonFE
        )
    }
    
    private func analizzaSingoloGiustificativo(
        path: String,
        beniTaggati: [String],
        componentiTaggati: [String]
    ) async -> (voci: [VoceGiustificativo], vociNonFE: [VoceNonFE])? {
        
        let beniList = beniTaggati.joined(separator: ", ")
        let compList = componentiTaggati.joined(separator: ", ")
        
        let prompt = """
        Analizza questo giustificativo (fattura/preventivo) ed estrai le voci di costo.
        
        BENI PRESENTI NELLE FOTO: \(beniList.isEmpty ? "nessuno identificato" : beniList)
        COMPONENTI PRESENTI NELLE FOTO: \(compList.isEmpty ? "nessuno identificato" : compList)
        
        PER OGNI VOCE DETERMINA:
        1. A quale BENE si riferisce (usa i nomi dei beni nelle foto se corrispondono)
        2. A quale COMPONENTE si riferisce (se specifico)
        3. Se è una voce FE-COMPATIBILE o NON-FE
        
        VOCI NON FE (da escludere dalla stima):
        - Pulizia, lavaggio, sanificazione
        - Programmazione, configurazione software
        - Staffe, supporti metallici, tubi
        - Gas refrigerante, ricarica gas
        - Opere idrauliche, murarie
        - Trasporto, movimentazione
        - Ricerca guasto (se non strumentale)
        - Danni consequenziali
        
        RISPONDI SOLO CON JSON:
        {
            "voci": [
                {
                    "bene": "nome bene",
                    "componente": "componente o null",
                    "descrizione": "descrizione voce",
                    "importo": 123.45,
                    "tipoImporto": "ricambio/manodopera/a_corpo"
                }
            ],
            "vociNonFE": [
                {
                    "descrizione": "descrizione voce",
                    "importo": 50.00,
                    "motivoEsclusione": "pulizia/programmazione/idraulica/etc"
                }
            ]
        }
        """
        
        let isImage = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp"].contains(URL(fileURLWithPath: path).pathExtension.lowercased())
        
        var parameters: [String: AnyCodable] = [
            "prompt": AnyCodable(prompt),
            "stream": AnyCodable(false)
        ]
        if isImage {
            parameters["images"] = AnyCodable([path])
        }
        
        let task = AITask(
            type: isImage ? .documentAnalysis : .textGeneration,
            priority: .secondary,
            preferredProvider: .cloudOpenAI,
            fallbackProviders: [.localMultimodal, .localText],
            allowFallback: true,
            parameters: parameters,
            requiresKnowledge: false
        )
        
        let result: Result<AIResult, AIError> = await withCheckedContinuation { cont in
            Task { @MainActor in
                var resumed = false
                AIManager.shared.enqueue(task, completion: { aiResult in
                    if resumed { return }
                    resumed = true
                    cont.resume(returning: aiResult.success ? .success(aiResult) : .failure(aiResult.error ?? .processingError("Errore")))
                })
            }
        }
        
        guard case .success(let aiResult) = result,
              let text = aiResult.result?.value as? String else { return nil }
        
        return parseGiustificativo(text, fonteDocumento: path)
    }
    
    private func parseGiustificativo(_ text: String, fonteDocumento: String) -> (voci: [VoceGiustificativo], vociNonFE: [VoceNonFE])? {
        struct RawVoce: Codable {
            let bene: String
            let componente: String?
            let descrizione: String
            let importo: Double
            let tipoImporto: String
        }
        
        struct RawNonFE: Codable {
            let descrizione: String
            let importo: Double
            let motivoEsclusione: String
        }
        
        struct RawResult: Codable {
            let voci: [RawVoce]?
            let vociNonFE: [RawNonFE]?
        }
        
        guard let raw: RawResult = decodeJSONResult(text) else {
            print("[Perxia] ❌ Errore parsing giustificativo per \(fonteDocumento)")
            return nil
        }
        
        let voci = (raw.voci ?? []).map { v in
            VoceGiustificativo(
                bene: v.bene,
                componente: v.componente,
                descrizione: v.descrizione,
                importo: v.importo,
                tipoImporto: v.tipoImporto,
                fonteDocumento: fonteDocumento
            )
        }
        
        let vociNonFE = (raw.vociNonFE ?? []).map { v in
            VoceNonFE(
                descrizione: v.descrizione,
                importo: v.importo,
                motivoEsclusione: v.motivoEsclusione,
                fonteDocumento: fonteDocumento
            )
        }
        
        return (voci, vociNonFE)
    }
    
    private func fase0_verificaUbicazione(
        fotoUbicazione: [String],
        denuncia: AnalisiDenuncia,
        sinistro: Sinistro
    ) async -> VerificaUbicazione? {
        
        // Prima analizziamo le foto ubicazione per trovare elementi identificativi
        var elementiTrovati: [String] = []
        
        for path in fotoUbicazione.prefix(5) {  // Max 5 foto
            if let elementi = await analizzaFotoUbicazionePerVerifica(path: path) {
                elementiTrovati.append(contentsOf: elementi)
            }
        }
        
        // Confronta con denuncia
        let prompt = """
        Confronta le informazioni dell'ubicazione dalla denuncia con gli elementi trovati nelle foto.
        
        UBICAZIONE DA DENUNCIA:
        \(denuncia.ubicazione.indirizzoCompleto)
        
        ELEMENTI TROVATI NELLE FOTO UBICAZIONE:
        \(elementiTrovati.isEmpty ? "Nessun elemento identificativo trovato" : elementiTrovati.joined(separator: "\n"))
        
        VALUTA:
        1. Ci sono elementi che CONFERMANO l'ubicazione? (numero civico, nome via, citofono con nome)
        2. Ci sono DISCREPANZE evidenti?
        3. Qual è il livello di confidenza nella corrispondenza?
        
        RISPONDI SOLO CON JSON:
        {
            "corrispondenza": "confermata/parziale/non_verificabile/discrepanza",
            "evidenzeTrovate": ["elemento1", "elemento2"],
            "discrepanze": [],
            "confidenza": 0.8,
            "note": "eventuali note"
        }
        """
        
        let task = AITask(
            type: .textGeneration,
            priority: .secondary,
            preferredProvider: .localText,
            fallbackProviders: [.cloudOpenAI],
            allowFallback: true,
            parameters: [
                "prompt": AnyCodable(prompt),
                "stream": AnyCodable(false)
            ],
            requiresKnowledge: false
        )
        
        let result: Result<AIResult, AIError> = await withCheckedContinuation { cont in
            Task { @MainActor in
                var resumed = false
                AIManager.shared.enqueue(task, completion: { aiResult in
                    if resumed { return }
                    resumed = true
                    cont.resume(returning: aiResult.success ? .success(aiResult) : .failure(aiResult.error ?? .processingError("Errore")))
                })
            }
        }
        
        guard case .success(let aiResult) = result,
              let text = aiResult.result?.value as? String else { return nil }
        
        return parseVerificaUbicazione(text)
    }
    
    private func analizzaFotoUbicazionePerVerifica(path: String) async -> [String]? {
        let prompt = """
        Analizza questa foto di ubicazione e cerca elementi che possano identificare l'indirizzo.
        
        CERCA:
        - Numeri civici visibili
        - Nomi di vie/piazze su targhe
        - Nomi su citofoni/campanelli
        - Insegne con indirizzi
        - Numeri di porta/scala
        - Qualsiasi testo che possa identificare il luogo
        
        RISPONDI SOLO CON JSON:
        {
            "elementiIdentificativi": ["elemento1", "elemento2"]
        }
        
        Se non trovi nulla, rispondi con array vuoto.
        """
        
        let task = AITask(
            type: .documentAnalysis,
            priority: .secondary,
            preferredProvider: .localMultimodal,
            fallbackProviders: [.cloudOpenAI],
            allowFallback: true,
            parameters: [
                "prompt": AnyCodable(prompt),
                "images": AnyCodable([path]),
                "stream": AnyCodable(false)
            ],
            requiresKnowledge: false
        )
        
        let result: Result<AIResult, AIError> = await withCheckedContinuation { cont in
            Task { @MainActor in
                var resumed = false
                AIManager.shared.enqueue(task, completion: { aiResult in
                    if resumed { return }
                    resumed = true
                    cont.resume(returning: aiResult.success ? .success(aiResult) : .failure(aiResult.error ?? .processingError("Errore")))
                })
            }
        }
        
        guard case .success(let aiResult) = result,
              let text = aiResult.result?.value as? String else { return nil }
        
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            if cleaned.hasPrefix("```json") { cleaned = String(cleaned.dropFirst(7)) }
            else { cleaned = String(cleaned.dropFirst(3)) }
            if let end = cleaned.range(of: "```", options: .backwards) {
                cleaned = String(cleaned[..<end.lowerBound])
            }
        }
        
        guard let data = cleaned.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8) else { return nil }
        
        struct RawResult: Codable {
            let elementiIdentificativi: [String]?
        }
        
        if let raw = try? JSONDecoder().decode(RawResult.self, from: data) {
            return raw.elementiIdentificativi
        }
        return nil
    }
    
    private func parseVerificaUbicazione(_ text: String) -> VerificaUbicazione? {
        guard let result: VerificaUbicazione = decodeJSONResult(text) else {
            print("[Perxia] ❌ Errore parsing verifica ubicazione")
            return nil
        }
        return result
    }
    
    // MARK: - Calcolo complessità
    
    func calcolaComplessitaSinistro(
        beni: [BeneAnalysis],
        giustificativi: AnalisiGiustificativi?
    ) -> ComplessitaSinistro {
        var punteggio = 0
        var fattori: [String] = []
        
        // Numero beni
        let numeroBeni = beni.count
        if numeroBeni == 1 {
            punteggio += 1
        } else if numeroBeni <= 3 {
            punteggio += 3
            fattori.append("Più beni coinvolti (\(numeroBeni))")
        } else {
            punteggio += 5
            fattori.append("Molti beni coinvolti (\(numeroBeni))")
        }
        
        // Importo totale
        let importoTotale = giustificativi?.totaleGiustificativi ?? beni.compactMap { $0.stimaEconomica?.importo }.reduce(0, +)
        if importoTotale > 5000 {
            punteggio += 2
            fattori.append("Importo elevato (€\(String(format: "%.0f", importoTotale)))")
        }
        if importoTotale > 15000 {
            punteggio += 2
            fattori.append("Importo molto elevato")
        }
        
        // Tipologie beni
        let tipologie = Set(beni.map { $0.nome })
        if tipologie.contains(where: { $0.lowercased().contains("fotovoltaico") || $0.lowercased().contains("inverter") }) {
            punteggio += 2
            fattori.append("Impianto fotovoltaico")
        }
        if tipologie.contains(where: { $0.lowercased().contains("quadro") || $0.lowercased().contains("impianto elettrico") }) {
            punteggio += 1
            fattori.append("Impianto elettrico")
        }
        
        // Compatibilità FE mista
        let esiti = Set(beni.map { $0.compatibilitaFE.esito })
        if esiti.count > 1 {
            punteggio += 2
            fattori.append("Compatibilità FE mista tra beni")
        }
        
        // Voci non FE significative
        if let giust = giustificativi, giust.totaleNonFE > giust.totaleGiustificativi * 0.2 {
            punteggio += 1
            fattori.append("Voci non FE significative")
        }
        
        // Beni non in foto
        if let giust = giustificativi, !giust.beniNonInFoto.isEmpty {
            punteggio += 2
            fattori.append("Beni in giustificativi non documentati in foto")
        }
        
        let livello: String
        if punteggio <= 3 {
            livello = "semplice"
        } else if punteggio <= 6 {
            livello = "media"
        } else {
            livello = "complessa"
        }
        
        return ComplessitaSinistro(
            livello: livello,
            punteggio: min(10, punteggio),
            fattori: fattori,
            importoTotale: importoTotale,
            numeroBeni: numeroBeni,
            tipologieBeni: Array(tipologie).sorted()
        )
    }
    
    // MARK: - Fase 1: Descrizione approfondita foto
    
    private func fase1_analizzaFotoApprofondite(
        sinistro: Sinistro,
        rootPath: String,
        streamCallback: @escaping @MainActor (String) -> Void,
        progressCallback: @escaping @MainActor (Double) -> Void
    ) async -> [PhotoDescription] {
        var descrizioni: [PhotoDescription] = []
        
        // Trova tutte le foto taggate
        let fotoTaggate = await trovaTutteLesFotoTaggate(rootPath: rootPath)
        
        // Filtra solo foto con tag di default (con bene) e ubicazione
        let fotoFiltrate = await filtraFotoPerBatch(fotoTaggate)
        let totalCount = fotoFiltrate.count
        
        if totalCount == 0 {
            await MainActor.run {
                streamCallback("⚠️ Nessuna foto taggata trovata. Eseguire prima l'autotagging.\n")
            }
            return []
        }
        
        await MainActor.run {
            streamCallback("Analizzando \(totalCount) foto taggate...\n")
        }
        
        for (index, (path, tags)) in fotoFiltrate.enumerated() {
            // Estrai bene e componente dai tag
            let bene = await estraiBeneDaTag(path: path, tags: tags)
            let componente = await estraiComponenteDaTag(path: path, tags: tags)
            
            if let desc = await analizzaFotoSingola(
                path: path,
                bene: bene,
                componente: componente,
                sinistro: sinistro
            ) {
                descrizioni.append(desc)
            }
            
            let progress = Double(index + 1) / Double(totalCount)
            await MainActor.run { progressCallback(progress) }
        }
        
        return descrizioni
    }
    
    private func analizzaFotoSingola(
        path: String,
        bene: String?,
        componente: String?,
        sinistro: Sinistro
    ) async -> PhotoDescription? {
        let prompt = buildDescrizioneFotoPrompt(path: path, bene: bene, componente: componente)
        
        let task = AITask(
            type: .documentAnalysis,
            priority: .secondary,
            preferredProvider: .localMultimodal,
            fallbackProviders: [.cloudOpenAI],
            allowFallback: true,
            parameters: [
                "prompt": AnyCodable(prompt),
                "images": AnyCodable([path]),
                "stream": AnyCodable(false)
            ],
            requiresKnowledge: false
        )
        
        let result: Result<AIResult, AIError> = await withCheckedContinuation { cont in
            Task { @MainActor in
                var resumed = false
                AIManager.shared.enqueue(task, completion: { aiResult in
                    if resumed { return }
                    resumed = true
                    if aiResult.success {
                        cont.resume(returning: .success(aiResult))
                    } else {
                        cont.resume(returning: .failure(aiResult.error ?? .processingError("Errore analisi foto")))
                    }
                })
            }
        }
        
        switch result {
        case .success(let aiResult):
            return parsePhotoDescription(aiResult, path: path, bene: bene, componente: componente)
        case .failure:
            return nil
        }
    }
    
    private func buildDescrizioneFotoPrompt(path: String, bene: String?, componente: String?) -> String {
        let fileName = URL(fileURLWithPath: path).lastPathComponent
        let beneInfo = bene != nil ? "Bene: \(bene!)" : "Bene: non specificato"
        let componenteInfo = componente != nil ? "Componente: \(componente!)" : ""
        
        return """
        Analizza questa foto in modo MOLTO DETTAGLIATO per una perizia assicurativa Fenomeno Elettrico.
        
        CONTESTO:
        - File: \(fileName)
        - \(beneInfo)
        \(componenteInfo.isEmpty ? "" : "- \(componenteInfo)")
        
        OBIETTIVO: Fornire una descrizione ACCURATA e COMPLETA di tutto ciò che è visibile nella foto.
        
        ANALIZZA E DESCRIVI:
        1. ELEMENTI VISIBILI: Elenca TUTTI gli elementi identificabili (componenti, parti, etichette, cavi, connessioni)
        2. TESTO LEGGIBILE: Trascrivi ESATTAMENTE qualsiasi testo visibile (marche, modelli, numeri di serie, etichette, targhette dati)
        3. MISURE STRUMENTALI: Se presente uno strumento di misura:
           - Tipo strumento (multimetro, megger, pinza)
           - Valore mostrato sul display
           - Impostazione selezionata
           - Posizionamento puntali (corretto/scorretto)
           - Interpretazione della misura
        4. ANOMALIE VISIVE: Descrivi OGNI anomalia (bruciature, rigonfiamenti, ossidazioni, rotture, deformazioni, carbonizzazioni)
        5. QUALITÀ FOTO: Valuta nitidezza, esposizione, inquadratura
        
        RISPONDI SOLO CON JSON VALIDO:
        {
            "descrizioneDettagliata": "descrizione completa e accurata di tutto ciò che si vede",
            "elementiVisibili": ["elemento1", "elemento2", ...],
            "testoLeggibile": "testo esatto visibile o null",
            "misureStrumentali": {
                "tipoStrumento": "tipo o null",
                "valoreRilevato": "valore con unità o null",
                "unitaMisura": "unità o null",
                "posizionamentoPuntali": "corretto/scorretto/non_valutabile",
                "impostazioniStrumento": "corrette/scorrette/non_valutabile",
                "misuraRisolutiva": true/false,
                "interpretazione": "cosa significa questa misura"
            },
            "anomalieVisive": ["anomalia1", "anomalia2", ...],
            "qualitaFoto": "buona/media/scarsa"
        }
        
        Se non ci sono misure strumentali, usa null per "misureStrumentali".
        """
    }
    
    private func parsePhotoDescription(_ aiResult: AIResult, path: String, bene: String?, componente: String?) -> PhotoDescription? {
        guard let text = aiResult.result?.value as? String else { return nil }
        
        struct RawDesc: Codable {
            let descrizioneDettagliata: String
            let elementiVisibili: [String]?
            let testoLeggibile: String?
            let misureStrumentali: MisuraStrumentale?
            let anomalieVisive: [String]?
            let qualitaFoto: String?
        }
        
        guard let raw: RawDesc = decodeJSONResult(text) else {
            print("[Perxia] ❌ Errore parsing descrizione foto per \(path)")
            return nil
        }
        
        return PhotoDescription(
            path: path,
            beneRiferimento: bene,
            componente: componente,
            descrizioneDettagliata: raw.descrizioneDettagliata,
            elementiVisibili: raw.elementiVisibili ?? [],
            testoLeggibile: raw.testoLeggibile,
            misureStrumentali: raw.misureStrumentali,
            anomalieVisive: raw.anomalieVisive ?? [],
            qualitaFoto: raw.qualitaFoto ?? "media"
        )
    }
    
    // MARK: - Fase 2: Raggruppamento per bene
    
    private func fase2_raggruppaPerBene(
        descrizioni: [PhotoDescription],
        rootPath: String
    ) -> [String: [PhotoDescription]] {
        var result: [String: [PhotoDescription]] = [:]
        
        for desc in descrizioni {
            let bene = desc.beneRiferimento ?? "Bene non identificato"
            if result[bene] == nil {
                result[bene] = []
            }
            result[bene]?.append(desc)
        }
        
        return result
    }
    
    // MARK: - Fase 3: Analisi FE per bene
    
    private func fase3_analizzaBeneFE(
        nomeBene: String,
        foto: [PhotoDescription],
        vociGiustificativo: [VoceGiustificativo],
        sinistro: Sinistro,
        fulminazione: Bool,
        sopralluogo: Bool,
        streamCallback: @escaping @MainActor (String) -> Void
    ) async -> BeneAnalysis? {
        
        // Costruisci il contesto dalle descrizioni foto
        let descrizioniJSON = foto.map { desc -> [String: Any] in
            var dict: [String: Any] = [
                "path": desc.path,
                "descrizione": desc.descrizioneDettagliata,
                "elementi": desc.elementiVisibili,
                "anomalie": desc.anomalieVisive,
                "qualita": desc.qualitaFoto
            ]
            if let testo = desc.testoLeggibile {
                dict["testoLeggibile"] = testo
            }
            if let misure = desc.misureStrumentali {
                dict["misure"] = [
                    "strumento": misure.tipoStrumento,
                    "valore": misure.valoreRilevato,
                    "puntali": misure.posizionamentoPuntali,
                    "impostazioni": misure.impostazioniStrumento,
                    "risolutiva": misure.misuraRisolutiva,
                    "interpretazione": misure.interpretazione
                ]
            }
            if let comp = desc.componente {
                dict["componente"] = comp
            }
            return dict
        }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: descrizioniJSON),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }
        
        // Costruisci JSON giustificativi per questo bene
        var giustificativiJSON = "Nessun giustificativo disponibile"
        if !vociGiustificativo.isEmpty {
            let vociDict = vociGiustificativo.map { voce -> [String: Any] in
                var dict: [String: Any] = [
                    "descrizione": voce.descrizione,
                    "importo": voce.importo,
                    "tipo": voce.tipoImporto
                ]
                if let comp = voce.componente {
                    dict["componente"] = comp
                }
                return dict
            }
            if let data = try? JSONSerialization.data(withJSONObject: vociDict),
               let str = String(data: data, encoding: .utf8) {
                giustificativiJSON = str
            }
        }
        
        let prompt = buildAnalisiBeeneFEPrompt(
            nomeBene: nomeBene,
            descrizioniJSON: jsonString,
            giustificativiJSON: giustificativiJSON,
            fulminazione: fulminazione,
            sopralluogo: sopralluogo
        )
        
        let task = AITask(
            type: .textGeneration,
            priority: .primary,
            preferredProvider: .cloudOpenAI,
            fallbackProviders: [.localText],
            allowFallback: true,
            parameters: [
                "prompt": AnyCodable(prompt),
                "stream": AnyCodable(false)
            ],
            requiresKnowledge: true,
            knowledgeDomains: [.fenomenoElettrico, .stimaDanni, .letturaSchede],
            maxKnowledgeChunks: 6
        )
        
        let result: Result<AIResult, AIError> = await withCheckedContinuation { cont in
            Task { @MainActor in
                var resumed = false
                AIManager.shared.enqueue(task, completion: { aiResult in
                    if resumed { return }
                    resumed = true
                    if aiResult.success {
                        cont.resume(returning: .success(aiResult))
                    } else {
                        cont.resume(returning: .failure(aiResult.error ?? .processingError("Errore analisi bene")))
                    }
                })
            }
        }
        
        switch result {
        case .success(let aiResult):
            return parseBeneAnalysis(aiResult, nomeBene: nomeBene, foto: foto)
        case .failure(let error):
            print("[Perxia] ❌ Errore analisi bene \(nomeBene): \(error)")
            return nil
        }
    }
    
    private func buildAnalisiBeeneFEPrompt(
        nomeBene: String,
        descrizioniJSON: String,
        giustificativiJSON: String,
        fulminazione: Bool,
        sopralluogo: Bool
    ) -> String {
        return """
        Analizza il bene "\(nomeBene)" per una perizia Fenomeno Elettrico.
        
        CONTESTO:
        - Sopralluogo effettuato: \(sopralluogo ? "SÌ" : "NO")
        - Fulminazione rilevata nella zona: \(fulminazione ? "SÌ" : "NO")
        
        DESCRIZIONI FOTO DEL BENE:
        \(descrizioniJSON)
        
        GIUSTIFICATIVI (fatture/preventivi) PER QUESTO BENE:
        \(giustificativiJSON)
        
        OBIETTIVO: Fornire un'analisi tecnica completa del bene con indicatori di confidenza.
        
        ANALIZZA:
        1. IDENTIFICAZIONE: Marca, modello, anno (da targhette, etichette, caratteristiche visive)
        2. COMPONENTI DANNEGGIATI: Lista componenti con danni visibili
        3. OSSERVAZIONI VISIVE: Descrizione tecnica dei danni (bruciature, rigonfiamenti, piste fuse, ecc.)
        4. TEST ESEGUITI: Descrizione completa dei test strumentali visibili, valori, interpretazione
        5. COMPATIBILITÀ FE: Valutazione se il danno è compatibile con Fenomeno Elettrico
        6. STIMA ECONOMICA: 
           - Se disponibili giustificativi, valuta se gli importi sono COMPATIBILI con il danno osservato
           - Se la tua stima differisce significativamente dai giustificativi, segnalalo nelle note
           - Indica se ritieni l'importo giustificato congruo, sottostimato o sovrastimato
        
        REGOLE COMPATIBILITÀ FE:
        - "compatibile": danno localizzato su componenti elettronici, protezioni (MOV/TVS) danneggiate, piste fuse, misure indicano corto/isolamento crollato
        - "poco_probabile": segni non chiari, possibili cause alternative
        - "non_compatibile": usura, ruggine diffusa, surriscaldamento prolungato, blocchi meccanici
        - "indeterminato": documentazione insufficiente, misure assenti/non interpretabili
        
        CONFIDENZE (0.0-1.0):
        - Usa valori REALISTICI basati sulla chiarezza delle evidenze
        - 0.9+: dato chiaramente leggibile/visibile
        - 0.7-0.8: dato dedotto con buona certezza
        - 0.5-0.6: dato incerto
        - <0.5: dato molto incerto o assente
        
        RISPONDI SOLO CON JSON VALIDO:
        {
            "marca": "marca identificata o null",
            "modello": "modello identificato o null",
            "anno": "anno o null",
            "annoStimato": false,
            "componentiDanneggiati": ["comp1", "comp2"],
            "osservazioniVisive": "descrizione tecnica dettagliata dei danni",
            "testEseguiti": "descrizione test: strumenti usati, valori rilevati, esiti, interpretazione",
            "compatibilitaFE": {
                "esito": "compatibile/poco_probabile/non_compatibile/indeterminato",
                "motivazione": "spiegazione tecnica dell'esito",
                "evidenzeAFavore": ["evidenza1", "evidenza2"],
                "evidenzeContrarie": ["evidenza1"]
            },
            "stimaEconomica": {
                "importo": null,
                "descrizione": "tipo di intervento necessario",
                "baseStima": "stima peritale/preventivo/listino",
                "note": "valutazione congruità importo giustificativi se disponibili"
            },
            "confidenzaMarca": 0.0,
            "confidenzaModello": 0.0,
            "confidenzaAnno": 0.0,
            "confidenzaOsservazioni": 0.8,
            "confidenzaTest": 0.7,
            "confidenzaCompatibilita": 0.75,
            "confidenzaStima": 0.5
        }
        """
    }
    
    private func parseBeneAnalysis(_ aiResult: AIResult, nomeBene: String, foto: [PhotoDescription]) -> BeneAnalysis? {
        guard let text = aiResult.result?.value as? String else { return nil }
        
        struct RawBene: Codable {
            let marca: String?
            let modello: String?
            let anno: String?
            let annoStimato: Bool?
            let componentiDanneggiati: [String]?
            let osservazioniVisive: String
            let testEseguiti: String
            let compatibilitaFE: CompatibilitaFE
            let stimaEconomica: StimaEconomica?
            let confidenzaMarca: Double?
            let confidenzaModello: Double?
            let confidenzaAnno: Double?
            let confidenzaOsservazioni: Double?
            let confidenzaTest: Double?
            let confidenzaCompatibilita: Double?
            let confidenzaStima: Double?
        }
        
        guard let raw: RawBene = decodeJSONResult(text) else {
            print("[Perxia] ❌ Errore parsing analisi bene: \(nomeBene)")
            return nil
        }
        
        return BeneAnalysis(
            nome: nomeBene,
            marca: raw.marca,
            modello: raw.modello,
            anno: raw.anno,
            annoStimato: raw.annoStimato ?? false,
            componentiDanneggiati: raw.componentiDanneggiati ?? [],
            osservazioniVisive: raw.osservazioniVisive,
            testEseguiti: raw.testEseguiti,
            compatibilitaFE: raw.compatibilitaFE,
            stimaEconomica: raw.stimaEconomica,
            fotoAssociate: foto.map { $0.path },
            confidenzaMarca: raw.confidenzaMarca ?? 0,
            confidenzaModello: raw.confidenzaModello ?? 0,
            confidenzaAnno: raw.confidenzaAnno ?? 0,
            confidenzaOsservazioni: raw.confidenzaOsservazioni ?? 0.5,
            confidenzaTest: raw.confidenzaTest ?? 0.5,
            confidenzaCompatibilita: raw.confidenzaCompatibilita ?? 0.5,
            confidenzaStima: raw.confidenzaStima ?? 0
        )
    }
    
    // MARK: - Fase 4: Generazione relazione
    
    private func fase4_generaRelazione(
        sinistro: Sinistro,
        analisi: AnalisiSinistroCompleta,
        ubicazione: String,
        streamCallback: @escaping @MainActor (String) -> Void
    ) async -> Result<String, AIError> {
        
        // Determina se indennizzo (almeno un bene compatibile)
        let haCompatibile = analisi.beni.contains { $0.compatibilitaFE.esito == "compatibile" }
        let template = selectTemplate(
            sopralluogo: analisi.sopralluogo,
            fulminazione: analisi.fulminazione,
            indennizzo: haCompatibile
        )
        
        // Costruisci JSON beni per il prompt
        let beniSummary = analisi.beni.map { bene -> [String: Any] in
            var dict: [String: Any] = [
                "nome": bene.nome,
                "osservazioni": bene.osservazioniVisive,
                "test": bene.testEseguiti,
                "compatibilita": bene.compatibilitaFE.esito,
                "motivazione": bene.compatibilitaFE.motivazione
            ]
            if let marca = bene.marca { dict["marca"] = marca }
            if let modello = bene.modello { dict["modello"] = modello }
            if let anno = bene.anno { dict["anno"] = anno }
            if let stima = bene.stimaEconomica {
                dict["stima"] = stima.descrizione
            }
            return dict
        }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: beniSummary),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return .failure(.processingError("Errore serializzazione beni"))
        }
        
        let prompt = buildRelazionePrompt(
            sinistro: sinistro,
            template: template,
            beniJSON: jsonString,
            analisi: analisi,
            ubicazione: ubicazione
        )
        
        let task = AITask(
            type: .textGeneration,
            priority: .primary,
            preferredProvider: .localText,
            fallbackProviders: [.cloudOpenAI],
            allowFallback: true,
            parameters: [
                "prompt": AnyCodable(prompt),
                "stream": AnyCodable(false)
            ],
            requiresKnowledge: false
        )
        
        let result: Result<AIResult, AIError> = await withCheckedContinuation { cont in
            Task { @MainActor in
                var resumed = false
                AIManager.shared.enqueue(task, completion: { aiResult in
                    if resumed { return }
                    resumed = true
                    if aiResult.success {
                        cont.resume(returning: .success(aiResult))
                    } else {
                        cont.resume(returning: .failure(aiResult.error ?? .processingError("Errore generazione relazione")))
                    }
                })
            }
        }
        
        switch result {
        case .success(let aiResult):
            let relazione = aiResult.result?.value as? String ?? ""
            return .success(relazione)
        case .failure(let error):
            return .failure(error)
        }
    }
    
    private func buildRelazionePrompt(
        sinistro: Sinistro,
        template: String,
        beniJSON: String,
        analisi: AnalisiSinistroCompleta,
        ubicazione: String
    ) -> String {
        // Costruisci sezioni aggiuntive se disponibili
        var denunciaInfo = "Non disponibile"
        if let denuncia = analisi.denuncia {
            denunciaInfo = """
            - Ubicazione dichiarata: \(denuncia.ubicazione.indirizzoCompleto)
            - Data sinistro: \(denuncia.dataSinistro ?? "non specificata")
            - Tipo sinistro: \(denuncia.tipoSinistro)
            - Beni dichiarati: \(denuncia.beniDichiarati.joined(separator: ", "))
            """
        }
        
        var giustificativiInfo = "Non disponibili"
        if let giust = analisi.giustificativi {
            var parts: [String] = []
            parts.append("- Totale giustificativi: €\(String(format: "%.2f", giust.totaleGiustificativi))")
            parts.append("- Totale FE compatibile: €\(String(format: "%.2f", giust.totaleFECompatibile))")
            if giust.totaleNonFE > 0 {
                parts.append("- Totale voci non FE: €\(String(format: "%.2f", giust.totaleNonFE))")
                parts.append("- Voci escluse: \(giust.vociNonFE.map { $0.descrizione }.joined(separator: ", "))")
            }
            if !giust.beniNonInFoto.isEmpty {
                parts.append("- ⚠️ Beni in giustificativi NON documentati in foto: \(giust.beniNonInFoto.joined(separator: ", "))")
            }
            giustificativiInfo = parts.joined(separator: "\n")
        }
        
        var ubicazioneVerifica = "Non verificata"
        if let verifica = analisi.verificaUbicazione {
            ubicazioneVerifica = """
            - Corrispondenza: \(verifica.corrispondenza)
            - Evidenze trovate: \(verifica.evidenzeTrovate.isEmpty ? "nessuna" : verifica.evidenzeTrovate.joined(separator: ", "))
            - Confidenza: \(String(format: "%.0f", verifica.confidenza * 100))%
            """
            if !verifica.discrepanze.isEmpty {
                ubicazioneVerifica += "\n- ⚠️ Discrepanze: \(verifica.discrepanze.joined(separator: ", "))"
            }
        }
        
        let complessitaInfo = """
        - Livello: \(analisi.complessita.livello) (punteggio \(analisi.complessita.punteggio)/10)
        - Fattori: \(analisi.complessita.fattori.isEmpty ? "nessuno" : analisi.complessita.fattori.joined(separator: ", "))
        - Numero beni: \(analisi.complessita.numeroBeni)
        - Importo totale: €\(String(format: "%.2f", analisi.complessita.importoTotale))
        """
        
        return """
        Genera la relazione tecnica finale per la perizia Fenomeno Elettrico.
        
        TEMPLATE BASE (mantieni stile e struttura):
        ---
        \(template)
        ---
        
        BENI ANALIZZATI:
        \(beniJSON)
        
        DATI SINISTRO:
        - Sopralluogo: \(analisi.sopralluogo ? "effettuato" : "non effettuato (perizia documentale)")
        - Fulminazione: \(analisi.fulminazione ? "rilevata nella zona" : "non rilevata")
        - Ubicazione dichiarata: \(ubicazione)
        
        DENUNCIA:
        \(denunciaInfo)
        
        GIUSTIFICATIVI:
        \(giustificativiInfo)
        
        VERIFICA UBICAZIONE:
        \(ubicazioneVerifica)
        
        COMPLESSITÀ SINISTRO:
        \(complessitaInfo)
        
        ISTRUZIONI:
        1. Sostituisci [ELENCO_BENI] con l'elenco discorsivo dei beni (nome, marca e anno, se disponibili)
        2. Sostituisci [OSSERVAZIONI_SINTETICHE] con un riassunto delle osservazioni principali
        3. Se TUTTI i beni sono "compatibili" o almeno uno è "compatibile" → esito FE positivo
        4. Se TUTTI i beni sono "non_compatibile" o "poco_probabile" → esito FE negativo
        5. Mantieni le frasi standard del template (es. "al netto di opere non indennizzabili")
        6. Se ci sono voci non FE nei giustificativi, menziona che sono state escluse dalla stima
        7. Se ci sono beni nei giustificativi non documentati in foto, segnalalo come criticità
        8. Se la verifica ubicazione ha discrepanze, segnalalo
        9. NON usare elenchi puntati, scrivi testo fluido e continuo
        10. NON inserire valori di misura numerici (ohm, volt) → quelli restano nel processo interno
        
        Genera SOLO il testo della relazione, senza JSON o altri formati.
        """
    }
    
    // MARK: - Helper per nuova pipeline
    
    func trovaTutteLesFotoTaggate(rootPath: String) async -> [(path: String, tags: Set<FileTagManager.FileTag>)] {
        let photoExtensions = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp"]
        
        // Usa security-scoped access per accedere ai file - raccogli solo i path
        let photoPaths = FileService.shared.performWithSecurityScopedAccess(to: rootPath) { () -> [String] in
            var paths: [String] = []
            
            let enumerator = FileManager.default.enumerator(
                at: URL(fileURLWithPath: rootPath),
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            
            while let url = enumerator?.nextObject() as? URL {
                // Salta directory "Da Chiudere"
                if url.lastPathComponent.lowercased().hasPrefix("da chiudere") {
                    enumerator?.skipDescendants()
                    continue
                }
                
                let ext = url.pathExtension.lowercased()
                guard photoExtensions.contains(ext) else { continue }
                
                paths.append(url.path)
            }
            
            return paths
        } ?? []
        
        // Ora ottieni i tag per ogni foto in modo async
        var photos: [(String, Set<FileTagManager.FileTag>)] = []
        for path in photoPaths {
            let tags = await fileTagManager.getTagsForFile(at: path)
            if !tags.isEmpty {
                photos.append((path, tags))
            }
        }
        
        print("[PerxiaService] 🔍 trovaTutteLesFotoTaggate: trovate \(photos.count) foto taggate in \(rootPath)")
        return photos
    }
    
    /// Filtra le foto per includere solo quelle con tag di default (con bene associato) e quelle di ubicazione
    private func filtraFotoPerBatch(_ fotoTaggate: [(path: String, tags: Set<FileTagManager.FileTag>)]) async -> [(path: String, tags: Set<FileTagManager.FileTag>)] {
        var fotoFiltrate: [(path: String, tags: Set<FileTagManager.FileTag>)] = []
        
        for (path, tags) in fotoTaggate {
            let tagIds = Set(tags.map { $0.id })
            
            // Escludi foto con solo tag ubicazione (non hanno beni specifici da analizzare)
            let hasUbicazioneTag = tagIds.intersection(Set(FileTagManager.FileTag.ubicazioneTags)).isEmpty == false
            let hasBeneTags = tagIds.intersection(Set(["foto_bene", "foto_componente", "foto_ripristino", "foto_test_funzionale", "test_strumentale"])).isEmpty == false
            
            // Se ha solo tag ubicazione senza tag bene, skippa
            if hasUbicazioneTag && !hasBeneTags {
                continue
            }
            
            // Include foto con tag di default che hanno un bene associato
            // Tag che richiedono bene: foto_bene, foto_componente, foto_ripristino, foto_test_funzionale, test_strumentale
            if hasBeneTags {
                // Verifica se ha un bene associato
                let bene = await estraiBeneDaTag(path: path, tags: tags)
                if let bene = bene, !bene.isEmpty {
                    fotoFiltrate.append((path, tags))
                }
            }
        }
        
        print("[PerxiaService] 🔍 filtraFotoPerBatch: \(fotoFiltrate.count)/\(fotoTaggate.count) foto filtrate")
        return fotoFiltrate
    }
    
    func estraiBeneDaTag(path: String, tags: Set<FileTagManager.FileTag>) async -> String? {
        for tag in tags {
            if FileTagManager.FileTag.beneRiferimentoTags.contains(tag.id) {
                let bene = await fileTagManager.getBeneRiferimento(forFile: path, tagId: tag.id)
                if let bene = bene, !bene.isEmpty {
                    return bene
                }
            }
            // Se è foto_bene, cerca nell'additionalText
            if tag.id == "foto_bene" {
                let text = await fileTagManager.getAdditionalText(forFile: path, tagId: tag.id)
                if let text = text, !text.isEmpty {
                    return text
                }
            }
        }
        return nil
    }
    
    func estraiComponenteDaTag(path: String, tags: Set<FileTagManager.FileTag>) async -> String? {
        for tag in tags where tag.id == "foto_componente" {
            let text = await fileTagManager.getAdditionalText(forFile: path, tagId: tag.id)
            if let text = text, !text.isEmpty {
                return text
            }
        }
        return nil
    }
    
    private func verificaPresenzaGiustificativi(rootPath: String) async -> Bool {
        let fatturaTag = FileTagManager.FileTag.availableTags.first { $0.id == "fattura" }
        let preventivoTag = FileTagManager.FileTag.availableTags.first { $0.id == "preventivo" }
        
        if let tag = fatturaTag {
            let files = await fileTagManager.getFilesWithTag(tag)
            if files.contains(where: { $0.hasPrefix(rootPath) }) { return true }
        }
        if let tag = preventivoTag {
            let files = await fileTagManager.getFilesWithTag(tag)
            if files.contains(where: { $0.hasPrefix(rootPath) }) { return true }
        }
        return false
    }
    
    private func verificaPresenzaDenuncia(rootPath: String) async -> Bool {
        let denunciaTag = FileTagManager.FileTag.availableTags.first { $0.id == "denuncia" }
        if let tag = denunciaTag {
            let files = await fileTagManager.getFilesWithTag(tag)
            return files.contains(where: { $0.hasPrefix(rootPath) })
        }
        return false
    }
    
    func salvaAnalisiCompleta(sinistro: Sinistro, analisi: AnalisiSinistroCompleta) {
        let context = PersistenceController.shared.container.viewContext
        let beniCount = analisi.beni.count
        let complessitaLivello = analisi.complessita.livello
        
        // Esegui tutte le operazioni Core Data sul main thread
        let saveBlock = {
            // Cerca o crea PerxiaAnalisi
            let fetch = NSFetchRequest<PerxiaAnalisi>(entityName: "PerxiaAnalisi")
            fetch.predicate = NSPredicate(format: "sinistro == %@", sinistro)
            fetch.sortDescriptors = [NSSortDescriptor(keyPath: \PerxiaAnalisi.dataAnalisi, ascending: false)]
            fetch.fetchLimit = 1
            
            let perxiaAnalisi: PerxiaAnalisi
            if let existing = try? context.fetch(fetch).first {
                perxiaAnalisi = existing
                // Rimuovi beni esistenti
                if let beniSet = perxiaAnalisi.beni as? Set<PerxiaBene> {
                    beniSet.forEach { context.delete($0) }
                }
            } else {
                perxiaAnalisi = PerxiaAnalisi(context: context)
                perxiaAnalisi.id = UUID()
                perxiaAnalisi.sinistro = sinistro
            }
            
            perxiaAnalisi.dataAnalisi = Date()
            
            // Salva ogni bene
            for (index, bene) in analisi.beni.enumerated() {
                let perxiaBene = PerxiaBene(context: context)
                perxiaBene.id = UUID()
                perxiaBene.tipologia = bene.nome
                if let marca = bene.marca { perxiaBene.tipologia = "\(bene.nome) \(marca)" }
                perxiaBene.modello = bene.modello
                perxiaBene.anno = bene.anno
                perxiaBene.osservazioniVisive = bene.osservazioniVisive
                perxiaBene.valutazioneTest = bene.testEseguiti
                perxiaBene.stimaEconomica = bene.stimaEconomica?.descrizione
                perxiaBene.componenti = bene.componentiDanneggiati.joined(separator: ", ")
                perxiaBene.ordine = Int16(index)
                perxiaBene.analisi = perxiaAnalisi
            }
            
            // Aggiorna sinistro con complessità
            sinistro.complessita = complessitaLivello
            
            // Aggiorna ubicazione se verificata
            if let verifica = analisi.verificaUbicazione {
                sinistro.ubicazioneValidata = verifica.corrispondenza == "confermata"
                sinistro.ubicazioneNote = verifica.note
            }
            
            // Salva giustificativi se presenti
            if analisi.giustificativi != nil {
                sinistro.giustificativi = true
            }
            
            try? context.save()
            print("[Perxia] ✅ Analisi completa salvata: \(beniCount) beni, complessità: \(complessitaLivello)")
        }
        
        if Thread.isMainThread {
            saveBlock()
        } else {
            DispatchQueue.main.sync { saveBlock() }
        }
    }
    
    // MARK: - Pubbliche: pipeline a due fasi (legacy)
    func analizzaBeniSinistro(
        sinistro: Sinistro,
        fulminazione: Bool,
        sopralluogo: Bool,
        ubicazione: String,
        propensionePerito: String,
        documenti: [URL],
        foto: [URL],
        useModello2: Bool = false,  // false = Modello 1 (Phi-4 testo), true = Modello 2 (OpenAI JSON)
        streamCallback: @escaping @MainActor (String) -> Void,
        progressCallback: @escaping @MainActor (Double) -> Void = { _ in },
        partialBeniCallback: @escaping @MainActor (PhiBeniResult) -> Void = { _ in }
    ) async -> Result<(beni: PhiBeniResult, fotoTags: [[String: Any]]?, descrizioni: [FileAnalysisResult], beniText: String?), AIError> {
        if sinistro.stato?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "chiuso" {
            print("[PerxiaService] ⏭️ Sinistro chiuso: skip analizzaBeniSinistro")
            return .failure(.processingError("Sinistro chiuso"))
        }
        
        let files = foto + documenti
        let filePaths = Set(files.map { $0.path })
        
        // Recupera descrizioni esistenti dal database
        let context = PersistenceController.shared.container.viewContext
        let existingAnalyses = caricaDescrizioniEsistenti(sinistro: sinistro, in: context)
        let existingPaths = Set(existingAnalyses.map { $0.filePath })
        
        // Identifica file nuovi da analizzare
        let newFiles = files.filter { !existingPaths.contains($0.path) }
        let existingFiles = files.filter { existingPaths.contains($0.path) }
        
        var allDescrizioni: [FileAnalysisResult] = []
        
        // Aggiungi descrizioni esistenti per file già analizzati
        for file in existingFiles {
            if let existing = existingAnalyses.first(where: { $0.filePath == file.path }) {
                var jsonString = existing.jsonAnalisi ?? ""
                
                // Rimuovi markdown code blocks se presenti
                jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
                if jsonString.hasPrefix("```") {
                    if jsonString.hasPrefix("```json") {
                        jsonString = String(jsonString.dropFirst(7))
                    } else if jsonString.hasPrefix("```") {
                        jsonString = String(jsonString.dropFirst(3))
                    }
                    if let codeEndRange = jsonString.range(of: "```", options: .backwards) {
                        jsonString = String(jsonString[..<codeEndRange.lowerBound])
                    }
                    jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                
                guard let jsonData = jsonString.data(using: .utf8) else { continue }
                
                // Prova a decodificare come singolo oggetto o come array
                if let decoded = try? JSONDecoder().decode(FileAnalysisResult.self, from: jsonData) {
                    allDescrizioni.append(decoded)
                } else if let decodedArray = try? JSONDecoder().decode([FileAnalysisResult].self, from: jsonData),
                          let first = decodedArray.first {
                    allDescrizioni.append(first)
                }
            }
        }
        
        // Analizza solo i nuovi file
        if !newFiles.isEmpty {
            print("[Perxia] 📋 File nuovi da analizzare: \(newFiles.count), file esistenti riutilizzati: \(existingFiles.count)")
            await MainActor.run {
                streamCallback("Analizzando \(newFiles.count) nuovi file...\n")
            }
            
            let cloudResult = await analizzaFileConCloud(
                sinistro: sinistro,
                files: newFiles,
                fulminazione: fulminazione,
                sopralluogo: sopralluogo,
                ubicazione: ubicazione,
                propensionePerito: propensionePerito,
                streamCallback: streamCallback,
                progressCallback: { progress in
                    // Scala il progresso per i nuovi file (0-0.7) mantenendo spazio per Phi
                    progressCallback(progress * 0.7)
                }
            )
            
            guard case .success(let newDescrizioni) = cloudResult else {
                if case .failure(let error) = cloudResult { return .failure(error) }
                return .failure(.processingError("Analisi cloud non riuscita"))
            }
            
            // Salva le nuove descrizioni nel database
            salvaDescrizioniFile(sinistro: sinistro, descrizioni: newDescrizioni, in: context)
            
            allDescrizioni.append(contentsOf: newDescrizioni)
        } else {
            print("[Perxia] ✅ Nessun file nuovo, riutilizzo \(existingFiles.count) descrizioni esistenti")
            await MainActor.run {
                streamCallback("Riutilizzando descrizioni esistenti per \(existingFiles.count) file...\n")
                progressCallback(0.7) // Salta direttamente alla fase Phi
            }
        }

        // Filtra solo immagini esplicitamente irrilevanti o scartate
        // NON filtrare per daAllegare=false perché potrebbe contenere info utili per identificare beni
        let descrizioniUtili = allDescrizioni.filter { desc in
            let tipoLower = desc.tipo.lowercased()
            // Filtra solo se esplicitamente marcato come irrilevante o scartato
            if tipoLower.contains("irrilevante") || tipoLower.contains("scarta") { return false }
            // Non filtrare per daAllegare - anche se non da allegare può contenere info utili
            return true
        }
        
        print("[Perxia] 📊 Descrizioni totali: \(allDescrizioni.count), utili per Phi: \(descrizioniUtili.count)")
        if descrizioniUtili.isEmpty && !allDescrizioni.isEmpty {
            print("[Perxia] ⚠️ ATTENZIONE: Tutte le descrizioni sono state filtrate! Usiamo tutte le descrizioni.")
        }
        
        // Usa descrizioniUtili se disponibili, altrimenti tutte le descrizioni per evitare perdita di informazioni
        let descrizioniPerPhi = descrizioniUtili.isEmpty ? allDescrizioni : descrizioniUtili
        
        // Log delle prime descrizioni per debug
        if !descrizioniPerPhi.isEmpty {
            print("[Perxia] 📝 Prime 3 descrizioni per Phi:")
            for (idx, desc) in descrizioniPerPhi.prefix(3).enumerated() {
                print("  [\(idx+1)] path: \(desc.path), tipo: \(desc.tipo), descrizione: \(String(desc.descrizione.prefix(100)))...")
            }
        }
        
        if useModello2 {
            // Modello 2: OpenAI per generare JSON strutturato
            let openAIResult = await strutturaBeniConOpenAI(
                sinistro: sinistro,
                descrizioni: descrizioniPerPhi,
                fulminazione: fulminazione,
                sopralluogo: sopralluogo,
                ubicazione: ubicazione,
                propensionePerito: propensionePerito,
                streamCallback: streamCallback,
                progressCallback: { openAIProgress in
                    if !newFiles.isEmpty {
                        progressCallback(0.7 + openAIProgress * 0.3)
                    } else {
                        progressCallback(0.7 + openAIProgress * 0.3)
                    }
                },
                partialCallback: partialBeniCallback
            )
            
            switch openAIResult {
            case .success(let beniStruct):
                await MainActor.run { progressCallback(0.99) }
                
                // Salva stato parziale dell'analisi
                salvaStatoParzialeAnalisi(sinistro: sinistro, beni: beniStruct, in: PersistenceController.shared.container.viewContext)
                
                // Invia notifica di completamento
                NotificationService.shared.sendAnalisiCompletataNotification(
                    sinistro: sinistro,
                    beniCount: beniStruct.beni.count
                )
                
                let fotoTags = allDescrizioni.compactMap { desc -> [String: Any]? in
                    guard let tag = desc.tagSuggerito else { return nil }
                    return [
                        "path": desc.path,
                        "tag": tag,
                        "commento": desc.tagCommento ?? "",
                        "bene_riferimento": desc.beneRiferimento ?? "",
                        "da_allegare_chiusura": desc.daAllegare
                    ]
                }
                
                return .success((beniStruct, fotoTags.isEmpty ? nil : fotoTags, allDescrizioni, nil))
            case .failure(let error):
                return .failure(error)
            }
        } else {
            // Modello 1: Phi-4 per testo formattato
            let phiBeni = await strutturaBeniConPhi4(
                sinistro: sinistro,
                descrizioni: descrizioniPerPhi,
                fulminazione: fulminazione,
                sopralluogo: sopralluogo,
                ubicazione: ubicazione,
                propensionePerito: propensionePerito,
                streamCallback: streamCallback,
                progressCallback: { phiProgress in
                    if !newFiles.isEmpty {
                        progressCallback(0.7 + phiProgress * 0.3)
                    } else {
                        progressCallback(0.7 + phiProgress * 0.3)
                    }
                },
                partialCallback: partialBeniCallback
            )
            switch phiBeni {
            case .success(let beniText):
                await MainActor.run { progressCallback(0.99) }
                
                // Salva il testo formattato in Core Data
                let context = PersistenceController.shared.container.viewContext
                let analisiFetch = NSFetchRequest<PerxiaAnalisi>(entityName: "PerxiaAnalisi")
                analisiFetch.predicate = NSPredicate(format: "sinistro == %@", sinistro)
                analisiFetch.sortDescriptors = [NSSortDescriptor(keyPath: \PerxiaAnalisi.dataAnalisi, ascending: false)]
                analisiFetch.fetchLimit = 1
                
                if let analisi = try? context.fetch(analisiFetch).first {
                    analisi.contextSummary = beniText
                    try? context.save()
                    print("[Perxia] ✅ Testo beni salvato in Core Data")
                } else {
                    let analisi = PerxiaAnalisi(context: context)
                    analisi.id = UUID()
                    analisi.dataAnalisi = Date()
                    analisi.sinistro = sinistro
                    analisi.contextSummary = beniText
                    try? context.save()
                    print("[Perxia] ✅ Nuova analisi creata con testo beni")
                }
                
                let fotoTags = allDescrizioni.compactMap { desc -> [String: Any]? in
                    guard let tag = desc.tagSuggerito else { return nil }
                    return [
                        "path": desc.path,
                        "tag": tag,
                        "commento": desc.tagCommento ?? "",
                        "bene_riferimento": desc.beneRiferimento ?? "",
                        "da_allegare_chiusura": desc.daAllegare
                    ]
                }
                
                let emptyBeniStruct = PhiBeniResult(
                    beni: [],
                    complessita: nil,
                    ubicazioneValidata: nil,
                    ubicazioneNote: nil
                )
                
                return .success((emptyBeniStruct, fotoTags.isEmpty ? nil : fotoTags, allDescrizioni, beniText))
            case .failure(let error):
                return .failure(error)
            }
        }
    }

    /// Analisi di dettaglio danni/misure con RAG su subset file (dettagli, schede, misure)
    func analizzaDanniEMisure(
        sinistro: Sinistro,
        beniBase: PhiBeniResult,
        descrizioni: [FileAnalysisResult],
        fulminazione: Bool,
        sopralluogo: Bool,
        ubicazione: String,
        propensionePerito: String,
        useModello2: Bool = false,  // Se true, usa OpenAI invece di Phi-4
        streamCallback: @escaping @MainActor (String) -> Void,
        progressCallback: @escaping @MainActor (Double) -> Void = { _ in }
    ) async -> Result<PhiBeniResult, AIError> {
        if sinistro.stato?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "chiuso" {
            print("[PerxiaService] ⏭️ Sinistro chiuso: skip analizzaDanniEMisure")
            return .failure(.processingError("Sinistro chiuso"))
        }
        
        if useModello2 {
            // Modello 2: Usa OpenAI per analisi danni/misure
            return await analizzaDanniEMisureConOpenAI(
                sinistro: sinistro,
                beniBase: beniBase,
                descrizioni: descrizioni,
                fulminazione: fulminazione,
                sopralluogo: sopralluogo,
                ubicazione: ubicazione,
                propensionePerito: propensionePerito,
                streamCallback: streamCallback,
                progressCallback: progressCallback
            )
        } else {
            // Modello 1: Usa Phi-4 per analisi danni/misure
            return await analizzaDanniEMisureConPhi4(
                sinistro: sinistro,
                beniBase: beniBase,
                descrizioni: descrizioni,
                fulminazione: fulminazione,
                sopralluogo: sopralluogo,
                ubicazione: ubicazione,
                propensionePerito: propensionePerito,
                streamCallback: streamCallback,
                progressCallback: progressCallback
            )
        }
    }
    
    /// Analisi danni/misure con Phi-4 (Modello 1)
    private func analizzaDanniEMisureConPhi4(
        sinistro: Sinistro,
        beniBase: PhiBeniResult,
        descrizioni: [FileAnalysisResult],
        fulminazione: Bool,
        sopralluogo: Bool,
        ubicazione: String,
        propensionePerito: String,
        streamCallback: @escaping @MainActor (String) -> Void,
        progressCallback: @escaping @MainActor (Double) -> Void
    ) async -> Result<PhiBeniResult, AIError> {
        // filtra solo foto utili a danno/misure
        let interessanti = descrizioni.filter { desc in
            let tipo = desc.tipo.lowercased()
            return tipo.contains("danno") || tipo.contains("componente") || tipo.contains("strumento") || (desc.misure != nil) || (desc.anomalieVisive != nil)
        }
        let chunks = stride(from: 0, to: interessanti.count, by: 10).map { idx in
            Array(interessanti[idx..<min(idx + 10, interessanti.count)])
        }
        var currentResult = beniBase
        
        for (idx, chunk) in chunks.enumerated() {
            let progressBase = Double(idx) / Double(max(1, chunks.count))
            await MainActor.run { progressCallback(0.1 + progressBase * 0.8) }
            
            guard let jsonDescrizioni = try? JSONEncoder().encode(chunk),
                  let jsonString = String(data: jsonDescrizioni, encoding: .utf8),
                  let jsonBeni = try? JSONEncoder().encode(currentResult),
                  let jsonBeniString = String(data: jsonBeni, encoding: .utf8) else {
                return .failure(.processingError("Serializzazione input danni/misure"))
            }
            
            let prompt = buildPhiDanniPrompt(
                sinistro: sinistro,
                beniJSON: jsonBeniString,
                descrizioniJSON: jsonString,
                fulminazione: fulminazione,
                sopralluogo: sopralluogo,
                ubicazione: ubicazione,
                propensionePerito: propensionePerito
            )
            
            let task = AITask(
                type: .textGeneration,
                priority: .primary,
                preferredProvider: .localText,
                fallbackProviders: [.cloudOpenAI],  // Fallback su cloud se locale non disponibile
                allowFallback: true,
                personality: .sparky,
                parameters: [
                    "prompt": AnyCodable(prompt),
                    "stream": AnyCodable(true)
                ],
                requiresKnowledge: true,
                knowledgeDomains: [.fenomenoElettrico, .stimaDanni, .letturaSchede, .generico],
                maxKnowledgeChunks: 6
            )
            
            var buffer = ""
            let result: Result<AIResult, AIError> = await withCheckedContinuation { cont in
                Task { @MainActor in
                    var resumed = false
                    AIManager.shared.enqueue(
                        task,
                        completion: { aiResult in
                            if resumed { return }
                            resumed = true
                            if aiResult.success {
                                // Log se è stato usato un fallback
                                if aiResult.usedFallback {
                                    print("[Perxia] ⚠️ Danni analisi: usato fallback \(aiResult.provider.displayName) invece di localText")
                                }
                                cont.resume(returning: .success(aiResult))
                            } else {
                                cont.resume(returning: .failure(aiResult.error ?? .processingError("Errore sconosciuto Phi-4 danni")))
                            }
                        },
                        streamCallback: { chunk in
                            Task { @MainActor in
                                buffer += chunk
                                streamCallback(chunk)
                            }
                        }
                    )
                }
            }
            
            switch result {
            case .success(let aiResult):
                let text = (aiResult.result?.value as? String) ?? buffer
                if let decoded: PhiBeniResult = decodeJSONResult(text) {
                    currentResult = decoded
                } else {
                    return .failure(.processingError("Output danni non valido (provider: \(aiResult.provider.displayName))"))
                }
            case .failure(let error):
                return .failure(error)
            }
        }
        
        await MainActor.run { progressCallback(1.0) }
        return .success(currentResult)
    }
    
    /// Analisi danni/misure con OpenAI (Modello 2)
    private func analizzaDanniEMisureConOpenAI(
        sinistro: Sinistro,
        beniBase: PhiBeniResult,
        descrizioni: [FileAnalysisResult],
        fulminazione: Bool,
        sopralluogo: Bool,
        ubicazione: String,
        propensionePerito: String,
        streamCallback: @escaping @MainActor (String) -> Void,
        progressCallback: @escaping @MainActor (Double) -> Void
    ) async -> Result<PhiBeniResult, AIError> {
        // filtra solo foto utili a danno/misure
        let interessanti = descrizioni.filter { desc in
            let tipo = desc.tipo.lowercased()
            return tipo.contains("danno") || tipo.contains("componente") || tipo.contains("strumento") || (desc.misure != nil) || (desc.anomalieVisive != nil)
        }
        
        guard let jsonDescrizioni = try? JSONEncoder().encode(interessanti),
              let jsonString = String(data: jsonDescrizioni, encoding: .utf8),
              let jsonBeni = try? JSONEncoder().encode(beniBase),
              let jsonBeniString = String(data: jsonBeni, encoding: .utf8) else {
            return .failure(.processingError("Serializzazione input danni/misure"))
        }
        
        await MainActor.run { progressCallback(0.3) }
        
        let prompt = buildOpenAIDanniPrompt(
            sinistro: sinistro,
            beniJSON: jsonBeniString,
            descrizioniJSON: jsonString,
            fulminazione: fulminazione,
            sopralluogo: sopralluogo,
            ubicazione: ubicazione,
            propensionePerito: propensionePerito
        )
        
        let task = AITask(
            type: .textGeneration,
            priority: .primary,
            preferredProvider: .cloudOpenAI,
            fallbackProviders: [.localText],  // Fallback su locale se cloud non disponibile
            allowFallback: true,
            personality: nil,
            parameters: [
                "prompt": AnyCodable(prompt),
                "stream": AnyCodable(true)
            ],
            requiresKnowledge: true,
            knowledgeDomains: [.fenomenoElettrico, .stimaDanni, .letturaSchede, .generico],
            maxKnowledgeChunks: 6
        )
        
        var buffer = ""
        let result: Result<AIResult, AIError> = await withCheckedContinuation { cont in
            Task { @MainActor in
                var resumed = false
                AIManager.shared.enqueue(
                    task,
                    completion: { aiResult in
                        if resumed { return }
                        resumed = true
                        if aiResult.success {
                            // Log se è stato usato un fallback
                            if aiResult.usedFallback {
                                print("[Perxia] ⚠️ OpenAI danni: usato fallback \(aiResult.provider.displayName)")
                            }
                            cont.resume(returning: .success(aiResult))
                        } else {
                            cont.resume(returning: .failure(aiResult.error ?? .processingError("Errore sconosciuto OpenAI danni")))
                        }
                    },
                    streamCallback: { chunk in
                        Task { @MainActor in
                            buffer += chunk
                            streamCallback(chunk)
                            let est = min(0.95, 0.3 + min(0.65, Double(buffer.count) / 5000.0 * 0.65))
                            progressCallback(est)
                        }
                    }
                )
            }
        }
        
        switch result {
        case .success(let aiResult):
            let text = (aiResult.result?.value as? String) ?? buffer
            print("[Perxia] ✅ Danni OK len=\(text.count) (provider: \(aiResult.provider.displayName), fallback: \(aiResult.usedFallback))")
            
            if let decoded: PhiBeniResult = decodeJSONResult(text) {
                await MainActor.run { progressCallback(1.0) }
                return .success(decoded)
            } else {
                print("[Perxia] ❌ Impossibile decodificare JSON danni. Testo completo:")
                print(text)
                return .failure(.processingError("Output danni non valido (provider: \(aiResult.provider.displayName))"))
            }
        case .failure(let error):
            return .failure(error)
        }
    }
    
    /// Prompt per OpenAI (Modello 2) per analisi danni/misure
    private func buildOpenAIDanniPrompt(
        sinistro: Sinistro,
        beniJSON: String,
        descrizioniJSON: String,
        fulminazione: Bool,
        sopralluogo: Bool,
        ubicazione: String,
        propensionePerito: String
    ) -> String {
        return """
        Sei un modello tecnico specializzato in Fenomeno Elettrico.
        Analizza i danni, le misure e la compatibilità con FE per ciascun bene già identificato.

        NON creare nuovi beni, ma aggiorna quelli esistenti con:
        - osservazioni: descrizione tecnica sintetica dei danni elettrici visibili (bruciature, rigonfiamenti, ossidazioni, manomissioni, ecc.)
        - test: DETTAGLIO COMPLETO: quali test sono stati eseguiti, strumenti usati, valori misurati, esiti ottenuti, se eseguiti correttamente (es. "Resistenze avvolgimenti misurate con multimetro digitale: fase-neutro 12.5Ω, fase-terra 8.2Ω (asimmetriche, anomalia). Isolamento crollato su avvolgimento principale (0.1MΩ vs valore atteso >100MΩ). Test eseguiti correttamente con puntali ben posizionati.")
        - compatibilitaDanno: "compatibile" | "poco_probabile" | "non_compatibile" | "indeterminato" (SOLO questo, NON compatibilitaGaranzia)
        - stima: solo se ricavabile in modo sensato (es. "sostituzione scheda elettronica standard")
        - note: ubicazione interna del bene (es. "sul tetto", "in garage") - solo per uso interno
        - fotoOsservazioni: array di path delle foto che mostrano i danni/osservazioni
        - fotoTest: array di path delle foto che mostrano i test strumentali
        - fotoComponenti: array di path delle foto che mostrano i componenti
        - certezzaOsservazioni, certezzaTest, certezzaCompatibilita, certezzaStima: valori 0.0-1.0 REALISTICI (NON sempre 0.5!)

        REGOLE:
        1. NON modificare nome, marca, modello, anno dei beni esistenti
        2. NON inventare misure, guasti, componenti
        3. Se una misura non è chiaramente leggibile → segnala come "non_valida" o "non_risolutiva"
        4. La compatibilità FE deve basarsi SOLO su anomalie visive e misure
        5. Se mancano elementi TECNICI sufficienti → compatibilitaDanno = "indeterminato"

        Restituisci SOLO JSON con la stessa struttura dei beni in input, aggiornando solo i campi sopra indicati.

        BENI BASE:
        \(beniJSON)

        DESCRIZIONI TECNICHE:
        \(descrizioniJSON)

        FULMINAZIONE: \(fulminazione ? "true" : "false")
        """
    }
    
    func generaRelazioneDaBeni(
        sinistro: Sinistro,
        beni: PhiBeniResult,
        fulminazione: Bool,
        sopralluogo: Bool,
        ubicazione: String,
        propensionePerito: String,
        streamCallback: @escaping @MainActor (String) -> Void
    ) async -> Result<String, AIError> {
        if sinistro.stato?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "chiuso" {
            print("[PerxiaService] ⏭️ Sinistro chiuso: skip generaRelazioneDaBeni")
            return .failure(.processingError("Sinistro chiuso"))
        }
        
        return await generaRelazioneConPhi4(
            sinistro: sinistro,
            beni: beni,
            fulminazione: fulminazione,
            sopralluogo: sopralluogo,
            ubicazione: ubicazione,
            propensionePerito: propensionePerito,
            streamCallback: streamCallback
        )
    }
    
    private func aggiornaComplessita(sinistro: Sinistro, complessita: String?) {
        guard let complessita = complessita else { return }
        let context = PersistenceController.shared.container.viewContext
        sinistro.complessita = complessita
        try? context.save()
    }
    
    private func valutaAmbiguitaEDescrizioni(
        sinistro: Sinistro,
        descrizioni: [FileAnalysisResult],
        beni: PhiBeniResult
    ) {
        var shouldAlert = false
        // poche foto o nessuna
        if descrizioni.isEmpty {
            shouldAlert = true
        }
        // beni non compatibili o manomissione
        let hasNonFE = beni.beni.contains { bene in
            (bene.compatibilitaDanno == "non_compatibile" || bene.compatibilitaDanno == "poco_probabile") ||
            (bene.note?.localizedCaseInsensitiveContains("manomissione") == true)
        }
        if hasNonFE { shouldAlert = true }
        
        // Se ambigui, crea task
        if shouldAlert, let riferimento = sinistro.riferimento {
            Task { @MainActor in
                TaskManager.shared.createAITriageTask(
                    sinistro: sinistro,
                    title: "Verifica sinistro \(riferimento)",
                    description: "Risultati ambigui/insufficienti: verificare residui, considerare sopralluogo o gestione negativa.",
                    priority: 0.8
                )
            }
        }
    }
    
    /// Analizza un sinistro con l'IA
    func analizzaSinistro(
        sinistro: Sinistro,
        fulminazione: Bool,
        sopralluogo: Bool,
        ubicazione: String,
        propensionePerito: String,
        documenti: [URL],
        foto: [URL],
        systemPrompt: String,
        streamCallback: @escaping @MainActor (String) -> Void,
        beneCallback: @escaping @MainActor (PerxiaHTMLParser.ParsedBene) -> Void,
        relazioneCallback: @escaping @MainActor (String) -> Void
    ) async -> Result<(beni: [PerxiaHTMLParser.ParsedBene], relazione: String?, fotoTags: [[String: Any]]?), AIError> {
        if sinistro.stato?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "chiuso" {
            print("[PerxiaService] ⏭️ Sinistro chiuso: skip analizzaSinistro (legacy)")
            return .failure(.processingError("Sinistro chiuso"))
        }
        
        // Reset parser legacy
        self.htmlParser.reset()
        
        // 1) Analisi file con OpenAI cloud -> JSON descrittivi
        let files = foto + documenti
        let cloudResult = await analizzaFileConCloud(
            sinistro: sinistro,
            files: files,
            fulminazione: fulminazione,
            sopralluogo: sopralluogo,
            ubicazione: ubicazione,
            propensionePerito: propensionePerito,
            streamCallback: streamCallback,
            progressCallback: { _ in }
        )
        guard case .success(let descrizioni) = cloudResult else {
            if case .failure(let error) = cloudResult {
                return .failure(error)
            }
            return .failure(.processingError("Analisi cloud non riuscita"))
        }
        
        // 2) Strutturazione beni e relazione con Phi-4 locale
        let phiBeni = await strutturaBeniConPhi4(
            sinistro: sinistro,
            descrizioni: descrizioni,
            fulminazione: fulminazione,
            sopralluogo: sopralluogo,
            ubicazione: ubicazione,
            propensionePerito: propensionePerito,
            streamCallback: streamCallback,
            progressCallback: { _ in },
            partialCallback: { _ in }
        )
        guard case .success(let beniText) = phiBeni else {
            if case .failure(let error) = phiBeni {
                return .failure(error)
            }
            return .failure(.processingError("Strutturazione beni non riuscita"))
        }
        
        // Per ora non generiamo la relazione, solo restituiamo il testo formattato
        // Crea un PhiBeniResult vuoto per compatibilità
        let emptyBeniStruct = PhiBeniResult(
            beni: [],
            complessita: nil,
            ubicazioneValidata: nil,
            ubicazioneNote: nil
        )
        
        // Foto tags: mappiamo suggerimenti se presenti
        let fotoTags = descrizioni.compactMap { desc -> [String: Any]? in
            guard let tag = desc.tagSuggerito else { return nil }
            return [
                "path": desc.path,
                "tag": tag,
                "commento": desc.tagCommento ?? "",
                "bene_riferimento": desc.beneRiferimento ?? "",
                "da_allegare_chiusura": desc.daAllegare
            ]
        }
        
        // Restituisci beni vuoti e relazione vuota per ora
        await MainActor.run { relazioneCallback("") }
        
        return .success(([], nil, fotoTags.isEmpty ? nil : fotoTags))
    }
    
    private func shouldAutoAnalyze(sinistro: Sinistro) -> Bool {
        if let stato = sinistro.stato?.lowercased(), stato.contains("attesa") {
            return false
        }
        guard let rif = sinistro.riferimento,
              let path = FileService.shared.getSinistroPath(riferimento: rif),
              !path.isEmpty else {
            return false
        }
        if let stato = sinistro.stato?.lowercased() {
            if stato.contains("perizia") || stato.contains("gestione") || stato.contains("gestire") {
                return true
            }
        }
        return false
    }
    
    /// Chat successiva mantenendo il context
    func chatSinistro(
        sinistro: Sinistro,
        analisi: PerxiaAnalisi,
        domanda: String,
        chatHistory: [(role: String, content: String)],
        streamCallback: @escaping @MainActor (String) -> Void
    ) async -> Result<String, AIError> {
        if sinistro.stato?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "chiuso" {
            print("[PerxiaService] ⏭️ Sinistro chiuso: skip chatSinistro")
            return .failure(.processingError("Sinistro chiuso"))
        }
        
        // Costruisci prompt con context summary e history
        var promptParts: [String] = []
        
        // Context summary
        if let summary = analisi.contextSummary {
            promptParts.append("Context dell'analisi precedente:\n\(summary)")
        }
        
        // Chat history
        for (role, content) in chatHistory {
            promptParts.append("\(role == "user" ? "Utente" : "Assistente"): \(content)")
        }
        
        // Nuova domanda
        promptParts.append("Utente: \(domanda)")
        promptParts.append("Assistente:")
        
        let prompt = promptParts.joined(separator: "\n\n")
        
        // Crea task con fallback
        let task = AITask(
            type: .chat,
            priority: .primary,
            preferredProvider: .cloudOpenAI,
            fallbackProviders: [.localText, .localMultimodal],
            allowFallback: true,
            personality: nil,
            parameters: [
                "prompt": AnyCodable(prompt),
                "stream": AnyCodable(true)
            ],
            requiresKnowledge: true,
            knowledgeDomains: [.fenomenoElettrico, .stimaDanni, .generico],
            maxKnowledgeChunks: 8
        )
        
        var fullResponse = ""
        
        let result = await cloudAIService.callOpenAIStreaming(
            prompt: prompt,
            task: task,
            systemPrompt: analisi.systemPrompt,
            streamCallback: { chunk in
                Task { @MainActor in
                    fullResponse += chunk
                    streamCallback(chunk)
                }
            }
        )
        
        switch result {
        case .success:
            return .success(fullResponse)
        case .failure(let error):
            return .failure(error)
        }
    }
    
    /// Salva analisi in Core Data
    func salvaAnalisi(
        sinistro: Sinistro,
        beni: [PerxiaHTMLParser.ParsedBene],
        relazione: String?,
        systemPrompt: String,
        contextSummary: String?,
        in context: NSManagedObjectContext
    ) throws -> PerxiaAnalisi {
        let analisi = PerxiaAnalisi(context: context)
        analisi.id = UUID()
        analisi.dataAnalisi = Date()
        analisi.relazioneComplessiva = relazione
        analisi.systemPrompt = systemPrompt
        analisi.contextSummary = contextSummary
        analisi.sinistro = sinistro
        
        // Salva beni
        for (index, bene) in beni.enumerated() {
            let perxiaBene = PerxiaBene(context: context)
            perxiaBene.id = UUID()
            perxiaBene.tipologia = bene.tipologia
            perxiaBene.componenti = bene.componenti
            perxiaBene.modello = bene.modello
            perxiaBene.anno = bene.anno
            perxiaBene.osservazioniVisive = bene.osservazioniVisive
            perxiaBene.valutazioneTest = bene.valutazioneTest
            // compatibilitaGaranzia rimosso - non più utilizzato
            perxiaBene.stimaEconomica = bene.stimaEconomica
            perxiaBene.noteAggiuntive = bene.noteAggiuntive
            perxiaBene.ordine = Int16(index)
            perxiaBene.analisi = analisi
        }
        
        try context.save()
        return analisi
    }
    
    /// Applica tag automatici alle foto con bene, componente e flag da allegare
    /// NOTA: Questo metodo viene usato dai risultati dell'analisi beni (analizzaBeniSinistro).
    /// Per l'autotagging delle foto non analizzate, usare AutoTaggingService.
    func applicaTagFoto(_ fotoTags: [[String: Any]]) async {
        for fotoTag in fotoTags {
            guard let path = fotoTag["path"] as? String,
                  let tagId = fotoTag["tag"] as? String else {
                continue
            }
            
            // Verifica se l'utente ha rimosso manualmente questo tag
            let wasRemoved = await fileTagManager.wasTagManuallyRemoved(tagId: tagId, fromFile: path)
            if wasRemoved {
                print("[Perxia] ⏭️ Tag '\(tagId)' rimosso manualmente, skip")
                continue
            }
            
            let daAllegare = fotoTag["da_allegare_chiusura"] as? Bool ?? false
            let componente = fotoTag["commento"] as? String  // additionalText per il componente
            let bene = fotoTag["bene_riferimento"] as? String  // beneRiferimento per il bene
            
            if let tag = FileTagManager.FileTag.availableTags.first(where: { $0.id == tagId }) {
                // Applica il tag con il componente (additionalText)
                await fileTagManager.addTag(tag, toFile: path, additionalText: componente, daAllegareInChiusura: daAllegare)
                
                // Se il tag supporta beneRiferimento e abbiamo un bene, lo impostiamo
                if FileTagManager.FileTag.beneRiferimentoTags.contains(tagId), let bene = bene, !bene.isEmpty {
                    await fileTagManager.setBeneRiferimento(bene, forFile: path, tagId: tagId)
                    
                    // Aggiungi il bene alla lista dei beni comuni per suggerimenti futuri
                    CommonItemsManager.shared.addCustomBene(bene)
                }
                
                // Se abbiamo un componente, aggiungilo alla lista dei componenti comuni
                if let componente = componente, !componente.isEmpty {
                    CommonItemsManager.shared.addCustomComponente(componente)
                }
            }
        }
    }
    
    /// Salva stato parziale dell'analisi per permettere il ripristino
    func salvaStatoParzialeAnalisi(sinistro: Sinistro, beni: PhiBeniResult, in context: NSManagedObjectContext) {
        // Cerca analisi esistente o creane una nuova
        let fetchRequest = NSFetchRequest<PerxiaAnalisi>(entityName: "PerxiaAnalisi")
        fetchRequest.predicate = NSPredicate(format: "sinistro == %@", sinistro)
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \PerxiaAnalisi.dataAnalisi, ascending: false)]
        fetchRequest.fetchLimit = 1
        
        let analisi: PerxiaAnalisi
        if let existing = try? context.fetch(fetchRequest).first {
            analisi = existing
            // Rimuovi beni esistenti
            if let beniSet = analisi.beni as? Set<PerxiaBene> {
                beniSet.forEach { context.delete($0) }
            }
        } else {
            analisi = PerxiaAnalisi(context: context)
            analisi.id = UUID()
            analisi.dataAnalisi = Date()
            analisi.sinistro = sinistro
        }
        
        // Salva beni parziali
        for (index, bene) in beni.beni.enumerated() {
            let perxiaBene = PerxiaBene(context: context)
            perxiaBene.id = UUID()
            perxiaBene.tipologia = bene.nome
            perxiaBene.componenti = bene.componenti?.joined(separator: ", ")
            perxiaBene.modello = bene.modello
            perxiaBene.anno = bene.anno ?? bene.annoStimato
            perxiaBene.osservazioniVisive = bene.osservazioni
            perxiaBene.valutazioneTest = bene.test
            // compatibilitaGaranzia rimosso - non più utilizzato
            perxiaBene.stimaEconomica = bene.stima
            perxiaBene.noteAggiuntive = bene.note
            perxiaBene.ordine = Int16(index)
            perxiaBene.analisi = analisi
        }
        
        // Salva complessità e ubicazione
        sinistro.complessita = beni.complessita
        if let ubicazioneValidata = beni.ubicazioneValidata {
            sinistro.ubicazioneValidata = ubicazioneValidata
        }
        sinistro.ubicazioneNote = beni.ubicazioneNote
        
        try? context.save()
    }
    
    /// Carica stato parziale dell'analisi se esiste
    func caricaStatoParzialeAnalisi(sinistro: Sinistro, in context: NSManagedObjectContext) -> PhiBeniResult? {
        let fetchRequest = NSFetchRequest<PerxiaAnalisi>(entityName: "PerxiaAnalisi")
        fetchRequest.predicate = NSPredicate(format: "sinistro == %@", sinistro)
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \PerxiaAnalisi.dataAnalisi, ascending: false)]
        fetchRequest.fetchLimit = 1
        
        guard let analisi = try? context.fetch(fetchRequest).first,
              let beniSet = analisi.beni as? Set<PerxiaBene>,
              !beniSet.isEmpty else {
            return nil
        }
        
        let beniArray = beniSet.sorted { $0.ordine < $1.ordine }
        let beni = beniArray.map { bene -> PhiBeniResult.Bene in
            PhiBeniResult.Bene(
                nome: bene.tipologia ?? "",
                tipoBene: nil,
                marca: nil,
                componenti: bene.componenti?.components(separatedBy: ", "),
                modello: bene.modello,
                anno: bene.anno,
                annoStimato: nil,
                osservazioni: bene.osservazioniVisive,
                test: bene.valutazioneTest,
                compatibilitaDanno: nil,
                stima: bene.stimaEconomica,
                note: bene.noteAggiuntive,
                certezzaNome: nil,
                certezzaModello: nil,
                certezzaAnno: nil,
                certezzaOsservazioni: nil,
                certezzaTest: nil,
                certezzaCompatibilita: nil,
                certezzaStima: nil,
                foto: nil,
                fonti: nil,
                fotoOsservazioni: nil,
                fotoTest: nil,
                fotoComponenti: nil,
                componentiDettaglio: nil
            )
        }
        
        return PhiBeniResult(
            beni: beni,
            complessita: sinistro.complessita,
            ubicazioneValidata: sinistro.ubicazioneValidata ? true : nil,
            ubicazioneNote: sinistro.ubicazioneNote
        )
    }
    
    /// Carica descrizioni esistenti dei file dal database
    private func caricaDescrizioniEsistenti(sinistro: Sinistro, in context: NSManagedObjectContext) -> [PerxiaFileAnalysis] {
        let fetchRequest = NSFetchRequest<PerxiaFileAnalysis>(entityName: "PerxiaFileAnalysis")
        // Cerca descrizioni associate a qualsiasi analisi del sinistro
        let analisiFetch = NSFetchRequest<PerxiaAnalisi>(entityName: "PerxiaAnalisi")
        analisiFetch.predicate = NSPredicate(format: "sinistro == %@", sinistro)
        guard let analisiSet = try? context.fetch(analisiFetch) else { return [] }
        
        var allAnalyses: [PerxiaFileAnalysis] = []
        for analisi in analisiSet {
            let fileFetch = NSFetchRequest<PerxiaFileAnalysis>(entityName: "PerxiaFileAnalysis")
            fileFetch.predicate = NSPredicate(format: "analisi == %@", analisi)
            if let fileAnalyses = try? context.fetch(fileFetch) {
                allAnalyses.append(contentsOf: fileAnalyses)
            }
        }
        
        // Rimuovi duplicati per filePath (mantieni il più recente)
        let unique = Dictionary(grouping: allAnalyses, by: { $0.filePath })
            .compactMapValues { analyses in
                analyses.max(by: { ($0.analisi?.dataAnalisi ?? Date.distantPast) < ($1.analisi?.dataAnalisi ?? Date.distantPast) })
            }
        
        return Array(unique.values)
    }
    
    /// Salva descrizioni dei file nel database
    private func salvaDescrizioniFile(sinistro: Sinistro, descrizioni: [FileAnalysisResult], in context: NSManagedObjectContext) {
        // Cerca o crea analisi corrente
        let analisiFetch = NSFetchRequest<PerxiaAnalisi>(entityName: "PerxiaAnalisi")
        analisiFetch.predicate = NSPredicate(format: "sinistro == %@", sinistro)
        analisiFetch.sortDescriptors = [NSSortDescriptor(keyPath: \PerxiaAnalisi.dataAnalisi, ascending: false)]
        analisiFetch.fetchLimit = 1
        
        let analisi: PerxiaAnalisi
        if let existing = try? context.fetch(analisiFetch).first {
            analisi = existing
        } else {
            analisi = PerxiaAnalisi(context: context)
            analisi.id = UUID()
            analisi.dataAnalisi = Date()
            analisi.sinistro = sinistro
        }
        
        // Salva ogni descrizione
        for desc in descrizioni {
            // Verifica se esiste già una descrizione per questo file
            let fileFetch = NSFetchRequest<PerxiaFileAnalysis>(entityName: "PerxiaFileAnalysis")
            fileFetch.predicate = NSPredicate(format: "filePath == %@ AND analisi == %@", desc.path, analisi)
            fileFetch.fetchLimit = 1
            
            let fileAnalysis: PerxiaFileAnalysis
            if let existing = try? context.fetch(fileFetch).first {
                fileAnalysis = existing
            } else {
                fileAnalysis = PerxiaFileAnalysis(context: context)
                fileAnalysis.id = UUID()
                fileAnalysis.filePath = desc.path
                fileAnalysis.analisi = analisi
            }
            
            // Serializza la descrizione in JSON
            if let jsonData = try? JSONEncoder().encode(desc),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                fileAnalysis.jsonAnalisi = jsonString
            }
            
            fileAnalysis.tagSuggerito = desc.tagSuggerito
            fileAnalysis.daAllegare = desc.daAllegare
        }
        
        try? context.save()
    }
    
    // MARK: - Private
    
    private func analizzaFileConCloud(
        sinistro: Sinistro,
        files: [URL],
        fulminazione: Bool,
        sopralluogo: Bool,
        ubicazione: String,
        propensionePerito: String,
        streamCallback: @escaping @MainActor (String) -> Void,
        progressCallback: @escaping @MainActor (Double) -> Void
    ) async -> Result<[FileAnalysisResult], AIError> {
        var results: [FileAnalysisResult] = []
        let batchSize = 8
        let batches = stride(from: 0, to: files.count, by: batchSize).map { idx in
            Array(files[idx..<min(idx + batchSize, files.count)])
        }
        let totalCount = max(1, files.count)
        var processed = 0
        
        for (batchIndex, batch) in batches.enumerated() {
            print("[Perxia] 🔄 Cloud batch \(batchIndex+1)/\(batches.count) (\(batch.count) file)")
            for file in batch {
                let isImage = ["jpg","jpeg","png","gif","webp","heic","heif"].contains(file.pathExtension.lowercased())
                print("[Perxia] 🔍 Analisi cloud file: \(file.lastPathComponent) isImage=\(isImage)")
                let prompt = buildCloudPrompt(
                    sinistro: sinistro,
                    file: file,
                    isImage: isImage,
                    fulminazione: fulminazione,
                    sopralluogo: sopralluogo,
                    ubicazione: ubicazione,
                    propensionePerito: propensionePerito
                )
                
                var parameters: [String: AnyCodable] = [
                    "prompt": AnyCodable(prompt),
                    "stream": AnyCodable(true)
                ]
                if isImage {
                    parameters["images"] = AnyCodable([file.path])
                }
                
                let task = AITask(
                    type: .chat,
                    priority: .primary,
                    preferredProvider: .cloudOpenAI,
                    fallbackProviders: isImage ? [.localMultimodal] : [.localText],  // Fallback su modelli locali
                    allowFallback: true,
                    personality: nil,
                    parameters: parameters,
                    requiresKnowledge: true,
                    knowledgeDomains: [.fenomenoElettrico, .generico],
                    maxKnowledgeChunks: 6
                )
                
                var buffer = ""
                let call = await cloudAIService.callOpenAIStreaming(
                    prompt: prompt,
                    task: task,
                    systemPrompt: systemPromptCloud(),
                    streamCallback: { chunk in
                        Task { @MainActor in
                            buffer += chunk
                            streamCallback(chunk)
                        }
                    }
                )
                
                switch call {
                case .success(let full):
                    print("[Perxia] ✅ Cloud OK \(file.lastPathComponent) len=\(full.count)")
                    if let data = full.data(using: String.Encoding.utf8),
                       let decoded = try? JSONDecoder().decode([FileAnalysisResult].self, from: data) {
                        results.append(contentsOf: decoded)
                    } else {
                        let fallback = FileAnalysisResult(
                            path: file.path,
                            tipo: isImage ? "immagine" : "documento",
                            descrizione: full,
                            contesto: nil,
                            misure: nil,
                            validitaMisura: nil,
                            anomalieVisive: nil,
                            tagSuggerito: nil,
                            tagCommento: nil,
                            beneRiferimento: nil,
                            daAllegare: false
                        )
                        results.append(fallback)
                    }
                case .failure(let error):
                    print("[Perxia] ❌ Cloud errore \(file.lastPathComponent): \(error)")
                    return .failure(error)
                }
                
                processed += 1
                await MainActor.run {
                    let progress = min(0.7, 0.7 * Double(processed) / Double(totalCount))
                    progressCallback(progress)
                }
            }
        }
        
        return .success(results)
    }
    
    private func strutturaBeniConPhi4(
        sinistro: Sinistro,
        descrizioni: [FileAnalysisResult],
        fulminazione: Bool,
        sopralluogo: Bool,
        ubicazione: String,
        propensionePerito: String,
        streamCallback: @escaping @MainActor (String) -> Void,
        progressCallback: @escaping @MainActor (Double) -> Void,
        partialCallback: @escaping @MainActor (PhiBeniResult) -> Void
    ) async -> Result<String, AIError> {
        guard let jsonDescrizioni = try? JSONEncoder().encode(descrizioni),
              var jsonString = String(data: jsonDescrizioni, encoding: .utf8) else {
            return .failure(.processingError("Impossibile serializzare descrizioni"))
        }
        
        // Limita la lunghezza delle descrizioni se troppo lunghe (max 50k caratteri per le descrizioni)
        if jsonString.count > 50000 {
            print("[Perxia] ⚠️ Descrizioni troppo lunghe (\(jsonString.count) caratteri), tronco a 50k")
            jsonString = String(jsonString.prefix(50000))
            // Cerca l'ultimo oggetto JSON completo
            if let lastBrace = jsonString.lastIndex(of: "}") {
                jsonString = String(jsonString[..<jsonString.index(after: lastBrace)])
                jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
                if jsonString.hasSuffix(",") {
                    jsonString = String(jsonString.dropLast())
                }
                jsonString = "[" + jsonString + "]"
            }
        }
        
        // Log per debug: mostra un campione delle descrizioni passate a Phi-4
        print("[Perxia] 🔍 Passando \(descrizioni.count) descrizioni a Phi-4")
        for (idx, desc) in descrizioni.prefix(3).enumerated() {
            print("  [\(idx+1)] Tipo: \(desc.tipo), Path: \(desc.path)")
            print("     Descrizione: \(String(desc.descrizione.prefix(150)))...")
            if let misure = desc.misure {
                print("     Misure: \(misure)")
            }
        }
        if descrizioni.count > 3 {
            print("  ... e altre \(descrizioni.count - 3) descrizioni")
        }
        
        // Per la fase di identificazione beni, non serve la knowledge base completa
        // Riduciamo al minimo per evitare prompt troppo lunghi
        let knowledge = "" // Rimossa per questa fase - non serve per identificare beni
        
        let prompt = buildPhiBeniPrompt(
            sinistro: sinistro,
            descrizioniJSON: jsonString,
            fulminazione: fulminazione,
            sopralluogo: sopralluogo,
            ubicazione: ubicazione,
            propensionePerito: propensionePerito,
            knowledge: knowledge
        )
        
        print("[Perxia] 📏 Lunghezza prompt per Phi-4: \(prompt.count) caratteri, \(descrizioni.count) descrizioni")
        
        let task = AITask(
            type: .textGeneration,
            priority: .primary,
            preferredProvider: .localText,
            fallbackProviders: [.cloudOpenAI],  // Fallback su cloud se Phi-4 non disponibile
            allowFallback: true,
            personality: .sparky,
            parameters: [
                "prompt": AnyCodable(prompt),
                "stream": AnyCodable(true)
            ],
            requiresKnowledge: false
        )
        
        var buffer = ""
        let result: Result<AIResult, AIError> = await withCheckedContinuation { cont in
            Task { @MainActor in
                var resumed = false
                AIManager.shared.enqueue(
                    task,
                    completion: { aiResult in
                        if resumed { return }
                        resumed = true
                        if aiResult.success {
                            // Log se è stato usato un fallback
                            if aiResult.usedFallback {
                                print("[Perxia] ⚠️ Beni: usato fallback \(aiResult.provider.displayName) invece di localText")
                            }
                            cont.resume(returning: .success(aiResult))
                        } else {
                            cont.resume(returning: .failure(aiResult.error ?? .processingError("Errore sconosciuto Phi-4")))
                        }
                    },
                    streamCallback: { chunk in
                        Task { @MainActor in
                            buffer += chunk
                            streamCallback(chunk)
                            // NON decodificare durante lo streaming - solo aggiorna progresso
                            let est = min(0.99, 0.7 + min(0.3, Double(buffer.count) / 4000.0 * 0.3))
                            progressCallback(est)
                        }
                    }
                )
            }
        }
        
        switch result {
        case .success(let aiResult):
            let text = (aiResult.result?.value as? String) ?? buffer
            print("[Perxia] ✅ Beni OK len=\(text.count) (provider: \(aiResult.provider.displayName), fallback: \(aiResult.usedFallback))")
            print("[Perxia] 📄 Testo ricevuto (primi 500 caratteri): \(String(text.prefix(500)))")
            // Restituisci il testo formattato invece di cercare di decodificare JSON
            return .success(text)
        case .failure(let error):
            print("[Perxia] ❌ Beni errore: \(error)")
            return .failure(error)
        }
    }

    /// Modello 2: Usa OpenAI per generare JSON strutturato dei beni
    private func strutturaBeniConOpenAI(
        sinistro: Sinistro,
        descrizioni: [FileAnalysisResult],
        fulminazione: Bool,
        sopralluogo: Bool,
        ubicazione: String,
        propensionePerito: String,
        streamCallback: @escaping @MainActor (String) -> Void,
        progressCallback: @escaping @MainActor (Double) -> Void,
        partialCallback: @escaping @MainActor (PhiBeniResult) -> Void
    ) async -> Result<PhiBeniResult, AIError> {
        guard let jsonDescrizioni = try? JSONEncoder().encode(descrizioni),
              var jsonString = String(data: jsonDescrizioni, encoding: .utf8) else {
            return .failure(.processingError("Impossibile serializzare descrizioni"))
        }
        
        // Limita la lunghezza delle descrizioni se troppo lunghe
        if jsonString.count > 50000 {
            print("[Perxia] ⚠️ Descrizioni troppo lunghe (\(jsonString.count) caratteri), tronco a 50k")
            jsonString = String(jsonString.prefix(50000))
            if let lastBrace = jsonString.lastIndex(of: "}") {
                jsonString = String(jsonString[..<jsonString.index(after: lastBrace)])
                jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
                if jsonString.hasSuffix(",") {
                    jsonString = String(jsonString.dropLast())
                }
                jsonString = "[" + jsonString + "]"
            }
        }
        
        let prompt = buildOpenAIBeniPrompt(
            sinistro: sinistro,
            descrizioniJSON: jsonString,
            fulminazione: fulminazione,
            sopralluogo: sopralluogo,
            ubicazione: ubicazione,
            propensionePerito: propensionePerito
        )
        
        print("[Perxia] 📏 Lunghezza prompt OpenAI: \(prompt.count) caratteri, \(descrizioni.count) descrizioni")
        
        let task = AITask(
            type: .textGeneration,
            priority: .primary,
            preferredProvider: .cloudOpenAI,
            fallbackProviders: [.localText],  // Fallback su Phi-4 se cloud non disponibile
            allowFallback: true,
            personality: nil,
            parameters: [
                "prompt": AnyCodable(prompt),
                "stream": AnyCodable(true)
            ],
            requiresKnowledge: true,
            knowledgeDomains: [.fenomenoElettrico, .stimaDanni, .letturaSchede, .generico],
            maxKnowledgeChunks: 6
        )
        
        var buffer = ""
        let result: Result<AIResult, AIError> = await withCheckedContinuation { cont in
            Task { @MainActor in
                var resumed = false
                AIManager.shared.enqueue(
                    task,
                    completion: { aiResult in
                        if resumed { return }
                        resumed = true
                        if aiResult.success {
                            // Log se è stato usato un fallback
                            if aiResult.usedFallback {
                                print("[Perxia] ⚠️ OpenAI beni: usato fallback \(aiResult.provider.displayName)")
                            }
                            cont.resume(returning: .success(aiResult))
                        } else {
                            cont.resume(returning: .failure(aiResult.error ?? .processingError("Errore sconosciuto OpenAI")))
                        }
                    },
                    streamCallback: { chunk in
                        Task { @MainActor in
                            buffer += chunk
                            streamCallback(chunk)
                            let est = min(0.99, 0.7 + min(0.3, Double(buffer.count) / 4000.0 * 0.3))
                            progressCallback(est)
                            
                            // Prova a decodificare parzialmente durante lo streaming
                            if let decoded: PhiBeniResult = self.decodeJSONResult(buffer) {
                                partialCallback(decoded)
                            }
                        }
                    }
                )
            }
        }
        
        switch result {
        case .success(let aiResult):
            let text = (aiResult.result?.value as? String) ?? buffer
            print("[Perxia] ✅ Beni OK len=\(text.count) (provider: \(aiResult.provider.displayName), fallback: \(aiResult.usedFallback))")
            print("[Perxia] 📄 Testo ricevuto (primi 500 caratteri): \(String(text.prefix(500)))")
            
            if let decoded: PhiBeniResult = decodeJSONResult(text) {
                print("[Perxia] ✅ JSON decodificato: \(decoded.beni.count) beni, complessità: \(decoded.complessita ?? "nil")")
                return .success(decoded)
            } else {
                print("[Perxia] ❌ Impossibile decodificare JSON. Testo completo:")
                print(text)
                return .failure(.processingError("Output non valido (provider: \(aiResult.provider.displayName))"))
            }
        case .failure(let error):
            print("[Perxia] ❌ Beni errore: \(error)")
            return .failure(error)
        }
    }
    
    /// Prompt per OpenAI (Modello 2) per generare JSON strutturato
    private func buildOpenAIBeniPrompt(
        sinistro: Sinistro,
        descrizioniJSON: String,
        fulminazione: Bool,
        sopralluogo: Bool,
        ubicazione: String,
        propensionePerito: String
    ) -> String {
        return """
        Analizza le descrizioni JSON delle foto e identifica i BENI ELETTRICI/ELETTRONICI presenti nel sinistro.
        Restituisci SOLO un JSON valido con la struttura richiesta.

        OBIETTIVO:
        Identificare i BENI ELETTRICI/ELETTRONICI danneggiati (caldaia, inverter fotovoltaico, pompa di calore, quadro elettrico, cancello elettrico, UPS, TV, compressore, scheda elettronica, varistore, TVS, ecc.)
        e raggruppare le foto che si riferiscono allo stesso bene.

        IMPORTANTE:
        - Concentrati SOLO su beni elettrici/elettronici e loro componenti
        - IGNORA problemi strutturali, muri, muschio, muffa, corrosione non elettrica
        - Cerca danni elettrici: bruciature, rigonfiamenti, componenti esplosi, varistori/TVS distrutti, piste fuse, cortocircuiti visibili
        - Cerca componenti elettronici: schede, moduli, relè, contattori, fusibili, interruttori

        STRUTTURA JSON RICHIESTA:
        {
          "beni": [
            {
              "nome": "SOLO nome del bene (es. 'Inverter fotovoltaico', 'Lavastoviglie', 'Quadro elettrico') - NON includere marca nel nome",
              "tipoBene": "tipo generale (es. 'elettrodomestico', 'impianto')",
              "marca": "marca separata (es. 'Miele', 'Schneider Electric') - NON nel nome",
              "modello": "modello o null",
              "anno": "anno CERTA se leggibile (es. '2020') - solo se sicuro",
              "annoStimato": "anno STIMATO se non certo (es. '2018-2022') - indicare come stima",
              "componenti": ["lista componenti"],
              "osservazioni": "descrizione dettagliata danni elettrici visibili",
              "test": "DETTAGLIO completo: quali test sono stati fatti, esiti ottenuti, se eseguiti correttamente (es. 'Resistenze avvolgimenti: fase-neutro 12.5Ω, fase-terra 8.2Ω (asimmetriche). Isolamento crollato su avvolgimento principale (0.1MΩ). Test eseguiti correttamente con multimetro digitale.')",
              "compatibilitaDanno": "compatibile|poco_probabile|non_compatibile|indeterminato",
              "stima": null,
              "note": "ubicazione INTERNA del bene nella foto (es. 'sul tetto', 'in garage') - solo per uso interno modello, NON mostrare in UI",
              "foto": ["path1", "path2"],
              "fonti": ["path delle foto da cui derivano le info generali"],
              "fotoOsservazioni": ["path delle foto che mostrano i danni/osservazioni"],
              "fotoTest": ["path delle foto che mostrano i test strumentali"],
              "fotoComponenti": ["path delle foto che mostrano i componenti"],
              "certezzaNome": 0.95,  // Valore realistico 0.0-1.0, NON sempre 0.5
              "certezzaModello": 0.85,
              "certezzaAnno": 0.0,  // 0.0 se non visibile, 0.9+ se certo, 0.5-0.7 se stimato
              "certezzaOsservazioni": 0.8,  // Valore realistico basato su chiarezza foto
              "certezzaTest": 0.7,  // Valore realistico basato su chiarezza misure
              "certezzaCompatibilita": 0.75,  // Valore realistico basato su evidenze
              "certezzaStima": 0.0,  // 0.0 se non stimabile
              "componentiDettaglio": []
            }
          ],
          "complessita": "semplice|intermedio|complesso",
          "ubicazioneValidata": null,
          "ubicazioneNote": null
        }
        
        REGOLE CERTEZZE:
        - certezzaNome: 0.9+ se nome chiaramente visibile, 0.7-0.8 se dedotto, 0.5-0.6 se incerto
        - certezzaModello: 0.9+ se modello leggibile, 0.6-0.8 se parziale, 0.0 se non visibile
        - certezzaAnno: 0.9+ se anno certo, 0.5-0.7 se stimato, 0.0 se non visibile
        - certezzaOsservazioni: 0.8+ se danni chiari, 0.5-0.7 se parziali, 0.0 se non visibili
        - certezzaTest: 0.8+ se misure chiare e leggibili, 0.5-0.7 se parziali, 0.0 se non presenti
        - certezzaCompatibilita: 0.8+ se evidenze forti, 0.5-0.7 se deboli, 0.0 se indeterminato
        - NON usare sempre 0.5! Usa valori realistici basati sulla chiarezza dei dati.

        CRITICO: Restituisci SOLO JSON, nessun testo prima o dopo. Oggetto con chiave "beni", NON array semplice.

        DESCRIZIONI DA ANALIZZARE:
        \(descrizioniJSON)
        """
    }
    
    /// Estrae e decodifica il primo JSON valido dal testo (tollerante a prefissi/suffissi e markdown code blocks)
    private func decodeJSONResult<T: Decodable>(_ text: String) -> T? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let decoder = JSONDecoder()
        
        // Rimuovi markdown code blocks (```json ... ``` o ``` ... ```)
        // Gestisce sia ```json che ``` all'inizio
        if cleaned.hasPrefix("```") {
            // Rimuovi il primo blocco di backticks (```json o ```)
            if cleaned.hasPrefix("```json") {
                cleaned = String(cleaned.dropFirst(7)) // Rimuovi "```json"
            } else if cleaned.hasPrefix("```") {
                cleaned = String(cleaned.dropFirst(3)) // Rimuovi "```"
            }
            
            // Rimuovi il blocco finale di backticks (```)
            if let codeEndRange = cleaned.range(of: "```", options: .backwards) {
                cleaned = String(cleaned[..<codeEndRange.lowerBound])
            }
            
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        func tryDecode(_ candidate: String) -> (success: Bool, result: T?, error: String?) {
            guard let data = candidate.data(using: .utf8) else {
                return (false, nil, "Impossibile convertire in Data")
            }
            do {
                let decoded = try decoder.decode(T.self, from: data)
                return (true, decoded, nil)
            } catch {
                return (false, nil, error.localizedDescription)
            }
        }
        
        // Prova prima con il testo pulito completo
        let directResult = tryDecode(cleaned)
        if directResult.success, let decoded = directResult.result {
            return decoded
        }
        
        // Se fallisce, prova a estrarre il primo JSON object o array valido
        if let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}") {
            let slice = String(cleaned[start...end])
            let objectResult = tryDecode(slice)
            if objectResult.success, let decoded = objectResult.result {
                return decoded
            }
        }
        
        if let start = cleaned.firstIndex(of: "["), let end = cleaned.lastIndex(of: "]") {
            let slice = String(cleaned[start...end])
            let arrayResult = tryDecode(slice)
            if arrayResult.success, let decoded = arrayResult.result {
                return decoded
            }
        }
        
        // Log dettagliato dell'errore
        print("[Perxia] ❌ Errore decodifica JSON:")
        print("  Errore diretto: \(directResult.error ?? "nessuno")")
        print("  Primi 200 caratteri del testo pulito: \(String(cleaned.prefix(200)))")
        
        return nil
    }
    
    private func generaRelazioneConPhi4(
        sinistro: Sinistro,
        beni: PhiBeniResult,
        fulminazione: Bool,
        sopralluogo: Bool,
        ubicazione: String,
        propensionePerito: String,
        streamCallback: @escaping @MainActor (String) -> Void
    ) async -> Result<String, AIError> {
        guard let jsonBeni = try? JSONEncoder().encode(beni),
              let jsonBeniString = String(data: jsonBeni, encoding: .utf8) else {
            return .failure(.processingError("Impossibile serializzare beni"))
        }
        
        // Determina indennizzo: se almeno un bene ha compatibilità FE positiva o stima
        let indennizzo = beni.beni.contains { bene in
            (bene.compatibilitaDanno?.localizedCaseInsensitiveContains("compatibile") == true) ||
            (bene.stima != nil && !bene.stima!.isEmpty)
        }
        
        let selectedTemplate = selectTemplate(sopralluogo: sopralluogo, fulminazione: fulminazione, indennizzo: indennizzo)
        let prompt = buildPhiRelazionePrompt(
            sinistro: sinistro,
            beniJSON: jsonBeniString,
            fulminazione: fulminazione,
            sopralluogo: sopralluogo,
            ubicazione: ubicazione,
            propensionePerito: propensionePerito,
            template: selectedTemplate
        )
        
        let task = AITask(
            type: .textGeneration,
            priority: .primary,
            preferredProvider: .localText,
            fallbackProviders: [.cloudOpenAI],  // Fallback su cloud se Phi-4 non disponibile
            allowFallback: true,
            personality: .sparky,
            parameters: [
                "prompt": AnyCodable(prompt),
                "stream": AnyCodable(false)
            ],
            requiresKnowledge: false
        )
        
        // Usa AIManager per gestire automaticamente i fallback
        let result: Result<AIResult, AIError> = await withCheckedContinuation { cont in
            Task { @MainActor in
                var resumed = false
                AIManager.shared.enqueue(
                    task,
                    completion: { aiResult in
                        if resumed { return }
                        resumed = true
                        if aiResult.success {
                            if aiResult.usedFallback {
                                print("[Perxia] ⚠️ Relazione: usato fallback \(aiResult.provider.displayName) invece di localText")
                            }
                            cont.resume(returning: .success(aiResult))
                        } else {
                            cont.resume(returning: .failure(aiResult.error ?? .processingError("Errore generazione relazione")))
                        }
                    }
                )
            }
        }
        
        switch result {
        case .success(let aiResult):
            let text = aiResult.result?.value as? String ?? ""
            print("[Perxia] ✅ Relazione OK (provider: \(aiResult.provider.displayName), fallback: \(aiResult.usedFallback))")
            return .success(text)
        case .failure(let error):
            print("[Perxia] ❌ Relazione errore: \(error)")
            return .failure(error)
        }
    }
    
    private func buildCloudPrompt(
        sinistro: Sinistro,
        file: URL,
        isImage: Bool,
        fulminazione: Bool,
        sopralluogo: Bool,
        ubicazione: String,
        propensionePerito: String
    ) -> String {
        // Leggi tag disponibili dinamicamente
        let availableTags = FileTagManager.FileTag.availableTags
        let tagList = availableTags.map { "\($0.id): \($0.name)" }.joined(separator: ", ")
        
        return """
        Ruolo: Sei un modello tecnico per l'analisi preliminare di foto e documenti relativi a sinistri di Fenomeno Elettrico.
        
        TAG DISPONIBILI per il campo "tagSuggerito":
        \(tagList)
        
        IMPORTANTE: Usa SOLO uno dei tag sopra elencati per "tagSuggerito". Se nessun tag è appropriato, usa null.

        Obiettivo: Per ogni file fornito, estrarre SOLO informazioni realmente visibili sui BENI ELETTRICI/ELETTRONICI e i loro DANNI, senza aggiungere nulla di inventato.

        IMPORTANTE - Concentrati principlamente su:
        - Beni elettrici/elettronici (caldaia, inverter, pompa di calore, quadro elettrico, cancello elettrico, UPS, TV, compressore, scheda elettronica, varistore, TVS, relè, contattori, fusibili, interruttori)
        - Danni elettrici visibili (bruciature, rigonfiamenti, componenti esplosi, varistori/TVS distrutti, piste fuse, cortocircuiti, carbonizzazioni)
        - Componenti elettronici danneggiati
        - Misure elettriche (tensione, corrente, isolamento)
        - Eventuali segni di umidità o usura nautrale

        IGNORA:
        - Problemi strutturali (muri, soffitti, porte)
        - Problemi ambientali (muschio, muffa, umidità non elettrica)
        - Corrosione non elettrica
        - Dettagli architettonici non rilevanti

        Regole non negoziabili:
        1. Rispondi ESCLUSIVAMENTE con un array JSON valido.
        2. Se un'informazione non è visibile → usa null.
        3. Se la foto mostra solo problemi strutturali/ambientali senza beni elettrici → tipo = "irrilevante", daAllegare = false.
        4. Non fare inferenze tecniche o diagnosi: limitati a ciò che è oggettivamente visibile.
        5. Non usare termini ambigui ("probabile", "potrebbe essere", "forse").
        6. Non usare dati tecnici o conoscenze esterne: solo ciò che appare nel file.
        7. Per "anomalieVisive": descrivi SOLO danni elettrici visibili (bruciature, esplosioni componenti, piste fuse, ecc.), NON problemi strutturali.

        Output richiesto (schema):
        [
          {
            "path": "\(file.path)",
            "tipo": "ubicazione | bene | componente | strumento | dettaglio_danno | irrilevante | scarta",
            "descrizione": "Descrizione dettagliata del bene elettrico/elettronico visibile e dei suoi danni",
            "contesto": "Dove si trova (interno/esterno, stanza, tetto, garage, ecc.)",
            "anomalieVisive": "Dettaglio dei danni elettrici visibili (bruciature, componenti esplosi, piste fuse, ecc.) - SOLO danni elettrici",
            "misure": {
              "valore": "...",
              "strumento": "...",
              "correttezzaPosizionamento": "...",
              "correttezzaImpostazioni": "...",
              "valutazioneTecnica": "...",
              "misuraRisolutiva": true
            },
            "validitaMisura": "...",
            "tagSuggerito": "ID del tag",
            "tagCommento": "Componente: nome del componente specifico mostrato (es. 'scheda elettronica', 'motore', 'varistore')",
            "beneRiferimento": "Bene: nome del bene a cui appartiene il componente/test/ripristino (es. 'caldaia', 'inverter fotovoltaico')",
            "daAllegare": true
          }
        ]
        Regole:
        - Se la foto è sfocata/irrilevante/non mostra beni elettrici, metti tipo = "irrilevante" e "daAllegare": false.
        - Non inventare: se un dato non si vede scrivi null.
        - "anomalieVisive" deve contenere SOLO danni elettrici/elettronici visibili, NON problemi strutturali o ambientali.
        
        Campo "tagSuggerito":
        - Usa SOLO uno dei tag disponibili sopra elencati.
        - "foto_bene": foto che mostra un bene elettrico/elettronico completo (caldaia, inverter, TV, ecc.)
        - "foto_componente": foto che mostra un componente specifico di un bene (scheda elettronica, motore, varistore, ecc.)
        - "foto_test_funzionale": foto di test funzionale (accensione, spie, display, funzionamento)
        - "test_strumentale": foto di test con strumenti di misura (multimetro, megger, ecc.)
        - "foto_ripristino": foto del ripristino/riparazione effettuata
        - "foto_ubicazione_tecnico": foto dell'ubicazione tecnica del bene/impianto
        - "foto_ubicazione_rischio": foto dell'ubicazione con focus sul rischio
        - null: se la foto non mostra beni/componenti/ubicazioni elettrici rilevanti
        
        Campo "tagCommento" (COMPONENTE):
        - Indica il NOME del componente specifico mostrato nella foto
        - Es. per foto_componente: "scheda elettronica", "motore", "varistore", "condensatore", "relè"
        - Es. per foto_ubicazione_*: "sul tetto", "in garage", "locale tecnico"
        - null: se non applicabile
        
        Campo "beneRiferimento" (BENE):
        - Indica il NOME del bene elettrico a cui appartiene la foto
        - OBBLIGATORIO per: foto_componente, foto_test_funzionale, test_strumentale, foto_ripristino
        - Es. "caldaia", "inverter fotovoltaico", "lavatrice", "climatizzatore", "quadro elettrico"
        - Serve per raggruppare le foto per bene nella documentazione finale
        - null: solo per foto_ubicazione_* e foto_bene (dove il bene è già nel tag)
        
        Campo "daAllegare":
        - true: La foto deve essere inclusa nella documentazione finale da inviare alla compagnia assicurativa.
          Usa true per foto chiare, rappresentative, che documentano bene il danno elettrico, il bene elettrico o l'ubicazione - vogliamo comunque almeno due foto per l'ubicazione ed una per bene.
        - false: La foto è utile per l'analisi ma non deve essere inclusa nella documentazione finale.
          Usa false per foto di test/debug, duplicate, troppo tecniche, o dettagli interni non rappresentativi.

        GENERARE ORA SOLO JSON, SENZA TESTO ESTERNO.
        """
    }
        
    private func buildPhiBeniPrompt(
        sinistro: Sinistro,
        descrizioniJSON: String,
        fulminazione: Bool,
        sopralluogo: Bool,
        ubicazione: String,
        propensionePerito: String,
        knowledge: String
    ) -> String {
        let richiesta = sinistro.richiesta?.doubleValue ?? 0
        let templates = templatesJSON()
        return """
        Analizza le descrizioni JSON delle foto e identifica i BENI ELETTRICI/ELETTRONICI presenti nel sinistro.
        Rispondi ESCLUSIVAMENTE in italiano.

        OBIETTIVO:
        Identificare i BENI ELETTRICI/ELETTRONICI danneggiati (caldaia, inverter fotovoltaico, pompa di calore, quadro elettrico, cancello elettrico, UPS, TV, compressore, scheda elettronica, varistore, TVS, ecc.)
        e raggruppare le foto che si riferiscono allo stesso bene.

        IMPORTANTE:
        - Concentrati SOLO su beni elettrici/elettronici e loro componenti
        - IGNORA problemi strutturali, muri, muschio, muffa, corrosione non elettrica
        - Cerca danni elettrici: bruciature, rigonfiamenti, componenti esplosi, varistori/TVS distrutti, piste fuse, cortocircuiti visibili
        - Cerca componenti elettronici: schede, moduli, relè, contattori, fusibili, interruttori

        ISTRUZIONI:
        1. Cerca nelle descrizioni nomi di beni elettrici/elettronici, marche, modelli (anche se scritti in inglese)
        2. Raggruppa le foto che mostrano lo stesso bene
        3. Per ogni bene identificato, elenca in DETTAGLIO:
           - **Nome del bene** (es. "Inverter fotovoltaico", "Quadro elettrico", "Scheda elettronica")
           - **Marca** (se visibile o menzionata nelle descrizioni)
           - **Modello** (se visibile o menzionato, anche parziale)
           - **Anno** (solo se leggibile o esplicitamente menzionato)
           - **Componenti elettrici visibili** (es. "scheda principale", "varistore", "TVS", "relè", "fusibile", "contattore")
           - **Danni elettrici osservati** (es. "bruciature su scheda", "varistore esploso", "pista fusa", "rigonfiamento condensatore", "componente carbonizzato")
           - **Ubicazione** (dove si trova nella foto: "sul tetto", "in garage", "esterno", "interno" - NON l'indirizzo del sinistro)
           - **Foto associate** (solo i nomi file, non i path completi)

        FORMATO OUTPUT (usa markdown, rispondi SOLO in italiano, sii DETTAGLIATO):
        NON AGGIUNGERE ALTRI COMMENTI. NON RIPORTARE IL JSON DATOTI IN INPUT.
        # Beni elettrici/elettronici identificati
        
        ## [Nome del bene]
        
        **Marca:** [marca o "non specificata"]  
        **Modello:** [modello o "non specificato"]  
        **Anno:** [anno o "non specificato"]  
        **Componenti:** [lista dettagliata componenti elettrici visibili]  
        **Danni osservati:** [descrizione dettagliata dei danni elettrici visibili, es. "bruciature localizzate su scheda principale", "varistore esploso", "pista fusa in prossimità del componente X"]  
        **Ubicazione:** [dove si trova nella foto, es. "sul tetto", "in garage"]  
        **Foto:** [nome file1.jpg, nome file2.jpg]
        
        ---

        DESCRIZIONI DA ANALIZZARE:
        \(descrizioniJSON)
        """
    }

    private func buildPhiDanniPrompt(
        sinistro: Sinistro,
        beniJSON: String,
        descrizioniJSON: String,
        fulminazione: Bool,
        sopralluogo: Bool,
        ubicazione: String,
        propensionePerito: String
    ) -> String {
        """
        Sei Sparky, modello tecnico locale specializzato in Fenomeno Elettrico.
        Ora devi SOLO approfondire:
        - il danno,
        - le misure,
        - la compatibilità con FE,
        per ciascun bene già identificato nella fase precedente.

        Non devi creare nuovi beni, ma aggiornare quelli esistenti.

        =====================================================================
        📥 INPUT
        =====================================================================

        1) BENI BASE (JSON):
        \(beniJSON)

        2) DESCRIZIONI TECNICHE FILE (JSON ARRAY):
        \(descrizioniJSON)

        Contengono soprattutto:
        - dettagli su danni, componenti, schede
        - misure multimetro
        - anomalie visive
        - contesto tecnico

        3) FULMINAZIONE:
        \(fulminazione ? "true" : "false")

        =====================================================================
        🎯 OBIETTIVO
        =====================================================================

        Per OGNI bene già presente in "beni":

        A) Arricchire:
           - osservazioni: descrizione tecnica sintetica dei danni (bruciature, rigonfiamenti, ossidazioni, manomissioni, ecc.)
           - test: riassunto delle misure rilevanti, con valutazione (correttezza puntali, impostazioni, plausibilità, conclusione)

        B) Classificare il danno:
           - compatibilitaDanno: "compatibile" | "poco_probabile" | "non_compatibile" | "indeterminato"
           (SOLO questo campo, NON compatibilitaGaranzia)

        C) Eventuale stima:
           - stima: solo se ricavabile in modo sensato (es. "sostituzione scheda elettronica standard", oppure se esiste una cifra esplicita nelle descrizioni).
           - altrimenti lascia stima = null.

        D) Note:
           - note: eventuali note sintetiche su residui mancanti, documentazione insufficiente, misure non risolutive.

        =====================================================================
        🚫 VINCOLI NON NEGOZIABILI
        =====================================================================

        1. NON modificare la lista dei beni: non aggiungere né togliere elementi.
        2. NON cambiare nome, marca, modello, anno: aggiornali solo se hai evidenze forti.
        3. NON inventare misure, guasti, componenti, marchi, valori economici.
        4. Se una misura non è chiaramente leggibile o non è coerente → segnala come "non_valida" o "non_risolutiva".
        5. La compatibilità FE deve basarsi SOLO su:
           - anomalie visive (bruciature localizzate, varistori/TVS distrutti, piste fuse, componenti esplosi),
           - misure (corto, isolamento crollato, triade alterata),
           - eventuale informazione di fulminazione.

        6. Se mancano elementi TECNICI sufficienti:
           - compatibilitaDanno = "indeterminato"

        7. Usa la fulminazione SOLO come indizio esterno:
           - non puoi dichiarare FE senza evidenze tecniche interne coerenti.

        8. Non inserire spiegazioni lunghe: osservazioni e test devono essere sintetici e tecnici.

        =====================================================================
        📤 OUTPUT – STESSA STRUTTURA BENI BASE
        =====================================================================

        Devi restituire un JSON con la STESSA STRUTTURA di "beniJSON",
        ma con i campi seguenti aggiornati per ciascun bene:

        - osservazioni
        - test
        - compatibilitaDanno
        - compatibilitaDanno (SOLO questo)
        - stima
        - note
        - certezzaOsservazioni (0.0–1.0)
        - certezzaTest (0.0–1.0)
        - certezzaCompatibilita (0.0–1.0)
        - certezzaStima (0.0–1.0)

        Gli altri campi (nome, marca, modello, anno, foto, fonti, ecc.)
        devono essere mantenuti, salvo piccole correzioni supportate da evidenze chiare.

        =====================================================================
        📌 LINEE GUIDA COMPATIBILITÀ FE
        =====================================================================

        - compatibile:
          - danno localizzato su componenti elettrici/elettronici coerente con picco/sovratensione
          - protezioni (MOV/TVS) danneggiate
          - piste fuse in un punto definito
          - misure indicano corto/isolamento crollato senza cause meccaniche

        - non_compatibile:
          - usura, ruggine, ossidazioni diffuse
          - surriscaldamento prolungato
          - blocchi meccanici
          - vetustà evidente

        - poco_probabile:
          - segni non chiari
          - documentazione confusa
          - possibili cause alternative prevalenti

        - indeterminato:
          - poche foto
          - misure assenti o non interpretabili
          - nessuna evidenza sufficiente

        =====================================================================
        📤 ISTRUZIONE FINALE
        =====================================================================

        Rispondi SOLO con il JSON completo dei beni aggiornati,
        senza testo esterno, senza commenti.
        """
    }
    
    private func buildPhiRelazionePrompt(
        sinistro: Sinistro,
        beniJSON: String,
        fulminazione: Bool,
        sopralluogo: Bool,
        ubicazione: String,
        propensionePerito: String,
        template: String
    ) -> String {
        return """
        Sei Sparky, modello locale.
        Devi SOLO generare la relazione tecnica finale, partendo da:
        - un TEMPLATE fisso di testo,
        - i BENI già analizzati (con osservazioni, test, compatibilità, stima).

        Non devi più fare diagnosi nuova: devi solo trasformare i dati dei beni in un testo coerente con il template.

        =====================================================================
        📥 INPUT
        =====================================================================

        1) TEMPLATE RELAZIONE (da usare come base, senza cambiarne struttura e stile):

        ---
        \(template)
        ---

        2) BENI (JSON):
        \(beniJSON)

        I beni contengono per ciascun elemento:
        - nome, tipoBene, marca, modello, anno/annoStimato
        - osservazioni
        - test
        - compatibilitaDanno
        - compatibilitaDanno (SOLO questo)
        - stima
        - note
        - complessita (a livello globale)

        3) DATI DI CONTESTO:
        - sopralluogo: \(sopralluogo ? "true" : "false")
        - fulminazione: \(fulminazione ? "true" : "false")
        - ubicazione dichiarata: \(ubicazione ?? "N/A")

        =====================================================================
        🎯 OBIETTIVO
        =====================================================================

        Generare una relazione:

        - che rispetti struttura e stile del TEMPLATE.
        - che contenga:
          - un elenco sintetico dei beni con marca, modello e anno (se noti) discorsivo,
          - un breve richiamo delle evidenze principali per la valutazione FE (senza entrare in dettagli strumentali),
          - un'espressione chiara dell'esito (FE riconosciuto / non riconosciuto) coerente con i beni,
          - eventuali note su:
            • documentazione insufficiente,
            • residui mancanti,
            • ubicazione non coerente (se emerso dalle foto).

        - che mantenga le frasi standard del template (ad es. quelle sulla stima al netto delle opere non indennizzabili in garanzia FE).
        - che non contenga elenchi puntati o numerati. Dev'essere un testo fluido e continuo.

        =====================================================================
        🚫 VINCOLI NON NEGOZIABILI
        =====================================================================

        1. NON modificare il tono e la struttura del template: 
           - conserva l'impostazione dei paragrafi,
           - non aggiungere premesse o conclusioni estranee.

        2. NON inserire:
           - valori di misura (ohm, megaohm, volt) → restano dentro il processo interno.
           - dettagli su posizionamento puntali, impostazioni strumento, ecc.
           - testo tecnico troppo specialistico.

        3. NON contraddire i dati dei beni:
           - se per tutti i beni compatibilitaDanno è "non_compatibile" o "poco_probabile",
             l'esito NON può essere "danno riconducibile ad un fenomeno elettrico".
           - se almeno un bene ha compatibilitaDanno "compatibile",
             puoi formulare un esito di FE riconosciuto (se il template lo prevede).

        4. Se i beni presentano esiti misti l'intera perizia sarà positiva e riconsceremo tutti i beni come danneggiati da fenomeno elettrico.

        5. Se dai beni emergono elementi di ambiguità o documentazione insufficiente:
           - richiamalo brevemente nel paragrafo osservazioni (in sostituzione di [OSSERVAZIONI_SINTETICHE]).

        - Se i beni suggeriscono dubbi sull'ubicazione dichiarata, puoi inserire una nota sintetica nelle osservazioni.

        =====================================================================
        📤 OUTPUT
        =====================================================================

        Devi restituire SOLO il testo completo della relazione finale,
        senza JSON, senza segnaposto residui (come [ELENCO_BENI] o [OSSERVAZIONI_SINTETICHE]),
        senza commenti esterni.
        """
    }

    private func relazioneTemplate(sopralluogo: Bool, fulminazione: Bool) -> String {
        if sopralluogo && fulminazione {
            return defaultTemplates.first { $0.titolo.contains("Sopralluogo, FE") }?.contenuto ?? defaultTemplates[0].contenuto
        }
        if sopralluogo && !fulminazione {
            return defaultTemplates.first { $0.titolo.contains("Sopralluogo, no FE") }?.contenuto ?? defaultTemplates[0].contenuto
        }
        if !sopralluogo && fulminazione {
            return defaultTemplates.first { $0.titolo.contains("Documentale, FE") }?.contenuto ?? defaultTemplates[0].contenuto
        }
        return defaultTemplates.first { $0.titolo.contains("Documentale, no FE") }?.contenuto ?? defaultTemplates[0].contenuto
    }
    
    private func systemPromptCloud() -> String {
        """
PROMPT:

Sei un perito tecnico specializzato in Fenomeno Elettrico.

Ricevi una o più immagini relative a un sinistro assicurativo.

Devi analizzare ciò che vedi e produrre un JSON valido (senza testo fuori dal JSON) secondo lo schema seguente.

Obiettivo dell’analisi:

Per ogni immagine devi:
 1. Descrivere nel dettaglio cosa si vede
    • contesto dell’ambiente
    • oggetti visibili
    • scritte, etichette, modelli, marchi
    • componenti elettronici riconoscibili
    • dettagli utili per diagnosi FE
 2. Classificare il tipo di foto
    • ubicazione
    • bene
    • componente
    • strumento di misura
    • dettaglio danno
    • irrilevante / sfocata / non utilizzabile
 3. Estrare informazioni utili alla perizia
    • tipo di edificio → villa, condominio, negozio, capannone industriale…
    • numero piani, presenza giardino, cancelletto, ingresso
    • stima dell’anno di costruzione (anche stimato: “circa 1980–2000”)
    • destinazione d’uso dell’ambiente interno (garage, cucina, vano tecnico…)
 4. Identificare bene e componente
    • se è un bene completo (caldaia, cancello, inverter FV, frigorifero…)
    • se è una scheda elettronica e a quale bene potrebbe appartenere
    • se è solo un dettaglio relativo a quel bene
 5. Analizzare le misure elettriche (se presenti)
    • corretta/impostazione corretta strumento
    • puntali posizionati correttamente
    • misura rilevata e unità
    • se la misura è plausibile per diagnostica FE (sovratensione/corto/fulmine ecc.)
    • se la misura è risolutiva o se è inutile/errata
    • se occorre ripetere la misura
 6. Diagnosticare segni di danno
    • bruciature, annerimenti, rigonfiamenti
    • segni termici, elettrolitici, esplosioni componenti
    • tracce di acqua/umidità, ruggine, ossidazioni
    • segni di intervento manuale / manomissione (bruciature con accendino, graffi deliberati, PCB scaldato localmente…)
 7. Validare la qualità della foto
    • foto sfocata
    • pessima esposizione
    • inquadratura inutilizzabile
    • irrilevante
    → In questi casi indica "valida": false e compila comunque il JSON.
 8. Stima dell’anno del bene
    • se leggibile da targhetta → anno reale
    • se non leggibile → stima plausibile e indicare "stimato": true
 9. Suggerire tag automatico (per classificazione interna)
    • Usa i tag disponibili: foto_bene, foto_componente, foto_test_funzionale, test_strumentale, foto_ripristino, foto_ubicazione_tecnico, foto_ubicazione_rischio
    • Se inutile → null
 10. Compilare i campi "tagCommento" (componente) e "beneRiferimento" (bene):
    • tagCommento: nome del COMPONENTE specifico mostrato (es. "scheda elettronica", "motore", "varistore")
    • beneRiferimento: nome del BENE a cui appartiene (es. "caldaia", "inverter fotovoltaico") - OBBLIGATORIO per foto_componente, foto_test_funzionale, test_strumentale, foto_ripristino
    • Questi campi permettono di raggruppare le foto per bene e componente nella documentazione finale
 11. Indicare se la foto è utile da allegare alla documentazione finale della perizia (campo "daAllegare")
     IMPORTANTE: Questo campo NON influisce sull'analisi dei beni. Tutte le foto vengono analizzate indipendentemente da questo flag.
     - "daAllegare": true → La foto deve essere inclusa nella documentazione finale da inviare alla compagnia assicurativa.
       Usa true per foto chiare, rappresentative, che documentano bene il danno o il bene.
     - "daAllegare": false → La foto è utile per l'analisi ma non deve essere inclusa nella documentazione finale.
       Usa false per: foto di test/debug, foto duplicate, foto troppo tecniche/dettagliate, foto sfocate ma ancora analizzabili,
       foto che mostrano solo dettagli interni non rappresentativi per la compagnia.
     Questo flag viene passato al TagManager per gestire i tag delle foto e sarà usato in fase di selezione delle foto
     da inviare alla compagnia a fine perizia.

OUTPUT JSON – Formato richiesto
Devi rispondere solo con un array JSON di oggetti, uno per ogni immagine ricevuta:
[
  {
    "path": "PERCORSO_DEL_FILE",
    "tipo": "ubicazione | bene | componente | strumento | dettaglio_danno | irrilevante",
    "descrizione": "descrizione completa e dettagliata di ciò che si vede",
    "contesto": "descrizione ambiente o area (interno/esterno, locale tecnico, vano, giardino, tettoia...)",
    "ubicazioneStimata": {
      "tipoEdificio": "villa | condominio | negozio | capannone | ufficio | non_identificabile",
      "numeroPiani": "numero o stima",
      "annoCostruzioneStimato": "stima o null"
    },
    "bene": {
      "nome": "nome del bene se riconoscibile",
      "modello": "modello rilevato o stimato",
      "anno": "anno reale o stimato",
      "stimato": true,
      "componentiPossibili": ["componenti a cui potrebbe appartenere la parte vista"],
      "compatibilitaBene": "alta | media | bassa | non_identificabile"
    },
    "misure": {
      "valore": "valore + unità se leggibile",
      "strumento": "tipo di strumento",
      "correttezzaPosizionamento": "corretto | scorretto | non_valutabile",
      "correttezzaImpostazioni": "corretto | scorretto | non_valutabile",
      "valutazioneTecnica": "spiega se la misura è sensata o no",
      "misuraRisolutiva": true
    },
    "validitaMisura": "valida | non_valida | non_presente",
    "anomalieVisive": "rigonfiamenti, bruciature, rotture, ossidazioni, segni di intervento...",
    "dannoFE": "compatibile | poco_probabile | non_compatibile | indeterminato",
    "dannoNonFE": "umidità | ruggine | urto | usura | manomissione | nessuno | indeterminato",
    "qualitaFotoValida": true,
    "tagSuggerito": "id-tag o null",
    "tagCommento": "componente specifico mostrato (es. 'scheda elettronica', 'motore') o null",
    "beneRiferimento": "nome del bene a cui appartiene (es. 'caldaia', 'inverter') - OBBLIGATORIO per foto_componente, foto_test_funzionale, test_strumentale, foto_ripristino",
    "daAllegare": true
  }
]

REGOLE
• Nessun testo fuori dal JSON.
• Non inventare dati: se non visibili → usa null.
• Se la foto è sfocata o inutile: "tipo": "irrilevante", "qualitaFotoValida": false.
• Se non sai l’anno: "anno": null, "stimato": false.
• Usare descrizioni tecniche e precise, non generiche.
• Le misure devono essere riportate esattamente come visibili.
• Se la misura è impossibile o incoerente → segnalalo.
• Se lo strumento è impostato male → evidenzialo.
• Se i puntali sono nel punto sbagliato → indicalo.

Risultato atteso
Questo JSON sarà inviato a un modello successivo che utilizzerà queste informazioni per:
• assemblare beni, componenti e test
• generare la relazione tecnica
• determinare compatibilità FE
• analizzare dinamiche e diagnosi
"""
    }
    
    // MARK: - Miglioramento Relazione Peritale
    
    /// Migliora una relazione peritale usando IA
    /// - Parameters:
    ///   - relazione: La relazione originale da migliorare
    ///   - limiteCaratteri: Limite massimo di caratteri (default 1500)
    ///   - streamCallback: Callback per streaming progressivo
    /// - Returns: La relazione migliorata
    func miglioraRelazione(
        _ relazione: String,
        limiteCaratteri: Int = 1500,
        streamCallback: @escaping @MainActor (String) -> Void
    ) async -> Result<String, AIError> {
        
        let prompt = """
        Sei un perito assicurativo esperto. Riscrivi la seguente relazione peritale rendendola più fluida e professionale.

        REGOLE TASSATIVE:
        1. NON stravolgere la struttura o il contenuto
        2. NON aggiungere informazioni non presenti nell'originale
        3. NON citare valori numerici esatti di misure tecniche (ohm, volt, megaohm)
        4. Mantieni un tono professionale ma leggibile a tutti
        5. Evita linguaggio aulico o eccessivamente formale
        6. Il testo DEVE essere massimo \(limiteCaratteri) caratteri
        7. Preserva tutte le informazioni tecniche rilevanti
        
        RELAZIONE ORIGINALE:
        \(relazione)
        
        Riscrivi la relazione (max \(limiteCaratteri) caratteri):
        """
        
        let task = AITask(
            type: .textGeneration,
            priority: .primary,
            preferredProvider: .cloudOpenAI,
            fallbackProviders: [.localText],
            allowFallback: true,
            personality: nil,
            parameters: [
                "prompt": AnyCodable(prompt),
                "stream": AnyCodable(true)
            ],
            requiresKnowledge: false
        )
        
        var buffer = ""
        let result: Result<AIResult, AIError> = await withCheckedContinuation { cont in
            Task { @MainActor in
                var resumed = false
                AIManager.shared.enqueue(
                    task,
                    completion: { aiResult in
                        if resumed { return }
                        resumed = true
                        if aiResult.success {
                            cont.resume(returning: .success(aiResult))
                        } else {
                            cont.resume(returning: .failure(aiResult.error ?? .processingError("Errore miglioramento relazione")))
                        }
                    },
                    streamCallback: { chunk in
                        Task { @MainActor in
                            buffer += chunk
                            streamCallback(chunk)
                        }
                    }
                )
            }
        }
        
        switch result {
        case .success:
            // Tronca se necessario
            if buffer.count > limiteCaratteri {
                // Cerca l'ultimo punto prima del limite
                let indiceLimite = buffer.index(buffer.startIndex, offsetBy: limiteCaratteri - 3)
                let sottotesto = String(buffer[..<indiceLimite])
                if let ultimoPunto = sottotesto.lastIndex(of: ".") {
                    buffer = String(sottotesto[...ultimoPunto])
                } else if let ultimoSpazio = sottotesto.lastIndex(of: " ") {
                    buffer = String(sottotesto[..<ultimoSpazio]) + "..."
                } else {
                    buffer = sottotesto + "..."
                }
            }
            return .success(buffer)
            
        case .failure(let error):
            return .failure(error)
        }
    }
}

