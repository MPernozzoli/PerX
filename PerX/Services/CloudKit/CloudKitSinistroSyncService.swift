import Foundation
import CloudKit
import CoreData
import Combine

/// Servizio per sincronizzazione completa sinistri via CloudKit
/// - Dati minimi per lista (tutti i sinistri)
/// - Dati completi on-demand (quando si apre un sinistro)
/// - Push automatico su ogni modifica locale
@MainActor
final class CloudKitSinistroSyncService: ObservableObject {
    static let shared = CloudKitSinistroSyncService()
    
    // MARK: - Published State
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var pendingChanges: Int = 0
    
    // MARK: - Stats (monitoraggio)
    @Published private(set) var downloadsInProgress: Int = 0
    @Published private(set) var uploadsInProgress: Int = 0
    @Published private(set) var lastMinimalSyncCount: Int = 0
    @Published private(set) var totalMinimalProcessed: Int = 0
    @Published private(set) var totalMinimalUploaded: Int = 0
    @Published private(set) var totalFullUploaded: Int = 0
    @Published private(set) var lastOwnedFullUploadCount: Int = 0
    
    // MARK: - Error Tracking
    struct SyncError: Identifiable, Codable {
        let id: UUID
        let timestamp: Date
        let type: ErrorType
        let message: String
        let details: String?
        let context: String?
        
        enum ErrorType: String, Codable {
            case pushMinimal = "Push Minimal"
            case pushFull = "Push Full"
            case pushBatch = "Push Batch"
            case pullMinimal = "Pull Minimal"
            case fetchFull = "Fetch Full"
            case query = "Query"
            case save = "Save"
            case other = "Altro"
        }
        
        var fullDescription: String {
            var lines: [String] = []
            lines.append("[\(type.rawValue)] \(message)")
            if let details = details, !details.isEmpty {
                lines.append("Dettagli: \(details)")
            }
            if let context = context, !context.isEmpty {
                lines.append("Contesto: \(context)")
            }
            lines.append("Timestamp: \(DateFormatter.localizedString(from: timestamp, dateStyle: .short, timeStyle: .medium))")
            return lines.joined(separator: "\n")
        }
    }
    
    @Published private(set) var errors: [SyncError] = []
    private static let maxErrorsInSession: Int = 100
    
    var lastError: String? {
        errors.last?.message
    }
    
    // MARK: - Dependencies
    private let container: CKContainer
    private let publicDB: CKDatabase
    private let settings = CloudKitSettingsService.shared
    private var cancellables = Set<AnyCancellable>()
    private var coreDataObserver: NSObjectProtocol?
    private var syncTimer: Timer?
    private var ownedFullUploadTimer: Timer?
    private var isOwnedFullUploadRunning: Bool = false
    
    /// Ogni quanto pushiamo in background i SinistroFull “propri”
    private static let ownedFullUploadInterval: TimeInterval = 5 * 60
    private static let modifyBatchSize: Int = 200
    private static let queryBatchSize: Int = 200
    
    // MARK: - Error Recording
    
    private func recordError(type: SyncError.ErrorType, message: String, details: String? = nil, context: String? = nil) {
        let error = SyncError(
            id: UUID(),
            timestamp: Date(),
            type: type,
            message: message,
            details: details,
            context: context
        )
        errors.append(error)
        // Mantieni solo gli ultimi N errori
        if errors.count > Self.maxErrorsInSession {
            errors.removeFirst(errors.count - Self.maxErrorsInSession)
        }
    }
    
    func clearErrors() {
        errors.removeAll()
    }
    
    // MARK: - Record Types
    private enum RecordType {
        static let sinistroMinimal = "SinistroMinimal"
        static let sinistroFull = "SinistroFull"
        static let perizia = "Perizia"
        static let partita = "Partita"
        static let garanzia = "Garanzia"
        static let bene = "Bene"
        static let voceCosto = "VoceCosto"
        static let coassicurazione = "Coassicurazione"
        static let diarioEntry = "DiarioEntry"
    }
    
    // MARK: - Keys per SinistroMinimal (dati lista)
    private enum MinimalKeys {
        static let riferimento = "riferimento"
        static let stato = "stato"
        static let nomeAssicurato = "nomeAssicurato"
        static let nomeCompagnia = "nomeCompagnia"
        static let gruppo = "gruppo"
        static let area = "area"
        static let dataAssegnazione = "dataAssegnazione"
        static let dataChiusura = "dataChiusura"
        static let assignedToUserEmail = "assignedToUserEmail"
        static let assignedToUserName = "assignedToUserName"
        static let ownerEmail = "ownerEmail"
        static let definizione = "definizione"
        static let stimaDanno = "stimaDanno"
        static let substate = "substate"
        static let fulminazione = "fulminazione"
        static let lastModifiedAt = "lastModifiedAt"
        static let lastModifiedBy = "lastModifiedBy"
        static let version = "version"
        static let hasFullData = "hasFullData"
    }
    
    // MARK: - Keys per SinistroFull (dati completi)
    private enum FullKeys {
        static let riferimento = "riferimento"
        // Dati anagrafici completi
        static let nomeContraente = "nomeContraente"
        static let telefonoContraente = "telefonoContraente"
        static let emailContraente = "emailContraente"
        static let indirizzoContraente = "indirizzoContraente"
        static let nomeAssicurato = "nomeAssicurato"
        static let telefonoAssicurato = "telefonoAssicurato"
        static let emailAssicurato = "emailAssicurato"
        static let indirizzoAssicurato = "indirizzoAssicurato"
        static let nomeDanneggiato = "nomeDanneggiato"
        static let telefonoDanneggiato = "telefonoDanneggiato"
        static let emailDanneggiato = "emailDanneggiato"
        static let indirizzoDanneggiato = "indirizzoDanneggiato"
        // Dati polizza
        static let numeroPolizza = "numeroPolizza"
        static let tipoPolizza = "tipoPolizza"
        static let numeroSinistroCompagnia = "numeroSinistroCompagnia"
        static let codiceAgenzia = "codiceAgenzia"
        static let agenzia = "agenzia"
        static let emailAgenzia = "emailAgenzia"
        static let telefonoAgenzia = "telefonoAgenzia"
        // Date
        static let dataSinistro = "dataSinistro"
        static let dataDenuncia = "dataDenuncia"
        static let dataIncarico = "dataIncarico"
        static let dataSopralluogo = "dataSopralluogo"
        static let dataAperturaGestione = "dataAperturaGestione"
        static let dataInvioAtto = "dataInvioAtto"
        static let dataComunicazioneEsito = "dataComunicazioneEsito"
        static let dataRicezioneAttoSottoscritto = "dataRicezioneAttoSottoscritto"
        static let dataAccettazioneVerbale = "dataAccettazioneVerbale"
        static let dataRevoca = "dataRevoca"
        // Importi
        static let richiesta = "richiesta"
        static let liquidato = "liquidato"
        static let dannoAccertato = "dannoAccertato"
        static let dannoAccertatoNetto = "dannoAccertatoNetto"
        // Flags
        static let sopralluogo = "sopralluogo"
        static let giustificativi = "giustificativi"
        static let oltreDieciBeni = "oltreDieciBeni"
        static let iban = "iban"
        static let concordata = "concordata"
        static let negativa = "negativa"
        static let definizioneManuale = "definizioneManuale"
        // Altri
        static let complessita = "complessita"
        static let propensionePerito = "propensionePerito"
        static let ubicazioneNote = "ubicazioneNote"
        static let ubicazioneValidata = "ubicazioneValidata"
        static let regolaritaAmministrativa = "regolaritaAmministrativa"
        static let dataPagamentoPremio = "dataPagamentoPremio"
        static let codiceFiscaleAssicurato = "codiceFiscaleAssicurato"
        static let partitaIVAAssicurato = "partitaIVAAssicurato"
        static let collegamenti = "collegamenti"
        static let diarioJSON = "diarioJSON"
        static let periziaJSON = "periziaJSON"
        static let coassicurazioniJSON = "coassicurazioniJSON"
        static let perxiaAnalisiJSON = "perxiaAnalisiJSON"
        static let lastModifiedAt = "lastModifiedAt"
    }

    // MARK: - Payload (JSON nel record SinistroFull)

    private struct CoassicurazionePayload: Codable {
        let id: String
        let tipo: String
        let compagnia: String
        let polizza: String
        let numeroSinistro: String
        let ordine: Int
    }

    private struct VoceCostoPayload: Codable {
        let id: String
        let descrizione: String
        let unitaMisura: String
        let quantita: Double
        let valoreUnitario: Double
        let totaleANuovo: Double?
        let percentualeMigliorie: Double?
        let nettoMigliorie: Double?
        let percentualeIllesi: Double?
        let nettoIllesi: Double?
        let vsu: Double?
        let si: Double?
        let indennizzabile: Bool
        let formula: String?
        let ordine: Int
        let campiForzati: [String]?
    }

    private struct BenePayload: Codable {
        let id: String
        let nome: String
        let marca: String?
        let modello: String?
        let numeroSerie: String?
        let anno: Int
        let stimata: Bool
        let relazioneTecnica: String?
        let richiesta: Double?
        let ivaInclusa: Bool
        let ripristiniUltimati: Bool
        let residuiMantenuti: String?
        let sostituzioneIntero: Bool
        let determinazioneDanno: String?
        let deprezzamento: Double
        let aliquotaIVA: Double
        let liquidazioneForzata: Double?
        let ordine: Int
        let vociCosto: [VoceCostoPayload]
    }

    private struct PartitaPayload: Codable {
        let id: String
        let tipoPartita: String
        let nomeFornitoCompagnia: String?
        let nomeEditabile: String
        let tipologia: String
        let valoreAssicurato: Double
        let percentualeDeroga: Double?
        let determinazioneDanno: String
        let regoleSpeciali: String?
        let ordine: Int
        let partitaAcquistata: Bool
        let beni: [BenePayload]
    }

    private struct GaranziaPayload: Codable {
        let id: String
        let tipoGaranzia: String
        let nomeFornitoCompagnia: String?
        let nomeEditabile: String
        let tipologia: String
        let valorePRA: Double?
        let massimale: Double
        let massimaleUnico: Bool
        let franchigiaMinimo: Double?
        let franchigiaMassimo: Double?
        let scopertoPercentuale: Double?
        let scopertoMinimo: Double?
        let scopertoMassimo: Double?
        let ordine: Int
        let beni: [BenePayload]
    }

    private struct PeriziaVersionPayload: Codable {
        let id: String
        let campo: String
        let contenuto: String
        let numeroVersione: Int
        let dataCreazione: Date
    }
    
    // MARK: - PerxiaAnalisi Payload (analisi AI)
    
    private struct PerxiaBenePayload: Codable {
        let id: String
        let tipologia: String
        let componenti: String?
        let modello: String?
        let anno: String?
        let osservazioniVisive: String?
        let valutazioneTest: String?
        let compatibilitaGaranzia: String?
        let compatibilitaDanno: String?
        let stimaEconomica: String?
        let noteAggiuntive: String?
        let tipoBene: String?
        let ordine: Int
        let certezzaTipologia: Double
        let certezzaModello: Double
        let certezzaAnno: Double
        let certezzaOsservazioni: Double
        let certezzaTest: Double
        let certezzaCompatibilita: Double
        let certezzaStima: Double
        let fotoAssociate: [String]?
    }
    
    private struct PerxiaAnalisiPayload: Codable {
        let id: String
        let dataAnalisi: Date?
        let relazioneComplessiva: String?
        let systemPrompt: String?
        let contextSummary: String?
        let beni: [PerxiaBenePayload]
    }

    private struct PeriziaPayload: Codable {
        let id: String
        let descrizioneRischio: String?
        let strutturaPortante: String?
        let tamponamenti: String?
        let ordituraTetto: String?
        let copertura: String?
        let finiture: String?
        let condizioneRischio: String?
        let rischio: String?
        let deprezzamentoFabbricato: Double?
        let numeroPiani: Int
        let annoCostruzione: Int
        let denunciaTardiva: Bool
        let mantenimentoResidui: String?
        let rivalsaPresente: Bool
        let rivalsaNota: String?
        let arrotondamentoLiquidazione: Double?
        let stimaDannoIndennizzabile: Double?
        let vociPersonalizzateJSON: String?
        let relazionePerizia: String?
        let noteConclusive: String?
        let noteRiserva: String?
        let noteOsservazioni: String?
        let hasRiserva: Bool
        let eventoCausatoDa: String?
        let determinazione: String?
        let partite: [PartitaPayload]
        let garanzie: [GaranziaPayload]
        let beniBozza: [BenePayload]
        let versioni: [PeriziaVersionPayload]
    }
    
    // MARK: - Init
    private init(container: CKContainer = CKContainer(identifier: "iCloud.it.pernozzoli.PerX")) {
        self.container = container
        self.publicDB = container.publicCloudDatabase
        
        setupObservers()
    }
    
    private func setupObservers() {
        // Osserva abilitazione sync
        settings.$isEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                if enabled {
                    self?.startBackgroundSync()
                } else {
                    self?.stopBackgroundSync()
                }
            }
            .store(in: &cancellables)
        
        // Osserva modifiche Core Data
        coreDataObserver = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleCoreDataSave(notification)
        }
    }
    
    deinit {
        if let observer = coreDataObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Background Sync
    
    func startBackgroundSync() {
        stopBackgroundSync()
        guard settings.isEnabled else { return }
        
        #if DEBUG
        Task { await ensureSchemaSeedRecords() }
        #endif

        Task { await CPUThrottler.shared.runWithThrottle { await syncAllMinimal() } }
        Task { await CPUThrottler.shared.runWithThrottle { await pushAllOwnedSinistriFull(reason: "start") } }
        
        // Timer per sync periodica (throttle per non intasare CPU)
        syncTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task {
                await CPUThrottler.shared.runWithThrottle { await self?.syncAllMinimal() }
            }
        }
        ownedFullUploadTimer = Timer.scheduledTimer(withTimeInterval: Self.ownedFullUploadInterval, repeats: true) { [weak self] _ in
            Task {
                await CPUThrottler.shared.runWithThrottle { await self?.pushAllOwnedSinistriFull(reason: "timer") }
            }
        }
        
        Task { await CPUThrottler.shared.runWithThrottle { await setupSubscriptions() } }
    }
    
    func stopBackgroundSync() {
        syncTimer?.invalidate()
        syncTimer = nil
        ownedFullUploadTimer?.invalidate()
        ownedFullUploadTimer = nil
    }

    /// Trigger manuale: pull lista minimal + push full sinistri “propri”.
    func syncNow(reason: String = "manual") async {
        guard settings.isEnabled else { return }
        await syncAllMinimal()
        await pushAllOwnedSinistriFull(reason: reason)
    }
    
    // MARK: - Core Data Observer
    
    private func handleCoreDataSave(_ notification: Notification) {
        guard settings.isEnabled else { return }
        guard let context = notification.object as? NSManagedObjectContext else { return }
        
        let inserted = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> ?? []
        let updated = notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject> ?? []
        
        let changedSinistri = (inserted.union(updated))
            .compactMap { $0 as? Sinistro }
            .filter { $0.riferimento != nil && !$0.riferimento!.isEmpty }
        
        guard !changedSinistri.isEmpty else { return }
        
        pendingChanges += changedSinistri.count
        
        // Push asincrono:
        // - sempre Minimal
        // - Full se è “proprio” oppure se l'utente ha modificato un sinistro non proprio (diario/dettagli)
        Task {
            for sinistro in changedSinistri {
                await pushSinistroMinimalOnly(sinistro)
                if self.isOwnedByCurrentUser(sinistro) || self.shouldPushFullForNonOwned(sinistro) {
                    await pushSinistroFullOnly(sinistro)
                }
            }
            await MainActor.run { pendingChanges = max(0, pendingChanges - changedSinistri.count) }
        }
    }
    
    // MARK: - Push Sinistro (Locale → Cloud)
    
    /// Push di un sinistro su CloudKit (dati minimi + full se presente perizia)
    func pushSinistro(_ sinistro: Sinistro) async {
        guard settings.isEnabled else { return }
        guard let riferimento = sinistro.riferimento, !riferimento.isEmpty else { return }
        
        do {
            // Full: per chiamate esplicite usa policy “proprio”
            try await pushSinistroMinimal(sinistro)
            if isOwnedByCurrentUser(sinistro) {
                try await pushSinistroFull(sinistro)
            }
            
            print("[CloudKitSinistro] ✅ Push completo sinistro \(riferimento)")
        } catch {
            print("[CloudKitSinistro] ❌ Errore push sinistro \(riferimento): \(error.localizedDescription)")
            recordError(
                type: .pushFull,
                message: error.localizedDescription,
                details: (error as NSError).localizedFailureReason,
                context: "Push completo sinistro: \(riferimento)"
            )
        }
    }
    
    private func pushSinistroMinimalOnly(_ sinistro: Sinistro) async {
        await MainActor.run { uploadsInProgress += 1 }
        defer { Task { @MainActor in uploadsInProgress = max(0, uploadsInProgress - 1) } }
        do { try await pushSinistroMinimal(sinistro) } catch {
            let rif = sinistro.riferimento ?? "N/A"
            print("[CloudKitSinistro] ❌ Errore push minimal \(rif): \(error.localizedDescription)")
            await MainActor.run {
                recordError(
                    type: .pushMinimal,
                    message: error.localizedDescription,
                    details: (error as NSError).localizedFailureReason,
                    context: "Sinistro: \(rif)"
                )
            }
            return
        }
        await MainActor.run { totalMinimalUploaded += 1 }
    }
    
    private func pushSinistroFullOnly(_ sinistro: Sinistro) async {
        await MainActor.run { uploadsInProgress += 1 }
        defer { Task { @MainActor in uploadsInProgress = max(0, uploadsInProgress - 1) } }
        do { try await pushSinistroFull(sinistro) } catch {
            let rif = sinistro.riferimento ?? "N/A"
            print("[CloudKitSinistro] ❌ Errore push full \(rif): \(error.localizedDescription)")
            await MainActor.run {
                recordError(
                    type: .pushFull,
                    message: error.localizedDescription,
                    details: (error as NSError).localizedFailureReason,
                    context: "Sinistro: \(rif)"
                )
            }
            return
        }
        await MainActor.run { totalFullUploaded += 1 }
    }
    
    private func isOwnedByCurrentUser(_ sinistro: Sinistro) -> Bool {
        let current = GoogleAuthService.shared.userEmail?.lowercased() ?? ""
        guard !current.isEmpty else { return false }
        let assignedOrOwner = (sinistro.assignedToUserEmail ?? sinistro.ownerEmail ?? "").lowercased()
        return !assignedOrOwner.isEmpty && assignedOrOwner == current
    }
    
    /// true se vale la pena pushare il Full anche se non è “proprio”.
    /// Serve per supportare modifiche a diario/dettagli su sinistri altrui.
    private func shouldPushFullForNonOwned(_ sinistro: Sinistro) -> Bool {
        // Se è proprio, gestito sopra
        if isOwnedByCurrentUser(sinistro) { return false }
        
        // Diario modificato/presente
        if !sinistro.diarioArray.isEmpty { return true }
        
        // Perizia presente (utente ha lavorato sul sinistro)
        if sinistro.perizia != nil { return true }
        
        // PerxiaAnalisi presente (analisi AI completata)
        if let analisiSet = sinistro.perxiaAnalisi as? Set<PerxiaAnalisi>, !analisiSet.isEmpty { return true }
        
        // Campi “dettagli” valorizzati
        let hasAnyDetail =
            (sinistro.nomeContraente?.isEmpty == false) ||
            (sinistro.telefonoContraente?.isEmpty == false) ||
            (sinistro.emailContraente?.isEmpty == false) ||
            (sinistro.indirizzoContraente?.isEmpty == false) ||
            (sinistro.telefonoAssicurato?.isEmpty == false) ||
            (sinistro.emailAssicurato?.isEmpty == false) ||
            (sinistro.indirizzoAssicurato?.isEmpty == false) ||
            (sinistro.nomeDanneggiato?.isEmpty == false) ||
            (sinistro.telefonoDanneggiato?.isEmpty == false) ||
            (sinistro.emailDanneggiato?.isEmpty == false) ||
            (sinistro.indirizzoDanneggiato?.isEmpty == false) ||
            (sinistro.numeroPolizza?.isEmpty == false) ||
            (sinistro.tipoPolizza?.isEmpty == false) ||
            (sinistro.codiceAgenzia?.isEmpty == false) ||
            (sinistro.agenzia?.isEmpty == false) ||
            (sinistro.emailAgenzia?.isEmpty == false) ||
            (sinistro.telefonoAgenzia?.isEmpty == false) ||
            (sinistro.complessita?.isEmpty == false) ||
            (sinistro.propensionePerito?.isEmpty == false) ||
            (sinistro.ubicazioneNote?.isEmpty == false) ||
            (sinistro.codiceFiscaleAssicurato?.isEmpty == false) ||
            (sinistro.partitaIVAAssicurato?.isEmpty == false)
        
        if hasAnyDetail { return true }
        
        // Importi / date impostate
        if sinistro.richiesta != nil || sinistro.liquidato != nil || sinistro.dannoAccertato != nil || sinistro.dannoAccertatoNetto != nil { return true }
        if sinistro.dataSinistro != nil || sinistro.dataDenuncia != nil || sinistro.dataIncarico != nil || sinistro.dataSopralluogo != nil { return true }
        
        return false
    }
    
    /// Upload in background di tutti i SinistroFull “propri” (assegnati/owner).
    private func pushAllOwnedSinistriFull(reason: String) async {
        guard settings.isEnabled else { return }
        guard isOwnedFullUploadRunning == false else { return }
        
        let current = GoogleAuthService.shared.userEmail?.lowercased() ?? ""
        guard !current.isEmpty else { return }
        
        isOwnedFullUploadRunning = true
        defer { isOwnedFullUploadRunning = false }
        
        let context = PersistenceController.shared.container.viewContext
        do {
            let sinistri = try await fetchLocalOwnedSinistri(context: context, email: current)
            guard !sinistri.isEmpty else { return }
            
            print("[CloudKitSinistro] ⬆️ Push full owned (\(reason)): \(sinistri.count) sinistri")
            await MainActor.run { lastOwnedFullUploadCount = sinistri.count }
            
            let minimalRecords = sinistri.compactMap { buildSinistroMinimalRecord($0) }
            let fullRecords = sinistri.compactMap { buildSinistroFullRecord($0) }
            
            await MainActor.run { uploadsInProgress += 1 }
            defer { Task { @MainActor in uploadsInProgress = max(0, uploadsInProgress - 1) } }
            
            _ = try await saveRecords(minimalRecords)
            await MainActor.run { totalMinimalUploaded += minimalRecords.count }
            _ = try await saveRecords(fullRecords)
            await MainActor.run { totalFullUploaded += fullRecords.count }
        } catch {
            print("[CloudKitSinistro] ❌ Errore push owned full (\(reason)): \(error.localizedDescription)")
            await MainActor.run {
                recordError(
                    type: .pushBatch,
                    message: error.localizedDescription,
                    details: (error as NSError).localizedFailureReason,
                    context: "Batch owned (\(reason))"
                )
            }
        }
    }
    
    private func fetchLocalOwnedSinistri(context: NSManagedObjectContext, email: String) async throws -> [Sinistro] {
        try await context.perform {
            let req = NSFetchRequest<Sinistro>(entityName: "Sinistro")
            req.predicate = NSPredicate(format: "assignedToUserEmail ==[c] %@ OR ownerEmail ==[c] %@", email, email)
            return try context.fetch(req)
        }
    }
    
    private func buildSinistroMinimalRecord(_ sinistro: Sinistro) -> CKRecord? {
        guard let riferimento = sinistro.riferimento, !riferimento.isEmpty else { return nil }
        
        let recordID = CKRecord.ID(recordName: "minimal_\(riferimento)")
        let record = CKRecord(recordType: RecordType.sinistroMinimal, recordID: recordID)
        
        record[MinimalKeys.riferimento] = riferimento as CKRecordValue
        record[MinimalKeys.stato] = (sinistro.stato ?? "") as CKRecordValue
        record[MinimalKeys.nomeAssicurato] = (sinistro.nomeAssicurato ?? "") as CKRecordValue
        record[MinimalKeys.nomeCompagnia] = (sinistro.nomeCompagnia ?? "") as CKRecordValue
        record[MinimalKeys.gruppo] = (sinistro.gruppo ?? "") as CKRecordValue
        record[MinimalKeys.area] = (sinistro.area ?? "") as CKRecordValue
        if let d = sinistro.dataAssegnazione {
            record[MinimalKeys.dataAssegnazione] = d as CKRecordValue
        } else {
            // Non serializzare placeholder (es. 1/1/0001) per date opzionali
            record[MinimalKeys.dataAssegnazione] = nil
        }
        if let dataChiusura = sinistro.dataChiusura {
            record[MinimalKeys.dataChiusura] = dataChiusura as CKRecordValue
        }
        record[MinimalKeys.assignedToUserEmail] = (sinistro.assignedToUserEmail ?? "") as CKRecordValue
        record[MinimalKeys.assignedToUserName] = (sinistro.assignedToUserName ?? "") as CKRecordValue
        record[MinimalKeys.ownerEmail] = (sinistro.ownerEmail ?? "") as CKRecordValue
        record[MinimalKeys.definizione] = (sinistro.definizione ?? "") as CKRecordValue
        record[MinimalKeys.substate] = (sinistro.substate ?? "") as CKRecordValue
        record[MinimalKeys.fulminazione] = (sinistro.fulminazione ?? "") as CKRecordValue
        if let stimaDanno = sinistro.stimaDanno?.doubleValue {
            record[MinimalKeys.stimaDanno] = stimaDanno as CKRecordValue
        }
        
        let now = Date()
        record[MinimalKeys.lastModifiedAt] = now as CKRecordValue
        record[MinimalKeys.lastModifiedBy] = (GoogleAuthService.shared.userEmail ?? "") as CKRecordValue
        record[MinimalKeys.hasFullData] = true as CKRecordValue
        record[MinimalKeys.version] = Int(now.timeIntervalSince1970) as CKRecordValue
        
        return record
    }
    
    private func pushSinistroMinimal(_ sinistro: Sinistro) async throws {
        guard let record = buildSinistroMinimalRecord(sinistro) else { return }
        try await upsertRecordResolvingConflicts(record, sinistro: sinistro)
    }
    
    private func buildSinistroFullRecord(_ sinistro: Sinistro) -> CKRecord? {
        guard let riferimento = sinistro.riferimento, !riferimento.isEmpty else { return nil }
        
        let recordID = CKRecord.ID(recordName: "full_\(riferimento)")
        let record = CKRecord(recordType: RecordType.sinistroFull, recordID: recordID)
        record[FullKeys.riferimento] = riferimento as CKRecordValue
        
        // Anagrafica
        record[FullKeys.nomeContraente] = (sinistro.nomeContraente ?? "") as CKRecordValue
        record[FullKeys.telefonoContraente] = (sinistro.telefonoContraente ?? "") as CKRecordValue
        record[FullKeys.emailContraente] = (sinistro.emailContraente ?? "") as CKRecordValue
        record[FullKeys.indirizzoContraente] = (sinistro.indirizzoContraente ?? "") as CKRecordValue
        record[FullKeys.nomeAssicurato] = (sinistro.nomeAssicurato ?? "") as CKRecordValue
        record[FullKeys.telefonoAssicurato] = (sinistro.telefonoAssicurato ?? "") as CKRecordValue
        record[FullKeys.emailAssicurato] = (sinistro.emailAssicurato ?? "") as CKRecordValue
        record[FullKeys.indirizzoAssicurato] = (sinistro.indirizzoAssicurato ?? "") as CKRecordValue
        record[FullKeys.nomeDanneggiato] = (sinistro.nomeDanneggiato ?? "") as CKRecordValue
        record[FullKeys.telefonoDanneggiato] = (sinistro.telefonoDanneggiato ?? "") as CKRecordValue
        record[FullKeys.emailDanneggiato] = (sinistro.emailDanneggiato ?? "") as CKRecordValue
        record[FullKeys.indirizzoDanneggiato] = (sinistro.indirizzoDanneggiato ?? "") as CKRecordValue
        
        // Polizza
        record[FullKeys.numeroPolizza] = (sinistro.numeroPolizza ?? "") as CKRecordValue
        record[FullKeys.tipoPolizza] = (sinistro.tipoPolizza ?? "") as CKRecordValue
        record[FullKeys.numeroSinistroCompagnia] = (sinistro.numeroSinistroCompagnia ?? "") as CKRecordValue
        record[FullKeys.codiceAgenzia] = (sinistro.codiceAgenzia ?? "") as CKRecordValue
        record[FullKeys.agenzia] = (sinistro.agenzia ?? "") as CKRecordValue
        record[FullKeys.emailAgenzia] = (sinistro.emailAgenzia ?? "") as CKRecordValue
        record[FullKeys.telefonoAgenzia] = (sinistro.telefonoAgenzia ?? "") as CKRecordValue
        
        // Date
        if let d = sinistro.dataSinistro { record[FullKeys.dataSinistro] = d as CKRecordValue }
        if let d = sinistro.dataDenuncia { record[FullKeys.dataDenuncia] = d as CKRecordValue }
        if let d = sinistro.dataIncarico { record[FullKeys.dataIncarico] = d as CKRecordValue }
        if let d = sinistro.dataSopralluogo { record[FullKeys.dataSopralluogo] = d as CKRecordValue }
        if let d = sinistro.dataAperturaGestione { record[FullKeys.dataAperturaGestione] = d as CKRecordValue }
        if let d = sinistro.dataInvioAtto { record[FullKeys.dataInvioAtto] = d as CKRecordValue }
        if let d = sinistro.dataComunicazioneEsito { record[FullKeys.dataComunicazioneEsito] = d as CKRecordValue }
        if let d = sinistro.dataRicezioneAttoSottoscritto { record[FullKeys.dataRicezioneAttoSottoscritto] = d as CKRecordValue }
        if let d = sinistro.dataAccettazioneVerbale { record[FullKeys.dataAccettazioneVerbale] = d as CKRecordValue }
        if let d = sinistro.dataRevoca { record[FullKeys.dataRevoca] = d as CKRecordValue }
        
        // Importi
        if let v = sinistro.richiesta?.doubleValue { record[FullKeys.richiesta] = v as CKRecordValue }
        if let v = sinistro.liquidato?.doubleValue { record[FullKeys.liquidato] = v as CKRecordValue }
        if let v = sinistro.dannoAccertato?.doubleValue { record[FullKeys.dannoAccertato] = v as CKRecordValue }
        if let v = sinistro.dannoAccertatoNetto?.doubleValue { record[FullKeys.dannoAccertatoNetto] = v as CKRecordValue }
        
        // Flags
        record[FullKeys.sopralluogo] = sinistro.sopralluogo as CKRecordValue
        record[FullKeys.giustificativi] = sinistro.giustificativi as CKRecordValue
        record[FullKeys.oltreDieciBeni] = sinistro.oltreDieciBeni as CKRecordValue
        record[FullKeys.iban] = sinistro.iban as CKRecordValue
        record[FullKeys.concordata] = sinistro.concordata as CKRecordValue
        record[FullKeys.negativa] = sinistro.negativa as CKRecordValue
        record[FullKeys.definizioneManuale] = sinistro.definizioneManuale as CKRecordValue
        record[FullKeys.ubicazioneValidata] = sinistro.ubicazioneValidata as CKRecordValue
        
        // Altri
        record[FullKeys.complessita] = (sinistro.complessita ?? "") as CKRecordValue
        record[FullKeys.propensionePerito] = (sinistro.propensionePerito ?? "") as CKRecordValue
        record[FullKeys.ubicazioneNote] = (sinistro.ubicazioneNote ?? "") as CKRecordValue
        record[FullKeys.codiceFiscaleAssicurato] = (sinistro.codiceFiscaleAssicurato ?? "") as CKRecordValue
        record[FullKeys.partitaIVAAssicurato] = (sinistro.partitaIVAAssicurato ?? "") as CKRecordValue
        
        if let regolarita = sinistro.regolaritaAmministrativa?.boolValue {
            record[FullKeys.regolaritaAmministrativa] = regolarita as CKRecordValue
        }
        if let d = sinistro.dataPagamentoPremio { record[FullKeys.dataPagamentoPremio] = d as CKRecordValue }
        
        // Collegamenti (come JSON array)
        let collegamentiArray = Array(sinistro.collegamentiSet)
        if let data = try? JSONEncoder().encode(collegamentiArray) {
            record[FullKeys.collegamenti] = String(data: data, encoding: .utf8) as CKRecordValue?
        }
        
        // Diario (come JSON)
        if let data = try? JSONEncoder().encode(sinistro.diarioArray) {
            record[FullKeys.diarioJSON] = String(data: data, encoding: .utf8) as CKRecordValue?
        }

        // Coassicurazioni (come JSON)
        let coassPayload: [CoassicurazionePayload] = sinistro.coassicurazioniArray.map { c in
            CoassicurazionePayload(
                id: c.wrappedId.uuidString,
                tipo: c.tipo,
                compagnia: c.compagnia,
                polizza: c.polizza,
                numeroSinistro: c.numeroSinistro,
                ordine: Int(c.ordine)
            )
        }
        if let data = try? JSONEncoder().encode(coassPayload) {
            record[FullKeys.coassicurazioniJSON] = String(data: data, encoding: .utf8) as CKRecordValue?
        }

        // Perizia + calcoli (come JSON)
        if let perizia = sinistro.perizia {
            let payload = PeriziaPayload(
                id: perizia.wrappedId.uuidString,
                descrizioneRischio: perizia.descrizioneRischio,
                strutturaPortante: perizia.strutturaPortante,
                tamponamenti: perizia.tamponamenti,
                ordituraTetto: perizia.ordituraTetto,
                copertura: perizia.copertura,
                finiture: perizia.finiture,
                condizioneRischio: perizia.condizioneRischio,
                rischio: perizia.rischio,
                deprezzamentoFabbricato: perizia.deprezzamentoFabbricato?.doubleValue,
                numeroPiani: Int(perizia.numeroPiani),
                annoCostruzione: Int(perizia.annoCostruzione),
                denunciaTardiva: perizia.denunciaTardiva,
                mantenimentoResidui: perizia.mantenimentoResidui,
                rivalsaPresente: perizia.rivalsaPresente,
                rivalsaNota: perizia.rivalsaNota,
                arrotondamentoLiquidazione: perizia.arrotondamentoLiquidazione?.doubleValue,
                stimaDannoIndennizzabile: perizia.stimaDannoIndennizzabile?.doubleValue,
                vociPersonalizzateJSON: perizia.vociPersonalizzateJSON,
                relazionePerizia: perizia.relazionePerizia,
                noteConclusive: perizia.noteConclusive,
                noteRiserva: perizia.noteRiserva,
                noteOsservazioni: perizia.noteOsservazioni,
                hasRiserva: perizia.hasRiserva,
                eventoCausatoDa: perizia.eventoCausatoDa,
                determinazione: perizia.determinazione,
                partite: perizia.partiteArray.map { p in
                    PartitaPayload(
                        id: p.wrappedId.uuidString,
                        tipoPartita: p.tipoPartita,
                        nomeFornitoCompagnia: p.nomeFornitoCompagnia,
                        nomeEditabile: p.nomeEditabile,
                        tipologia: p.tipologia,
                        valoreAssicurato: p.valoreAssicurato.doubleValue,
                        percentualeDeroga: p.percentualeDeroga?.doubleValue,
                        determinazioneDanno: p.determinazioneDanno,
                        regoleSpeciali: p.regoleSpeciali,
                        ordine: Int(p.ordine),
                        partitaAcquistata: p.partitaAcquistata,
                        beni: p.beniArray.map { b in
                            BenePayload(
                                id: b.wrappedId.uuidString,
                                nome: b.nome,
                                marca: b.marca,
                                modello: b.modello,
                                numeroSerie: b.numeroSerie,
                                anno: Int(b.anno),
                                stimata: b.stimata,
                                relazioneTecnica: b.relazioneTecnica,
                                richiesta: b.richiesta?.doubleValue,
                                ivaInclusa: b.ivaInclusa,
                                ripristiniUltimati: b.ripristiniUltimati,
                                residuiMantenuti: b.residuiMantenuti,
                                sostituzioneIntero: b.sostituzioneIntero,
                                determinazioneDanno: b.determinazioneDanno,
                                deprezzamento: b.deprezzamento,
                                aliquotaIVA: b.aliquotaIVA,
                                liquidazioneForzata: b.liquidazioneForzata?.doubleValue,
                                ordine: Int(b.ordine),
                                vociCosto: b.vociCostoArray.map { v in
                                    VoceCostoPayload(
                                        id: v.wrappedId.uuidString,
                                        descrizione: v.descrizione,
                                        unitaMisura: v.unitaMisura,
                                        quantita: v.quantita.doubleValue,
                                        valoreUnitario: v.valoreUnitario.doubleValue,
                                        totaleANuovo: v.totaleANuovo?.doubleValue,
                                        percentualeMigliorie: v.percentualeMigliorie?.doubleValue,
                                        nettoMigliorie: v.nettoMigliorie?.doubleValue,
                                        percentualeIllesi: v.percentualeIllesi?.doubleValue,
                                        nettoIllesi: v.nettoIllesi?.doubleValue,
                                        vsu: v.vsu?.doubleValue,
                                        si: v.si?.doubleValue,
                                        indennizzabile: v.indennizzabile,
                                        formula: v.formula,
                                        ordine: Int(v.ordine),
                                        campiForzati: Array(v.campiForzatiSet)
                                    )
                                }
                            )
                        }
                    )
                },
                garanzie: perizia.garanzieArray.compactMap { g in
                    guard let gId = g.id else { return nil }
                    return GaranziaPayload(
                        id: gId.uuidString,
                        tipoGaranzia: g.tipoGaranzia,
                        nomeFornitoCompagnia: g.nomeFornitoCompagnia,
                        nomeEditabile: g.nomeEditabile,
                        tipologia: g.tipologia,
                        valorePRA: g.valorePRA?.doubleValue,
                        massimale: g.massimale.doubleValue,
                        massimaleUnico: g.massimaleUnico,
                        franchigiaMinimo: g.franchigiaMinimo?.doubleValue,
                        franchigiaMassimo: g.franchigiaMassimo?.doubleValue,
                        scopertoPercentuale: g.scopertoPercentuale?.doubleValue,
                        scopertoMinimo: g.scopertoMinimo?.doubleValue,
                        scopertoMassimo: g.scopertoMassimo?.doubleValue,
                        ordine: Int(g.ordine),
                        beni: g.beniArray.compactMap { b in
                            guard let bId = b.id else { return nil }
                            return BenePayload(
                                id: bId.uuidString,
                                nome: b.nome,
                                marca: b.marca,
                                modello: b.modello,
                                numeroSerie: b.numeroSerie,
                                anno: Int(b.anno),
                                stimata: b.stimata,
                                relazioneTecnica: b.relazioneTecnica,
                                richiesta: b.richiesta?.doubleValue,
                                ivaInclusa: b.ivaInclusa,
                                ripristiniUltimati: b.ripristiniUltimati,
                                residuiMantenuti: b.residuiMantenuti,
                                sostituzioneIntero: b.sostituzioneIntero,
                                determinazioneDanno: b.determinazioneDanno,
                                deprezzamento: b.deprezzamento,
                                aliquotaIVA: b.aliquotaIVA,
                                liquidazioneForzata: b.liquidazioneForzata?.doubleValue,
                                ordine: Int(b.ordine),
                                vociCosto: b.vociCostoArray.map { v in
                                    VoceCostoPayload(
                                        id: v.wrappedId.uuidString,
                                        descrizione: v.descrizione,
                                        unitaMisura: v.unitaMisura,
                                        quantita: v.quantita.doubleValue,
                                        valoreUnitario: v.valoreUnitario.doubleValue,
                                        totaleANuovo: v.totaleANuovo?.doubleValue,
                                        percentualeMigliorie: v.percentualeMigliorie?.doubleValue,
                                        nettoMigliorie: v.nettoMigliorie?.doubleValue,
                                        percentualeIllesi: v.percentualeIllesi?.doubleValue,
                                        nettoIllesi: v.nettoIllesi?.doubleValue,
                                        vsu: v.vsu?.doubleValue,
                                        si: v.si?.doubleValue,
                                        indennizzabile: v.indennizzabile,
                                        formula: v.formula,
                                        ordine: Int(v.ordine),
                                        campiForzati: Array(v.campiForzatiSet)
                                    )
                                }
                            )
                        }
                    )
                },
                beniBozza: perizia.beniBozzaArray.compactMap { b in
                    guard let bId = b.id else { return nil }
                    return BenePayload(
                        id: bId.uuidString,
                        nome: b.nome,
                        marca: b.marca,
                        modello: b.modello,
                        numeroSerie: b.numeroSerie,
                        anno: Int(b.anno),
                        stimata: b.stimata,
                        relazioneTecnica: b.relazioneTecnica,
                        richiesta: b.richiesta?.doubleValue,
                        ivaInclusa: b.ivaInclusa,
                        ripristiniUltimati: b.ripristiniUltimati,
                        residuiMantenuti: b.residuiMantenuti,
                        sostituzioneIntero: b.sostituzioneIntero,
                        determinazioneDanno: b.determinazioneDanno,
                        deprezzamento: b.deprezzamento,
                        aliquotaIVA: b.aliquotaIVA,
                        liquidazioneForzata: b.liquidazioneForzata?.doubleValue,
                        ordine: Int(b.ordine),
                        vociCosto: b.vociCostoArray.compactMap { v in
                            guard let vId = v.id else { return nil }
                            return VoceCostoPayload(
                                id: vId.uuidString,
                                descrizione: v.descrizione,
                                unitaMisura: v.unitaMisura,
                                quantita: v.quantita.doubleValue,
                                valoreUnitario: v.valoreUnitario.doubleValue,
                                totaleANuovo: v.totaleANuovo?.doubleValue,
                                percentualeMigliorie: v.percentualeMigliorie?.doubleValue,
                                nettoMigliorie: v.nettoMigliorie?.doubleValue,
                                percentualeIllesi: v.percentualeIllesi?.doubleValue,
                                nettoIllesi: v.nettoIllesi?.doubleValue,
                                vsu: v.vsu?.doubleValue,
                                si: v.si?.doubleValue,
                                indennizzabile: v.indennizzabile,
                                formula: v.formula,
                                ordine: Int(v.ordine),
                                campiForzati: Array(v.campiForzatiSet)
                            )
                        }
                    )
                },
                versioni: perizia.versioniArray.compactMap { pv in
                    guard let pvId = pv.id else { return nil }
                    return PeriziaVersionPayload(
                        id: pvId.uuidString,
                        campo: pv.campo,
                        contenuto: pv.contenuto,
                        numeroVersione: Int(pv.numeroVersione),
                        dataCreazione: pv.dataCreazione
                    )
                }
            )

            if let data = try? JSONEncoder().encode(payload) {
                record[FullKeys.periziaJSON] = String(data: data, encoding: .utf8) as CKRecordValue?
            }
        } else {
            record[FullKeys.periziaJSON] = nil
        }
        
        // PerxiaAnalisi (analisi AI)
        if let analisiSet = sinistro.perxiaAnalisi as? Set<PerxiaAnalisi>,
           let analisi = analisiSet.sorted(by: { ($0.dataAnalisi ?? .distantPast) > ($1.dataAnalisi ?? .distantPast) }).first,
           let analisiId = analisi.id {
            let beniPayload: [PerxiaBenePayload] = (analisi.beni as? Set<PerxiaBene> ?? [])
                .sorted(by: { $0.ordine < $1.ordine })
                .compactMap { bene in
                    guard let beneId = bene.id else { return nil }
                    return PerxiaBenePayload(
                        id: beneId.uuidString,
                        tipologia: bene.tipologia ?? "",
                        componenti: bene.componenti,
                        modello: bene.modello,
                        anno: bene.anno,
                        osservazioniVisive: bene.osservazioniVisive,
                        valutazioneTest: bene.valutazioneTest,
                        compatibilitaGaranzia: bene.compatibilitaGaranzia,
                        compatibilitaDanno: bene.compatibilitaDanno,
                        stimaEconomica: bene.stimaEconomica,
                        noteAggiuntive: bene.noteAggiuntive,
                        tipoBene: bene.tipoBene,
                        ordine: Int(bene.ordine),
                        certezzaTipologia: bene.certezzaTipologia,
                        certezzaModello: bene.certezzaModello,
                        certezzaAnno: bene.certezzaAnno,
                        certezzaOsservazioni: bene.certezzaOsservazioni,
                        certezzaTest: bene.certezzaTest,
                        certezzaCompatibilita: bene.certezzaCompatibilita,
                        certezzaStima: bene.certezzaStima,
                        fotoAssociate: bene.fotoAssociate as? [String]
                    )
                }
            
            let analisiPayload = PerxiaAnalisiPayload(
                id: analisiId.uuidString,
                dataAnalisi: analisi.dataAnalisi,
                relazioneComplessiva: analisi.relazioneComplessiva,
                systemPrompt: analisi.systemPrompt,
                contextSummary: analisi.contextSummary,
                beni: beniPayload
            )
            
            if let data = try? JSONEncoder().encode(analisiPayload) {
                record[FullKeys.perxiaAnalisiJSON] = String(data: data, encoding: .utf8) as CKRecordValue?
            }
        } else {
            record[FullKeys.perxiaAnalisiJSON] = nil
        }
        
        record[FullKeys.lastModifiedAt] = Date() as CKRecordValue
        return record
    }
    
    private func pushSinistroFull(_ sinistro: Sinistro) async throws {
        guard let record = buildSinistroFullRecord(sinistro) else { return }
        try await upsertRecordResolvingConflicts(record, sinistro: sinistro)
    }
    
    private func pushDiarioEntry(_ entry: DiarioEntry, riferimento: String) async throws {
        let recordID = CKRecord.ID(recordName: "diario_\(entry.id.uuidString)")
        let record = (try? await fetchRecord(recordID)) ?? CKRecord(recordType: RecordType.diarioEntry, recordID: recordID)
        
        record["entryId"] = entry.id.uuidString as CKRecordValue
        record["sinistroRiferimento"] = riferimento as CKRecordValue
        record["timestamp"] = entry.timestamp as CKRecordValue
        record["tipo"] = entry.tipo.rawValue as CKRecordValue
        record["titolo"] = (entry.titolo ?? "") as CKRecordValue
        record["riassunto"] = (entry.riassunto ?? entry.testo) as CKRecordValue
        record["contenutoCompleto"] = (entry.contenutoCompleto ?? entry.testo) as CKRecordValue
        record["createdBy"] = (entry.createdByEmail ?? GoogleAuthService.shared.userEmail ?? "") as CKRecordValue
        
        _ = try await saveRecord(record)
    }
    
    private func pushCoassicurazione(_ coass: Coassicurazione, riferimento: String) async throws {
        guard let coassId = coass.id else { return }
        let recordID = CKRecord.ID(recordName: "coass_\(coassId.uuidString)")
        let record = (try? await fetchRecord(recordID)) ?? CKRecord(recordType: RecordType.coassicurazione, recordID: recordID)
        
        record["coassId"] = coassId.uuidString as CKRecordValue
        record["sinistroRiferimento"] = riferimento as CKRecordValue
        record["tipo"] = coass.tipo as CKRecordValue
        record["compagnia"] = coass.compagnia as CKRecordValue
        record["polizza"] = coass.polizza as CKRecordValue
        record["numeroSinistro"] = coass.numeroSinistro as CKRecordValue
        record["ordine"] = Int(coass.ordine) as CKRecordValue
        
        _ = try await saveRecord(record)
    }
    
    // MARK: - Push Perizia
    
    private func pushPerizia(_ perizia: Perizia, riferimento: String) async throws {
        guard let periziaId = perizia.id else { return }
        let recordID = CKRecord.ID(recordName: "perizia_\(periziaId.uuidString)")
        let record = (try? await fetchRecord(recordID)) ?? CKRecord(recordType: RecordType.perizia, recordID: recordID)
        
        record["periziaId"] = periziaId.uuidString as CKRecordValue
        record["sinistroRiferimento"] = riferimento as CKRecordValue
        record["descrizioneRischio"] = (perizia.descrizioneRischio ?? "") as CKRecordValue
        record["strutturaPortante"] = (perizia.strutturaPortante ?? "") as CKRecordValue
        record["tamponamenti"] = (perizia.tamponamenti ?? "") as CKRecordValue
        record["ordituraTetto"] = (perizia.ordituraTetto ?? "") as CKRecordValue
        record["copertura"] = (perizia.copertura ?? "") as CKRecordValue
        record["finiture"] = (perizia.finiture ?? "") as CKRecordValue
        record["condizioneRischio"] = (perizia.condizioneRischio ?? "") as CKRecordValue
        record["rischio"] = (perizia.rischio ?? "") as CKRecordValue
        record["numeroPiani"] = Int(perizia.numeroPiani) as CKRecordValue
        record["annoCostruzione"] = Int(perizia.annoCostruzione) as CKRecordValue
        record["denunciaTardiva"] = perizia.denunciaTardiva as CKRecordValue
        record["mantenimentoResidui"] = (perizia.mantenimentoResidui ?? "") as CKRecordValue
        record["rivalsaPresente"] = perizia.rivalsaPresente as CKRecordValue
        record["rivalsaNota"] = (perizia.rivalsaNota ?? "") as CKRecordValue
        record["relazionePerizia"] = (perizia.relazionePerizia ?? "") as CKRecordValue
        record["noteConclusive"] = (perizia.noteConclusive ?? "") as CKRecordValue
        record["noteRiserva"] = (perizia.noteRiserva ?? "") as CKRecordValue
        record["noteOsservazioni"] = (perizia.noteOsservazioni ?? "") as CKRecordValue
        record["hasRiserva"] = perizia.hasRiserva as CKRecordValue
        record["eventoCausatoDa"] = (perizia.eventoCausatoDa ?? "") as CKRecordValue
        record["determinazione"] = (perizia.determinazione ?? "") as CKRecordValue
        record["vociPersonalizzateJSON"] = (perizia.vociPersonalizzateJSON ?? "") as CKRecordValue
        
        if let v = perizia.deprezzamentoFabbricato?.doubleValue { record["deprezzamentoFabbricato"] = v as CKRecordValue }
        if let v = perizia.arrotondamentoLiquidazione?.doubleValue { record["arrotondamentoLiquidazione"] = v as CKRecordValue }
        if let v = perizia.stimaDannoIndennizzabile?.doubleValue { record["stimaDannoIndennizzabile"] = v as CKRecordValue }
        
        _ = try await saveRecord(record)
        
        // Push partite
        for partita in perizia.partiteArray {
            try await pushPartita(partita, periziaId: periziaId.uuidString)
        }
        
        // Push garanzie
        for garanzia in perizia.garanzieArray {
            try await pushGaranzia(garanzia, periziaId: periziaId.uuidString)
        }
    }
    
    private func pushPartita(_ partita: Partita, periziaId: String) async throws {
        guard let partitaId = partita.id else { return }
        let recordID = CKRecord.ID(recordName: "partita_\(partitaId.uuidString)")
        let record = (try? await fetchRecord(recordID)) ?? CKRecord(recordType: RecordType.partita, recordID: recordID)
        
        record["partitaId"] = partitaId.uuidString as CKRecordValue
        record["periziaId"] = periziaId as CKRecordValue
        record["tipoPartita"] = partita.tipoPartita as CKRecordValue
        record["nomeFornitoCompagnia"] = (partita.nomeFornitoCompagnia ?? "") as CKRecordValue
        record["nomeEditabile"] = partita.nomeEditabile as CKRecordValue
        record["tipologia"] = partita.tipologia as CKRecordValue
        record["valoreAssicurato"] = partita.valoreAssicurato.doubleValue as CKRecordValue
        record["determinazioneDanno"] = partita.determinazioneDanno as CKRecordValue
        record["regoleSpeciali"] = (partita.regoleSpeciali ?? "") as CKRecordValue
        record["ordine"] = Int(partita.ordine) as CKRecordValue
        record["partitaAcquistata"] = partita.partitaAcquistata as CKRecordValue
        if let v = partita.percentualeDeroga?.doubleValue { record["percentualeDeroga"] = v as CKRecordValue }
        
        _ = try await saveRecord(record)
        
        // Push beni della partita
        for bene in partita.beniArray {
            try await pushBene(bene, partitaId: partitaId.uuidString, garanziaId: nil)
        }
    }
    
    private func pushGaranzia(_ garanzia: Garanzia, periziaId: String) async throws {
        guard let garanziaId = garanzia.id else { return }
        let recordID = CKRecord.ID(recordName: "garanzia_\(garanziaId.uuidString)")
        let record = (try? await fetchRecord(recordID)) ?? CKRecord(recordType: RecordType.garanzia, recordID: recordID)
        
        record["garanziaId"] = garanziaId.uuidString as CKRecordValue
        record["periziaId"] = periziaId as CKRecordValue
        record["tipoGaranzia"] = garanzia.tipoGaranzia as CKRecordValue
        record["nomeFornitoCompagnia"] = (garanzia.nomeFornitoCompagnia ?? "") as CKRecordValue
        record["nomeEditabile"] = garanzia.nomeEditabile as CKRecordValue
        record["tipologia"] = garanzia.tipologia as CKRecordValue
        record["massimale"] = garanzia.massimale.doubleValue as CKRecordValue
        record["massimaleUnico"] = garanzia.massimaleUnico as CKRecordValue
        record["ordine"] = Int(garanzia.ordine) as CKRecordValue
        if let v = garanzia.valorePRA?.doubleValue { record["valorePRA"] = v as CKRecordValue }
        if let v = garanzia.franchigiaMinimo?.doubleValue { record["franchigiaMinimo"] = v as CKRecordValue }
        if let v = garanzia.franchigiaMassimo?.doubleValue { record["franchigiaMassimo"] = v as CKRecordValue }
        if let v = garanzia.scopertoPercentuale?.doubleValue { record["scopertoPercentuale"] = v as CKRecordValue }
        if let v = garanzia.scopertoMinimo?.doubleValue { record["scopertoMinimo"] = v as CKRecordValue }
        if let v = garanzia.scopertoMassimo?.doubleValue { record["scopertoMassimo"] = v as CKRecordValue }
        
        _ = try await saveRecord(record)
        
        // Push beni della garanzia
        for bene in garanzia.beniArray {
            try await pushBene(bene, partitaId: nil, garanziaId: garanziaId.uuidString)
        }
    }
    
    private func pushBene(_ bene: Bene, partitaId: String?, garanziaId: String?) async throws {
        guard let beneId = bene.id else { return }
        let recordID = CKRecord.ID(recordName: "bene_\(beneId.uuidString)")
        let record = (try? await fetchRecord(recordID)) ?? CKRecord(recordType: RecordType.bene, recordID: recordID)
        
        record["beneId"] = beneId.uuidString as CKRecordValue
        if let pid = partitaId { record["partitaId"] = pid as CKRecordValue }
        if let gid = garanziaId { record["garanziaId"] = gid as CKRecordValue }
        record["nome"] = bene.nome as CKRecordValue
        record["marca"] = (bene.marca ?? "") as CKRecordValue
        record["modello"] = (bene.modello ?? "") as CKRecordValue
        record["numeroSerie"] = (bene.numeroSerie ?? "") as CKRecordValue
        record["anno"] = Int(bene.anno) as CKRecordValue
        record["stimata"] = bene.stimata as CKRecordValue
        record["relazioneTecnica"] = (bene.relazioneTecnica ?? "") as CKRecordValue
        record["ivaInclusa"] = bene.ivaInclusa as CKRecordValue
        record["ripristiniUltimati"] = bene.ripristiniUltimati as CKRecordValue
        record["residuiMantenuti"] = (bene.residuiMantenuti ?? "") as CKRecordValue
        record["sostituzioneIntero"] = bene.sostituzioneIntero as CKRecordValue
        record["determinazioneDanno"] = (bene.determinazioneDanno ?? "") as CKRecordValue
        record["deprezzamento"] = bene.deprezzamento as CKRecordValue
        record["aliquotaIVA"] = bene.aliquotaIVA as CKRecordValue
        record["ordine"] = Int(bene.ordine) as CKRecordValue
        if let v = bene.richiesta?.doubleValue { record["richiesta"] = v as CKRecordValue }
        if let v = bene.liquidazioneForzata?.doubleValue { record["liquidazioneForzata"] = v as CKRecordValue }
        
        _ = try await saveRecord(record)
        
        // Push voci costo
        for voce in bene.vociCostoArray {
            try await pushVoceCosto(voce, beneId: beneId.uuidString)
        }
    }
    
    private func pushVoceCosto(_ voce: VoceCosto, beneId: String) async throws {
        guard let voceId = voce.id else { return }
        let recordID = CKRecord.ID(recordName: "voce_\(voceId.uuidString)")
        let record = (try? await fetchRecord(recordID)) ?? CKRecord(recordType: RecordType.voceCosto, recordID: recordID)
        
        record["voceId"] = voceId.uuidString as CKRecordValue
        record["beneId"] = beneId as CKRecordValue
        record["descrizione"] = voce.descrizione as CKRecordValue
        record["unitaMisura"] = voce.unitaMisura as CKRecordValue
        record["quantita"] = voce.quantita.doubleValue as CKRecordValue
        record["valoreUnitario"] = voce.valoreUnitario.doubleValue as CKRecordValue
        record["ordine"] = Int(voce.ordine) as CKRecordValue
        record["indennizzabile"] = voce.indennizzabile as CKRecordValue
        record["formula"] = (voce.formula ?? "") as CKRecordValue
        if let v = voce.totaleANuovo?.doubleValue { record["totaleANuovo"] = v as CKRecordValue }
        if let v = voce.percentualeMigliorie?.doubleValue { record["percentualeMigliorie"] = v as CKRecordValue }
        if let v = voce.nettoMigliorie?.doubleValue { record["nettoMigliorie"] = v as CKRecordValue }
        if let v = voce.percentualeIllesi?.doubleValue { record["percentualeIllesi"] = v as CKRecordValue }
        if let v = voce.nettoIllesi?.doubleValue { record["nettoIllesi"] = v as CKRecordValue }
        if let v = voce.vsu?.doubleValue { record["vsu"] = v as CKRecordValue }
        if let v = voce.si?.doubleValue { record["si"] = v as CKRecordValue }
        
        _ = try await saveRecord(record)
    }
    
    // MARK: - Pull Sinistri (Cloud → Locale)
    
    /// Scarica tutti i dati minimi dei sinistri (per lista)
    func syncAllMinimal() async {
        guard settings.isEnabled else { return }
        guard !isSyncing else { return }
        
        isSyncing = true
        downloadsInProgress += 1
        defer { isSyncing = false; lastSyncAt = Date() }
        defer { downloadsInProgress = max(0, downloadsInProgress - 1) }
        
        do {
            // Evita query su recordName (system field): usiamo un campo nostro indicizzabile
            let query = CKQuery(
                recordType: RecordType.sinistroMinimal,
                predicate: NSPredicate(format: "%K > %@", MinimalKeys.lastModifiedAt, Date.distantPast as NSDate)
            )
            query.sortDescriptors = [NSSortDescriptor(key: MinimalKeys.lastModifiedAt, ascending: false)]
            
            let records = try await performQuery(query)
            lastMinimalSyncCount = records.count
            totalMinimalProcessed += records.count
            let context = PersistenceController.shared.container.viewContext
            
            try await context.perform {
                for record in records {
                    self.applyMinimalRecord(record, context: context)
                }
                if context.hasChanges {
                    try context.save()
                }
            }
            
            print("[CloudKitSinistro] ✅ Sync minimal completata: \(records.count) sinistri")
        } catch {
            print("[CloudKitSinistro] ❌ Errore sync minimal: \(error.localizedDescription)")
            recordError(
                type: .pullMinimal,
                message: error.localizedDescription,
                details: (error as NSError).localizedFailureReason,
                context: "Query tutti sinistri"
            )
        }
    }
    
    private func applyMinimalRecord(_ record: CKRecord, context: NSManagedObjectContext) {
        guard let riferimento = record[MinimalKeys.riferimento] as? String, !riferimento.isEmpty else { return }
        guard riferimento.hasPrefix("__schema_") == false else { return }
        
        // Non ricreare sinistri che sono stati eliminati localmente
        if DeletedSinistriTracker.shared.isDeleted(riferimento: riferimento) {
            print("[CloudKitSinistro] ⏭️ Sinistro \(riferimento) ignorato (eliminato localmente)")
            return
        }
        
        let fetchRequest = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        fetchRequest.predicate = NSPredicate(format: "riferimento == %@", riferimento)
        fetchRequest.fetchLimit = 1
        
        let sinistro: Sinistro
        if let existing = try? context.fetch(fetchRequest).first {
            // Confronta versioni
            let remoteModified = (record[MinimalKeys.lastModifiedAt] as? Date) ?? Date.distantPast
            let localModified = existing.cloudKitLastModified ?? Date.distantPast
            
            // Se locale è più recente, non sovrascrivere
            if localModified > remoteModified { return }
            sinistro = existing
        } else {
            sinistro = Sinistro(context: context)
            sinistro.riferimento = riferimento
        }
        
        // Applica solo i campi minimi
        sinistro.stato = record[MinimalKeys.stato] as? String
        sinistro.nomeAssicurato = record[MinimalKeys.nomeAssicurato] as? String
        sinistro.nomeCompagnia = record[MinimalKeys.nomeCompagnia] as? String
        sinistro.gruppo = record[MinimalKeys.gruppo] as? String
        sinistro.area = record[MinimalKeys.area] as? String
        let remoteDataAssegnazione = record[MinimalKeys.dataAssegnazione] as? Date
        if let remoteDataAssegnazione, remoteDataAssegnazione == Date.distantPast {
            // Ripulisci record legacy che usavano .distantPast come sentinel
            sinistro.dataAssegnazione = nil
        } else {
            sinistro.dataAssegnazione = remoteDataAssegnazione
        }
        sinistro.dataChiusura = record[MinimalKeys.dataChiusura] as? Date
        sinistro.assignedToUserEmail = record[MinimalKeys.assignedToUserEmail] as? String
        sinistro.assignedToUserName = record[MinimalKeys.assignedToUserName] as? String
        sinistro.ownerEmail = record[MinimalKeys.ownerEmail] as? String
        sinistro.definizione = record[MinimalKeys.definizione] as? String
        sinistro.substate = record[MinimalKeys.substate] as? String
        sinistro.fulminazione = record[MinimalKeys.fulminazione] as? String
        if let stimaDanno = record[MinimalKeys.stimaDanno] as? Double {
            sinistro.stimaDanno = NSDecimalNumber(value: stimaDanno)
        }
        
        sinistro.cloudKitRecordID = record.recordID.recordName
        sinistro.cloudKitLastModified = record[MinimalKeys.lastModifiedAt] as? Date
    }

    #if DEBUG
    /// Best-effort: prova a creare i record type/fields in Development (JIT schema).
    /// Se l'ambiente è Production o lo schema è locked, fallisce senza impattare la sync.
    private func ensureSchemaSeedRecords() async {
        let seedRif = "__schema_seed__"
        let now = Date()

        do {
            let minimalID = CKRecord.ID(recordName: "minimal_\(seedRif)")
            let minimal = CKRecord(recordType: RecordType.sinistroMinimal, recordID: minimalID)
            minimal[MinimalKeys.riferimento] = seedRif as CKRecordValue
            minimal[MinimalKeys.stato] = "schema" as CKRecordValue
            minimal[MinimalKeys.nomeAssicurato] = "" as CKRecordValue
            minimal[MinimalKeys.nomeCompagnia] = "" as CKRecordValue
            minimal[MinimalKeys.gruppo] = "" as CKRecordValue
            minimal[MinimalKeys.area] = "" as CKRecordValue
            minimal[MinimalKeys.dataAssegnazione] = now as CKRecordValue
            minimal[MinimalKeys.assignedToUserEmail] = "" as CKRecordValue
            minimal[MinimalKeys.assignedToUserName] = "" as CKRecordValue
            minimal[MinimalKeys.ownerEmail] = "" as CKRecordValue
            minimal[MinimalKeys.definizione] = "" as CKRecordValue
            minimal[MinimalKeys.substate] = "" as CKRecordValue
            minimal[MinimalKeys.fulminazione] = "" as CKRecordValue
            minimal[MinimalKeys.lastModifiedAt] = now as CKRecordValue
            minimal[MinimalKeys.lastModifiedBy] = "schema" as CKRecordValue
            minimal[MinimalKeys.version] = 1 as CKRecordValue
            minimal[MinimalKeys.hasFullData] = true as CKRecordValue
            _ = try await saveRecord(minimal)
        } catch {
            // ignore
        }

        do {
            let fullID = CKRecord.ID(recordName: "full_\(seedRif)")
            let full = CKRecord(recordType: RecordType.sinistroFull, recordID: fullID)
            full[FullKeys.riferimento] = seedRif as CKRecordValue
            full[FullKeys.lastModifiedAt] = now as CKRecordValue
            // set campi stringa vuoti per “riservare” lo schema
            full[FullKeys.nomeContraente] = "" as CKRecordValue
            full[FullKeys.nomeAssicurato] = "" as CKRecordValue
            full[FullKeys.nomeDanneggiato] = "" as CKRecordValue
            full[FullKeys.numeroPolizza] = "" as CKRecordValue
            full[FullKeys.tipoPolizza] = "" as CKRecordValue
            full[FullKeys.numeroSinistroCompagnia] = "" as CKRecordValue
            full[FullKeys.codiceAgenzia] = "" as CKRecordValue
            full[FullKeys.agenzia] = "" as CKRecordValue
            full[FullKeys.emailAgenzia] = "" as CKRecordValue
            full[FullKeys.telefonoAgenzia] = "" as CKRecordValue
            full[FullKeys.collegamenti] = "[]" as CKRecordValue
            full[FullKeys.diarioJSON] = "[]" as CKRecordValue
            full[FullKeys.coassicurazioniJSON] = "[]" as CKRecordValue
            full[FullKeys.perxiaAnalisiJSON] = nil as CKRecordValue?
            _ = try await saveRecord(full)
        } catch {
            // ignore
        }
    }
    #endif
    
    /// Scarica i dati completi di un sinistro (on-demand quando si apre)
    func fetchFullSinistro(riferimento: String) async {
        guard settings.isEnabled else { return }
        
        do {
            // Fetch dati completi sinistro (include perizia/coass/diario in JSON)
            let fullRecordID = CKRecord.ID(recordName: "full_\(riferimento)")
            if let fullRecord = try? await fetchRecord(fullRecordID) {
                let context = PersistenceController.shared.container.viewContext
                try await context.perform {
                    self.applyFullRecord(fullRecord, context: context)
                    if context.hasChanges { try context.save() }
                }
            }
            print("[CloudKitSinistro] ✅ Fetch completo sinistro \(riferimento)")
        } catch {
            print("[CloudKitSinistro] ❌ Errore fetch completo \(riferimento): \(error.localizedDescription)")
            await MainActor.run {
                recordError(
                    type: .fetchFull,
                    message: error.localizedDescription,
                    details: (error as NSError).localizedFailureReason,
                    context: "Sinistro: \(riferimento)"
                )
            }
        }
    }
    
    private func applyFullRecord(_ record: CKRecord, context: NSManagedObjectContext) {
        guard let riferimento = record[FullKeys.riferimento] as? String, !riferimento.isEmpty else { return }
        
        let fetchRequest = NSFetchRequest<Sinistro>(entityName: "Sinistro")
        fetchRequest.predicate = NSPredicate(format: "riferimento == %@", riferimento)
        fetchRequest.fetchLimit = 1
        
        guard let sinistro = try? context.fetch(fetchRequest).first else { return }
        
        let remoteModified = record.modificationDate ?? .distantPast
        let localModified = sinistro.cloudKitLastModified ?? .distantPast
        if localModified > remoteModified {
            return
        }
        
        // Anagrafica completa
        sinistro.nomeContraente = record[FullKeys.nomeContraente] as? String
        sinistro.telefonoContraente = record[FullKeys.telefonoContraente] as? String
        sinistro.emailContraente = record[FullKeys.emailContraente] as? String
        sinistro.indirizzoContraente = record[FullKeys.indirizzoContraente] as? String
        sinistro.nomeAssicurato = record[FullKeys.nomeAssicurato] as? String
        sinistro.telefonoAssicurato = record[FullKeys.telefonoAssicurato] as? String
        sinistro.emailAssicurato = record[FullKeys.emailAssicurato] as? String
        sinistro.indirizzoAssicurato = record[FullKeys.indirizzoAssicurato] as? String
        sinistro.nomeDanneggiato = record[FullKeys.nomeDanneggiato] as? String
        sinistro.telefonoDanneggiato = record[FullKeys.telefonoDanneggiato] as? String
        sinistro.emailDanneggiato = record[FullKeys.emailDanneggiato] as? String
        sinistro.indirizzoDanneggiato = record[FullKeys.indirizzoDanneggiato] as? String
        
        // Polizza
        sinistro.numeroPolizza = record[FullKeys.numeroPolizza] as? String
        sinistro.tipoPolizza = record[FullKeys.tipoPolizza] as? String
        sinistro.numeroSinistroCompagnia = record[FullKeys.numeroSinistroCompagnia] as? String
        sinistro.codiceAgenzia = record[FullKeys.codiceAgenzia] as? String
        sinistro.agenzia = record[FullKeys.agenzia] as? String
        sinistro.emailAgenzia = record[FullKeys.emailAgenzia] as? String
        sinistro.telefonoAgenzia = record[FullKeys.telefonoAgenzia] as? String
        
        // Date
        // Nota: il fetch "full" è on-demand quando si apre il dettaglio.
        // Qui NON dobbiamo mai cancellare/retrocedere dati locali inseriti (es. da Import).
        // Quindi: riempiamo solo i campi mancanti.
        if sinistro.dataSinistro == nil, let d = record[FullKeys.dataSinistro] as? Date { sinistro.dataSinistro = d }
        if sinistro.dataDenuncia == nil, let d = record[FullKeys.dataDenuncia] as? Date { sinistro.dataDenuncia = d }
        if sinistro.dataIncarico == nil, let d = record[FullKeys.dataIncarico] as? Date { sinistro.dataIncarico = d }
        if sinistro.dataSopralluogo == nil, let d = record[FullKeys.dataSopralluogo] as? Date { sinistro.dataSopralluogo = d }
        if sinistro.dataAperturaGestione == nil, let d = record[FullKeys.dataAperturaGestione] as? Date { sinistro.dataAperturaGestione = d }
        if sinistro.dataInvioAtto == nil, let d = record[FullKeys.dataInvioAtto] as? Date { sinistro.dataInvioAtto = d }
        if sinistro.dataComunicazioneEsito == nil, let d = record[FullKeys.dataComunicazioneEsito] as? Date { sinistro.dataComunicazioneEsito = d }
        if sinistro.dataRicezioneAttoSottoscritto == nil, let d = record[FullKeys.dataRicezioneAttoSottoscritto] as? Date { sinistro.dataRicezioneAttoSottoscritto = d }
        if sinistro.dataAccettazioneVerbale == nil, let d = record[FullKeys.dataAccettazioneVerbale] as? Date { sinistro.dataAccettazioneVerbale = d }
        if sinistro.dataRevoca == nil, let d = record[FullKeys.dataRevoca] as? Date { sinistro.dataRevoca = d }
        
        // Importi
        if let v = record[FullKeys.richiesta] as? Double { sinistro.richiesta = NSDecimalNumber(value: v) }
        if let v = record[FullKeys.liquidato] as? Double { sinistro.liquidato = NSDecimalNumber(value: v) }
        if let v = record[FullKeys.dannoAccertato] as? Double { sinistro.dannoAccertato = NSDecimalNumber(value: v) }
        if let v = record[FullKeys.dannoAccertatoNetto] as? Double { sinistro.dannoAccertatoNetto = NSDecimalNumber(value: v) }
        
        // Flags
        sinistro.sopralluogo = record[FullKeys.sopralluogo] as? Bool ?? false
        sinistro.giustificativi = record[FullKeys.giustificativi] as? Bool ?? false
        sinistro.oltreDieciBeni = record[FullKeys.oltreDieciBeni] as? Bool ?? false
        sinistro.iban = record[FullKeys.iban] as? Bool ?? false
        sinistro.concordata = record[FullKeys.concordata] as? Bool ?? false
        sinistro.negativa = record[FullKeys.negativa] as? Bool ?? false
        sinistro.definizioneManuale = record[FullKeys.definizioneManuale] as? Bool ?? false
        sinistro.ubicazioneValidata = record[FullKeys.ubicazioneValidata] as? Bool ?? false
        
        // Altri
        sinistro.complessita = record[FullKeys.complessita] as? String
        sinistro.propensionePerito = record[FullKeys.propensionePerito] as? String
        sinistro.ubicazioneNote = record[FullKeys.ubicazioneNote] as? String
        sinistro.codiceFiscaleAssicurato = record[FullKeys.codiceFiscaleAssicurato] as? String
        sinistro.partitaIVAAssicurato = record[FullKeys.partitaIVAAssicurato] as? String
        
        if let regolarita = record[FullKeys.regolaritaAmministrativa] as? Bool {
            sinistro.regolaritaAmministrativa = NSNumber(value: regolarita)
        }
        sinistro.dataPagamentoPremio = record[FullKeys.dataPagamentoPremio] as? Date
        
        // Collegamenti
        if let json = record[FullKeys.collegamenti] as? String,
           let data = json.data(using: .utf8),
           let array = try? JSONDecoder().decode([String].self, from: data) {
            sinistro.collegamentiSet = Set(array)
        }

        // Diario (merge per id)
        if let json = record[FullKeys.diarioJSON] as? String,
           let data = json.data(using: .utf8),
           let remoteEntries = try? JSONDecoder().decode([DiarioEntry].self, from: data) {
            var merged: [UUID: DiarioEntry] = [:]
            for e in sinistro.diarioArray { merged[e.id] = e }
            for e in remoteEntries { merged[e.id] = e }
            let mergedArray = Array(merged.values).sorted { $0.timestamp < $1.timestamp }
            sinistro.diarioArray = mergedArray
        }

        // Coassicurazioni
        if let json = record[FullKeys.coassicurazioniJSON] as? String,
           let data = json.data(using: .utf8),
           let payload = try? JSONDecoder().decode([CoassicurazionePayload].self, from: data) {
            let existing = sinistro.coassicurazioniArray
            let keepIDs = Set(payload.compactMap { UUID(uuidString: $0.id) })
            for c in existing {
                if let cId = c.id, !keepIDs.contains(cId) {
                    context.delete(c)
                }
            }
            for p in payload {
                guard let id = UUID(uuidString: p.id) else { continue }
                let obj: Coassicurazione
                if let found = existing.first(where: { $0.id == id }) {
                    obj = found
                } else {
                    obj = Coassicurazione(context: context)
                    obj.id = id
                    sinistro.addToCoassicurazioni(obj)
                }
                obj.tipo = p.tipo
                obj.compagnia = p.compagnia
                obj.polizza = p.polizza
                obj.numeroSinistro = p.numeroSinistro
                obj.ordine = Int16(p.ordine)
            }
        }

        // Perizia + calcoli
        if let json = record[FullKeys.periziaJSON] as? String,
           let data = json.data(using: .utf8),
           let payload = try? JSONDecoder().decode(PeriziaPayload.self, from: data),
           let periziaId = UUID(uuidString: payload.id) {
            let perizia: Perizia
            if let existing = sinistro.perizia, existing.id == periziaId {
                perizia = existing
            } else {
                perizia = sinistro.perizia ?? Perizia(context: context)
                perizia.id = periziaId
                sinistro.perizia = perizia
            }

            perizia.descrizioneRischio = payload.descrizioneRischio
            perizia.strutturaPortante = payload.strutturaPortante
            perizia.tamponamenti = payload.tamponamenti
            perizia.ordituraTetto = payload.ordituraTetto
            perizia.copertura = payload.copertura
            perizia.finiture = payload.finiture
            perizia.condizioneRischio = payload.condizioneRischio
            perizia.rischio = payload.rischio
            perizia.deprezzamentoFabbricato = payload.deprezzamentoFabbricato.map { NSDecimalNumber(value: $0) }
            perizia.numeroPiani = Int16(payload.numeroPiani)
            perizia.annoCostruzione = Int16(payload.annoCostruzione)
            perizia.denunciaTardiva = payload.denunciaTardiva
            perizia.mantenimentoResidui = payload.mantenimentoResidui
            perizia.rivalsaPresente = payload.rivalsaPresente
            perizia.rivalsaNota = payload.rivalsaNota
            perizia.arrotondamentoLiquidazione = payload.arrotondamentoLiquidazione.map { NSDecimalNumber(value: $0) }
            perizia.stimaDannoIndennizzabile = payload.stimaDannoIndennizzabile.map { NSDecimalNumber(value: $0) }
            perizia.vociPersonalizzateJSON = payload.vociPersonalizzateJSON
            perizia.relazionePerizia = payload.relazionePerizia
            perizia.noteConclusive = payload.noteConclusive
            perizia.noteRiserva = payload.noteRiserva
            perizia.noteOsservazioni = payload.noteOsservazioni
            perizia.hasRiserva = payload.hasRiserva
            perizia.eventoCausatoDa = payload.eventoCausatoDa
            perizia.determinazione = payload.determinazione

            // Partite
            let existingPartite = perizia.partiteArray
            let keepPartite = Set(payload.partite.compactMap { UUID(uuidString: $0.id) })
            for p in existingPartite { if let pId = p.id, !keepPartite.contains(pId) { context.delete(p) } }
            for p in payload.partite {
                guard let pid = UUID(uuidString: p.id) else { continue }
                let obj: Partita
                if let found = existingPartite.first(where: { $0.id == pid }) {
                    obj = found
                } else {
                    obj = Partita(context: context)
                    obj.id = pid
                    perizia.addToPartite(obj)
                }
                obj.tipoPartita = p.tipoPartita
                obj.nomeFornitoCompagnia = p.nomeFornitoCompagnia
                obj.nomeEditabile = p.nomeEditabile
                obj.tipologia = p.tipologia
                obj.valoreAssicurato = NSDecimalNumber(value: p.valoreAssicurato)
                obj.percentualeDeroga = p.percentualeDeroga.map { NSDecimalNumber(value: $0) }
                obj.determinazioneDanno = p.determinazioneDanno
                obj.regoleSpeciali = p.regoleSpeciali
                obj.ordine = Int16(p.ordine)
                obj.partitaAcquistata = p.partitaAcquistata

                // Beni (partita)
                let existingBeni = obj.beniArray
                let keepBeni = Set(p.beni.compactMap { UUID(uuidString: $0.id) })
                for b in existingBeni { if let bId = b.id, !keepBeni.contains(bId) { context.delete(b) } }
                for b in p.beni {
                    guard let bid = UUID(uuidString: b.id) else { continue }
                    let bene: Bene
                    if let foundB = existingBeni.first(where: { $0.id == bid }) {
                        bene = foundB
                    } else {
                        bene = Bene(context: context)
                        bene.id = bid
                        obj.addToBeni(bene)
                    }
                    applyBenePayload(b, to: bene, context: context)
                }
            }

            // Garanzie
            let existingGaranzie = perizia.garanzieArray
            let keepGaranzie = Set(payload.garanzie.compactMap { UUID(uuidString: $0.id) })
            for g in existingGaranzie { if let gId = g.id, !keepGaranzie.contains(gId) { context.delete(g) } }
            for g in payload.garanzie {
                guard let gid = UUID(uuidString: g.id) else { continue }
                let obj: Garanzia
                if let found = existingGaranzie.first(where: { $0.id == gid }) {
                    obj = found
                } else {
                    obj = Garanzia(context: context)
                    obj.id = gid
                    perizia.addToGaranzie(obj)
                }
                obj.tipoGaranzia = g.tipoGaranzia
                obj.nomeFornitoCompagnia = g.nomeFornitoCompagnia
                obj.nomeEditabile = g.nomeEditabile
                obj.tipologia = g.tipologia
                obj.valorePRA = g.valorePRA.map { NSDecimalNumber(value: $0) }
                obj.massimale = NSDecimalNumber(value: g.massimale)
                obj.massimaleUnico = g.massimaleUnico
                obj.franchigiaMinimo = g.franchigiaMinimo.map { NSDecimalNumber(value: $0) }
                obj.franchigiaMassimo = g.franchigiaMassimo.map { NSDecimalNumber(value: $0) }
                obj.scopertoPercentuale = g.scopertoPercentuale.map { NSDecimalNumber(value: $0) }
                obj.scopertoMinimo = g.scopertoMinimo.map { NSDecimalNumber(value: $0) }
                obj.scopertoMassimo = g.scopertoMassimo.map { NSDecimalNumber(value: $0) }
                obj.ordine = Int16(g.ordine)

                // Beni (garanzia)
                let existingBeni = obj.beniArray
                let keepBeni = Set(g.beni.compactMap { UUID(uuidString: $0.id) })
                for b in existingBeni { if let bId = b.id, !keepBeni.contains(bId) { context.delete(b) } }
                for b in g.beni {
                    guard let bid = UUID(uuidString: b.id) else { continue }
                    let bene: Bene
                    if let foundB = existingBeni.first(where: { $0.id == bid }) {
                        bene = foundB
                    } else {
                        bene = Bene(context: context)
                        bene.id = bid
                        obj.addToBeni(bene)
                    }
                    applyBenePayload(b, to: bene, context: context)
                }
            }

            // Beni bozza
            let existingBozza = perizia.beniBozzaArray
            let keepBozza = Set(payload.beniBozza.compactMap { UUID(uuidString: $0.id) })
            for b in existingBozza { if let bId = b.id, !keepBozza.contains(bId) { context.delete(b) } }
            for b in payload.beniBozza {
                guard let bid = UUID(uuidString: b.id) else { continue }
                let bene: Bene
                if let found = existingBozza.first(where: { $0.id == bid }) {
                    bene = found
                } else {
                    bene = Bene(context: context)
                    bene.id = bid
                    // relazione bozza
                    bene.periziaBozza = perizia
                }
                applyBenePayload(b, to: bene, context: context)
            }

            // Versioni perizia
            let existingVersioni = perizia.versioniArray
            let keepVersioni = Set(payload.versioni.compactMap { UUID(uuidString: $0.id) })
            for v in existingVersioni { if let vId = v.id, !keepVersioni.contains(vId) { context.delete(v) } }
            for v in payload.versioni {
                guard let vid = UUID(uuidString: v.id) else { continue }
                let obj: PeriziaVersion
                if let found = existingVersioni.first(where: { $0.id == vid }) {
                    obj = found
                } else {
                    obj = PeriziaVersion(context: context)
                    obj.id = vid
                    obj.perizia = perizia
                }
                obj.campo = v.campo
                obj.contenuto = v.contenuto
                obj.numeroVersione = Int16(v.numeroVersione)
                obj.dataCreazione = v.dataCreazione
            }
        }
        
        // PerxiaAnalisi (analisi AI)
        if let json = record[FullKeys.perxiaAnalisiJSON] as? String,
           let data = json.data(using: .utf8),
           let payload = try? JSONDecoder().decode(PerxiaAnalisiPayload.self, from: data),
           let analisiId = UUID(uuidString: payload.id) {
            
            // Cerca o crea PerxiaAnalisi
            let existingAnalisi = (sinistro.perxiaAnalisi as? Set<PerxiaAnalisi>)?
                .first(where: { $0.id == analisiId })
            
            let perxiaAnalisi: PerxiaAnalisi
            if let existing = existingAnalisi {
                perxiaAnalisi = existing
            } else {
                perxiaAnalisi = PerxiaAnalisi(context: context)
                perxiaAnalisi.id = analisiId
                sinistro.addToPerxiaAnalisi(perxiaAnalisi)
            }
            
            perxiaAnalisi.dataAnalisi = payload.dataAnalisi
            perxiaAnalisi.relazioneComplessiva = payload.relazioneComplessiva
            perxiaAnalisi.systemPrompt = payload.systemPrompt
            perxiaAnalisi.contextSummary = payload.contextSummary
            
            // Beni analisi
            let existingBeni = (perxiaAnalisi.beni as? Set<PerxiaBene>) ?? []
            let keepBeni = Set(payload.beni.compactMap { UUID(uuidString: $0.id) })
            for b in existingBeni { if let bId = b.id, !keepBeni.contains(bId) { context.delete(b) } }
            
            for b in payload.beni {
                guard let bid = UUID(uuidString: b.id) else { continue }
                let bene: PerxiaBene
                if let found = existingBeni.first(where: { $0.id == bid }) {
                    bene = found
                } else {
                    bene = PerxiaBene(context: context)
                    bene.id = bid
                    bene.analisi = perxiaAnalisi
                }
                
                bene.tipologia = b.tipologia
                bene.componenti = b.componenti
                bene.modello = b.modello
                bene.anno = b.anno
                bene.osservazioniVisive = b.osservazioniVisive
                bene.valutazioneTest = b.valutazioneTest
                bene.compatibilitaGaranzia = b.compatibilitaGaranzia
                bene.compatibilitaDanno = b.compatibilitaDanno
                bene.stimaEconomica = b.stimaEconomica
                bene.noteAggiuntive = b.noteAggiuntive
                bene.tipoBene = b.tipoBene
                bene.ordine = Int16(b.ordine)
                bene.certezzaTipologia = b.certezzaTipologia
                bene.certezzaModello = b.certezzaModello
                bene.certezzaAnno = b.certezzaAnno
                bene.certezzaOsservazioni = b.certezzaOsservazioni
                bene.certezzaTest = b.certezzaTest
                bene.certezzaCompatibilita = b.certezzaCompatibilita
                bene.certezzaStima = b.certezzaStima
                bene.fotoAssociate = b.fotoAssociate
            }
        }
    }

    private func applyBenePayload(_ b: BenePayload, to bene: Bene, context: NSManagedObjectContext) {
        bene.nome = b.nome
        bene.marca = b.marca
        bene.modello = b.modello
        bene.numeroSerie = b.numeroSerie
        bene.anno = Int16(b.anno)
        bene.stimata = b.stimata
        bene.relazioneTecnica = b.relazioneTecnica
        bene.richiesta = b.richiesta.map { NSDecimalNumber(value: $0) }
        bene.ivaInclusa = b.ivaInclusa
        bene.ripristiniUltimati = b.ripristiniUltimati
        bene.residuiMantenuti = b.residuiMantenuti
        bene.sostituzioneIntero = b.sostituzioneIntero
        bene.determinazioneDanno = b.determinazioneDanno
        bene.deprezzamento = b.deprezzamento
        bene.aliquotaIVA = b.aliquotaIVA
        bene.liquidazioneForzata = b.liquidazioneForzata.map { NSDecimalNumber(value: $0) }
        bene.ordine = Int16(b.ordine)

        // Voci costo
        let existing = bene.vociCostoArray
        let keep = Set(b.vociCosto.compactMap { UUID(uuidString: $0.id) })
        for v in existing { if let vId = v.id, !keep.contains(vId) { context.delete(v) } }
        for v in b.vociCosto {
            guard let vid = UUID(uuidString: v.id) else { continue }
            let obj: VoceCosto
            if let found = existing.first(where: { $0.id == vid }) {
                obj = found
            } else {
                obj = VoceCosto(context: context)
                obj.id = vid
                bene.addToVociCosto(obj)
            }
            obj.descrizione = v.descrizione
            obj.unitaMisura = v.unitaMisura
            obj.quantita = NSDecimalNumber(value: v.quantita)
            obj.valoreUnitario = NSDecimalNumber(value: v.valoreUnitario)
            obj.totaleANuovo = v.totaleANuovo.map { NSDecimalNumber(value: $0) }
            obj.percentualeMigliorie = v.percentualeMigliorie.map { NSDecimalNumber(value: $0) }
            obj.nettoMigliorie = v.nettoMigliorie.map { NSDecimalNumber(value: $0) }
            obj.percentualeIllesi = v.percentualeIllesi.map { NSDecimalNumber(value: $0) }
            obj.nettoIllesi = v.nettoIllesi.map { NSDecimalNumber(value: $0) }
            obj.vsu = v.vsu.map { NSDecimalNumber(value: $0) }
            obj.si = v.si.map { NSDecimalNumber(value: $0) }
            obj.indennizzabile = v.indennizzabile
            obj.formula = v.formula
            obj.ordine = Int16(v.ordine)
            obj.campiForzatiSet = Set(v.campiForzati ?? [])
        }
    }
    
    private func applyPeriziaRecord(_ record: CKRecord, riferimento: String) async throws {
        guard let periziaIdStr = record["periziaId"] as? String,
              let periziaId = UUID(uuidString: periziaIdStr) else { return }
        
        let context = PersistenceController.shared.container.viewContext
        
        try await context.perform {
            // Trova il sinistro
            let fetchSinistro = NSFetchRequest<Sinistro>(entityName: "Sinistro")
            fetchSinistro.predicate = NSPredicate(format: "riferimento == %@", riferimento)
            fetchSinistro.fetchLimit = 1
            guard let sinistro = try? context.fetch(fetchSinistro).first else { return }
            
            // Trova o crea perizia
            let perizia: Perizia
            if let existing = sinistro.perizia, existing.id == periziaId {
                perizia = existing
            } else {
                perizia = Perizia(context: context)
                perizia.id = periziaId
                sinistro.perizia = perizia
            }
            
            // Applica campi
            perizia.descrizioneRischio = record["descrizioneRischio"] as? String
            perizia.strutturaPortante = record["strutturaPortante"] as? String
            perizia.tamponamenti = record["tamponamenti"] as? String
            perizia.ordituraTetto = record["ordituraTetto"] as? String
            perizia.copertura = record["copertura"] as? String
            perizia.finiture = record["finiture"] as? String
            perizia.condizioneRischio = record["condizioneRischio"] as? String
            perizia.rischio = record["rischio"] as? String
            perizia.numeroPiani = Int16(record["numeroPiani"] as? Int ?? 0)
            perizia.annoCostruzione = Int16(record["annoCostruzione"] as? Int ?? 0)
            perizia.denunciaTardiva = record["denunciaTardiva"] as? Bool ?? false
            perizia.mantenimentoResidui = record["mantenimentoResidui"] as? String
            perizia.rivalsaPresente = record["rivalsaPresente"] as? Bool ?? false
            perizia.rivalsaNota = record["rivalsaNota"] as? String
            perizia.relazionePerizia = record["relazionePerizia"] as? String
            perizia.noteConclusive = record["noteConclusive"] as? String
            perizia.noteRiserva = record["noteRiserva"] as? String
            perizia.noteOsservazioni = record["noteOsservazioni"] as? String
            perizia.hasRiserva = record["hasRiserva"] as? Bool ?? false
            perizia.eventoCausatoDa = record["eventoCausatoDa"] as? String
            perizia.determinazione = record["determinazione"] as? String
            perizia.vociPersonalizzateJSON = record["vociPersonalizzateJSON"] as? String
            
            if let v = record["deprezzamentoFabbricato"] as? Double { perizia.deprezzamentoFabbricato = NSDecimalNumber(value: v) }
            if let v = record["arrotondamentoLiquidazione"] as? Double { perizia.arrotondamentoLiquidazione = NSDecimalNumber(value: v) }
            if let v = record["stimaDannoIndennizzabile"] as? Double { perizia.stimaDannoIndennizzabile = NSDecimalNumber(value: v) }
            
            if context.hasChanges { try context.save() }
        }
        
        // Fetch e applica partite
        let partiteQuery = CKQuery(recordType: RecordType.partita, predicate: NSPredicate(format: "periziaId == %@", periziaIdStr))
        let partiteRecords = try await performQuery(partiteQuery)
        for partitaRecord in partiteRecords {
            try await applyPartitaRecord(partitaRecord, periziaId: periziaId)
        }
        
        // Fetch e applica garanzie
        let garanzieQuery = CKQuery(recordType: RecordType.garanzia, predicate: NSPredicate(format: "periziaId == %@", periziaIdStr))
        let garanzieRecords = try await performQuery(garanzieQuery)
        for garanziaRecord in garanzieRecords {
            try await applyGaranziaRecord(garanziaRecord, periziaId: periziaId)
        }
    }
    
    private func applyPartitaRecord(_ record: CKRecord, periziaId: UUID) async throws {
        guard let partitaIdStr = record["partitaId"] as? String,
              let partitaId = UUID(uuidString: partitaIdStr) else { return }
        
        let context = PersistenceController.shared.container.viewContext
        
        try await context.perform {
            let fetchPerizia = NSFetchRequest<Perizia>(entityName: "Perizia")
            fetchPerizia.predicate = NSPredicate(format: "id == %@", periziaId as CVarArg)
            fetchPerizia.fetchLimit = 1
            guard let perizia = try? context.fetch(fetchPerizia).first else { return }
            
            let partita: Partita
            if let existing = perizia.partiteArray.first(where: { $0.id == partitaId }) {
                partita = existing
            } else {
                partita = Partita(context: context)
                partita.id = partitaId
                perizia.addToPartite(partita)
            }
            
            partita.tipoPartita = record["tipoPartita"] as? String ?? ""
            partita.nomeFornitoCompagnia = record["nomeFornitoCompagnia"] as? String
            partita.nomeEditabile = record["nomeEditabile"] as? String ?? ""
            partita.tipologia = record["tipologia"] as? String ?? ""
            partita.valoreAssicurato = NSDecimalNumber(value: record["valoreAssicurato"] as? Double ?? 0)
            partita.determinazioneDanno = record["determinazioneDanno"] as? String ?? ""
            partita.regoleSpeciali = record["regoleSpeciali"] as? String
            partita.ordine = Int16(record["ordine"] as? Int ?? 0)
            partita.partitaAcquistata = record["partitaAcquistata"] as? Bool ?? true
            if let v = record["percentualeDeroga"] as? Double { partita.percentualeDeroga = NSDecimalNumber(value: v) }
            
            if context.hasChanges { try context.save() }
        }
        
        // Fetch e applica beni della partita
        let beniQuery = CKQuery(recordType: RecordType.bene, predicate: NSPredicate(format: "partitaId == %@", partitaIdStr))
        let beniRecords = try await performQuery(beniQuery)
        for beneRecord in beniRecords {
            try await applyBeneRecord(beneRecord, partitaId: partitaId, garanziaId: nil)
        }
    }
    
    private func applyGaranziaRecord(_ record: CKRecord, periziaId: UUID) async throws {
        guard let garanziaIdStr = record["garanziaId"] as? String,
              let garanziaId = UUID(uuidString: garanziaIdStr) else { return }
        
        let context = PersistenceController.shared.container.viewContext
        
        try await context.perform {
            let fetchPerizia = NSFetchRequest<Perizia>(entityName: "Perizia")
            fetchPerizia.predicate = NSPredicate(format: "id == %@", periziaId as CVarArg)
            fetchPerizia.fetchLimit = 1
            guard let perizia = try? context.fetch(fetchPerizia).first else { return }
            
            let garanzia: Garanzia
            if let existing = perizia.garanzieArray.first(where: { $0.id == garanziaId }) {
                garanzia = existing
            } else {
                garanzia = Garanzia(context: context)
                garanzia.id = garanziaId
                perizia.addToGaranzie(garanzia)
            }
            
            garanzia.tipoGaranzia = record["tipoGaranzia"] as? String ?? ""
            garanzia.nomeFornitoCompagnia = record["nomeFornitoCompagnia"] as? String
            garanzia.nomeEditabile = record["nomeEditabile"] as? String ?? ""
            garanzia.tipologia = record["tipologia"] as? String ?? ""
            garanzia.massimale = NSDecimalNumber(value: record["massimale"] as? Double ?? 0)
            garanzia.massimaleUnico = record["massimaleUnico"] as? Bool ?? false
            garanzia.ordine = Int16(record["ordine"] as? Int ?? 0)
            if let v = record["valorePRA"] as? Double { garanzia.valorePRA = NSDecimalNumber(value: v) }
            if let v = record["franchigiaMinimo"] as? Double { garanzia.franchigiaMinimo = NSDecimalNumber(value: v) }
            if let v = record["franchigiaMassimo"] as? Double { garanzia.franchigiaMassimo = NSDecimalNumber(value: v) }
            if let v = record["scopertoPercentuale"] as? Double { garanzia.scopertoPercentuale = NSDecimalNumber(value: v) }
            if let v = record["scopertoMinimo"] as? Double { garanzia.scopertoMinimo = NSDecimalNumber(value: v) }
            if let v = record["scopertoMassimo"] as? Double { garanzia.scopertoMassimo = NSDecimalNumber(value: v) }
            
            if context.hasChanges { try context.save() }
        }
        
        // Fetch e applica beni della garanzia
        let beniQuery = CKQuery(recordType: RecordType.bene, predicate: NSPredicate(format: "garanziaId == %@", garanziaIdStr))
        let beniRecords = try await performQuery(beniQuery)
        for beneRecord in beniRecords {
            try await applyBeneRecord(beneRecord, partitaId: nil, garanziaId: garanziaId)
        }
    }
    
    private func applyBeneRecord(_ record: CKRecord, partitaId: UUID?, garanziaId: UUID?) async throws {
        guard let beneIdStr = record["beneId"] as? String,
              let beneId = UUID(uuidString: beneIdStr) else { return }
        
        let context = PersistenceController.shared.container.viewContext
        
        try await context.perform {
            var bene: Bene?
            
            if let partitaId = partitaId {
                let fetchPartita = NSFetchRequest<Partita>(entityName: "Partita")
                fetchPartita.predicate = NSPredicate(format: "id == %@", partitaId as CVarArg)
                fetchPartita.fetchLimit = 1
                if let partita = try? context.fetch(fetchPartita).first {
                    if let existing = partita.beniArray.first(where: { $0.id == beneId }) {
                        bene = existing
                    } else {
                        bene = Bene(context: context)
                        bene?.id = beneId
                        partita.addToBeni(bene!)
                    }
                }
            } else if let garanziaId = garanziaId {
                let fetchGaranzia = NSFetchRequest<Garanzia>(entityName: "Garanzia")
                fetchGaranzia.predicate = NSPredicate(format: "id == %@", garanziaId as CVarArg)
                fetchGaranzia.fetchLimit = 1
                if let garanzia = try? context.fetch(fetchGaranzia).first {
                    if let existing = garanzia.beniArray.first(where: { $0.id == beneId }) {
                        bene = existing
                    } else {
                        bene = Bene(context: context)
                        bene?.id = beneId
                        garanzia.addToBeni(bene!)
                    }
                }
            }
            
            guard let bene = bene else { return }
            
            bene.nome = record["nome"] as? String ?? ""
            bene.marca = record["marca"] as? String
            bene.modello = record["modello"] as? String
            bene.numeroSerie = record["numeroSerie"] as? String
            bene.anno = Int16(record["anno"] as? Int ?? 0)
            bene.stimata = record["stimata"] as? Bool ?? false
            bene.relazioneTecnica = record["relazioneTecnica"] as? String
            bene.ivaInclusa = record["ivaInclusa"] as? Bool ?? false
            bene.ripristiniUltimati = record["ripristiniUltimati"] as? Bool ?? false
            bene.residuiMantenuti = record["residuiMantenuti"] as? String
            bene.sostituzioneIntero = record["sostituzioneIntero"] as? Bool ?? false
            bene.determinazioneDanno = record["determinazioneDanno"] as? String
            bene.deprezzamento = record["deprezzamento"] as? Double ?? 20
            bene.aliquotaIVA = record["aliquotaIVA"] as? Double ?? 22
            bene.ordine = Int16(record["ordine"] as? Int ?? 0)
            if let v = record["richiesta"] as? Double { bene.richiesta = NSDecimalNumber(value: v) }
            if let v = record["liquidazioneForzata"] as? Double { bene.liquidazioneForzata = NSDecimalNumber(value: v) }
            
            if context.hasChanges { try context.save() }
        }
        
        // Fetch e applica voci costo
        let vociQuery = CKQuery(recordType: RecordType.voceCosto, predicate: NSPredicate(format: "beneId == %@", beneIdStr))
        let vociRecords = try await performQuery(vociQuery)
        for voceRecord in vociRecords {
            try await applyVoceCostoRecord(voceRecord, beneId: beneId)
        }
    }
    
    private func applyVoceCostoRecord(_ record: CKRecord, beneId: UUID) async throws {
        guard let voceIdStr = record["voceId"] as? String,
              let voceId = UUID(uuidString: voceIdStr) else { return }
        
        let context = PersistenceController.shared.container.viewContext
        
        try await context.perform {
            let fetchBene = NSFetchRequest<Bene>(entityName: "Bene")
            fetchBene.predicate = NSPredicate(format: "id == %@", beneId as CVarArg)
            fetchBene.fetchLimit = 1
            guard let bene = try? context.fetch(fetchBene).first else { return }
            
            let voce: VoceCosto
            if let existing = bene.vociCostoArray.first(where: { $0.id == voceId }) {
                voce = existing
            } else {
                voce = VoceCosto(context: context)
                voce.id = voceId
                bene.addToVociCosto(voce)
            }
            
            voce.descrizione = record["descrizione"] as? String ?? ""
            voce.unitaMisura = record["unitaMisura"] as? String ?? ""
            voce.quantita = NSDecimalNumber(value: record["quantita"] as? Double ?? 0)
            voce.valoreUnitario = NSDecimalNumber(value: record["valoreUnitario"] as? Double ?? 0)
            voce.ordine = Int16(record["ordine"] as? Int ?? 0)
            voce.indennizzabile = record["indennizzabile"] as? Bool ?? true
            voce.formula = record["formula"] as? String
            if let v = record["totaleANuovo"] as? Double { voce.totaleANuovo = NSDecimalNumber(value: v) }
            if let v = record["percentualeMigliorie"] as? Double { voce.percentualeMigliorie = NSDecimalNumber(value: v) }
            if let v = record["nettoMigliorie"] as? Double { voce.nettoMigliorie = NSDecimalNumber(value: v) }
            if let v = record["percentualeIllesi"] as? Double { voce.percentualeIllesi = NSDecimalNumber(value: v) }
            if let v = record["nettoIllesi"] as? Double { voce.nettoIllesi = NSDecimalNumber(value: v) }
            if let v = record["vsu"] as? Double { voce.vsu = NSDecimalNumber(value: v) }
            if let v = record["si"] as? Double { voce.si = NSDecimalNumber(value: v) }
            
            if context.hasChanges { try context.save() }
        }
    }
    
    private func applyCoassicurazioniRecords(_ records: [CKRecord], riferimento: String) async throws {
        let context = PersistenceController.shared.container.viewContext
        
        try await context.perform {
            let fetchSinistro = NSFetchRequest<Sinistro>(entityName: "Sinistro")
            fetchSinistro.predicate = NSPredicate(format: "riferimento == %@", riferimento)
            fetchSinistro.fetchLimit = 1
            guard let sinistro = try? context.fetch(fetchSinistro).first else { return }
            
            for record in records {
                guard let coassIdStr = record["coassId"] as? String,
                      let coassId = UUID(uuidString: coassIdStr) else { continue }
                
                let coass: Coassicurazione
                if let existing = sinistro.coassicurazioniArray.first(where: { $0.id == coassId }) {
                    coass = existing
                } else {
                    coass = Coassicurazione(context: context)
                    coass.id = coassId
                    sinistro.addToCoassicurazioni(coass)
                }
                
                coass.tipo = record["tipo"] as? String ?? ""
                coass.compagnia = record["compagnia"] as? String ?? ""
                coass.polizza = record["polizza"] as? String ?? ""
                coass.numeroSinistro = record["numeroSinistro"] as? String ?? ""
                coass.ordine = Int16(record["ordine"] as? Int ?? 0)
            }
            
            if context.hasChanges { try context.save() }
        }
    }
    
    private func applyDiarioRecords(_ records: [CKRecord], riferimento: String) async throws {
        let context = PersistenceController.shared.container.viewContext
        
        try await context.perform {
            let fetchSinistro = NSFetchRequest<Sinistro>(entityName: "Sinistro")
            fetchSinistro.predicate = NSPredicate(format: "riferimento == %@", riferimento)
            fetchSinistro.fetchLimit = 1
            guard let sinistro = try? context.fetch(fetchSinistro).first else { return }
            
            var diarioArray = sinistro.diarioArray
            
            for record in records {
                guard let entryIdStr = record["entryId"] as? String,
                      let entryId = UUID(uuidString: entryIdStr),
                      let timestamp = record["timestamp"] as? Date,
                      let tipoRaw = record["tipo"] as? String,
                      let tipo = DiarioEntry.TipoEntry(rawValue: tipoRaw) else { continue }
                
                // Skip se già esiste
                if diarioArray.contains(where: { $0.id == entryId }) { continue }
                
                let entry = DiarioEntry(
                    id: entryId,
                    timestamp: timestamp,
                    tipo: tipo,
                    titolo: record["titolo"] as? String,
                    riassunto: (record["riassunto"] as? String) ?? "",
                    contenutoCompleto: (record["contenutoCompleto"] as? String) ?? "",
                    emailMessageId: nil,
                    processedEmailDate: nil,
                    whatsAppChatId: nil,
                    whatsAppMessageIds: nil,
                    processedWhatsAppDate: nil,
                    generatedTaskId: nil,
                    createdByEmail: record["createdBy"] as? String
                )
                
                diarioArray.append(entry)
            }
            
            diarioArray.sort { $0.timestamp < $1.timestamp }
            sinistro.diarioArray = diarioArray
            
            if context.hasChanges { try context.save() }
        }
    }
    
    // MARK: - CloudKit Subscriptions
    
    private func setupSubscriptions() async {
        // Subscription per modifiche ai sinistri
        let subscriptionID = "sinistro-changes"
        let subscription = CKQuerySubscription(
            recordType: RecordType.sinistroMinimal,
            predicate: NSPredicate(value: true),
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        
        do {
            _ = try await publicDB.save(subscription)
            print("[CloudKitSinistro] ✅ Subscription attivata")
        } catch {
            // Già esistente o errore
        }
    }
    
    /// Gestisce notifica push CloudKit
    func handleCloudKitNotification() async {
        await syncAllMinimal()
    }
    
    // MARK: - CloudKit Wrappers
    
    private func saveRecord(_ record: CKRecord) async throws -> CKRecord {
        let saved = try await saveRecords([record])
        return saved.first ?? record
    }
    
    private func saveRecords(_ records: [CKRecord]) async throws -> [CKRecord] {
        guard !records.isEmpty else { return [] }
        var savedAll: [CKRecord] = []
        var idx = 0
        while idx < records.count {
            let end = min(idx + Self.modifyBatchSize, records.count)
            let chunk = Array(records[idx..<end])
            let saved = try await saveRecordsChunk(chunk)
            savedAll.append(contentsOf: saved)
            idx = end
        }
        return savedAll
    }
    
    private func saveRecordsChunk(_ records: [CKRecord]) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { continuation in
            let op = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
            op.savePolicy = .changedKeys
            op.isAtomic = false
            
            op.perRecordCompletionBlock = { record, error in
                if let error = error {
                    let recordID = record.recordID.recordName
                    print("[CloudKitSinistro] ⚠️ Errore parziale per record \(recordID): \(error.localizedDescription)")
                    
                    // Se è un errore di conflitto, logghiamo più info
                    if let ckError = error as? CKError, ckError.code == .serverRecordChanged {
                        print("[CloudKitSinistro]   -> Conflitto rilevato per \(recordID). Il server ha una versione più recente.")
                    }
                }
            }
            
            op.modifyRecordsCompletionBlock = { saved, _, error in
                if let error = error {
                    // Se l'errore è parziale, restituiamo comunque i record salvati con successo
                    if let ckError = error as? CKError,
                       ckError.code == .partialFailure,
                       let partialErrors = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [CKRecord.ID: Error] {
                        
                        let totalFailed = partialErrors.count
                        print("[CloudKitSinistro] ⚠️ Errore parziale rilevato (\(totalFailed) record falliti)")
                        
                        // Analizziamo i tipi di errore
                        var conflictCount = 0
                        for (id, pError) in partialErrors {
                            if let cpError = pError as? CKError {
                                if cpError.code == .serverRecordChanged {
                                    conflictCount += 1
                                }
                                print("[CloudKitSinistro]   - Record \(id.recordName): [\(cpError.code.rawValue)] \(cpError.localizedDescription)")
                            } else {
                                print("[CloudKitSinistro]   - Record \(id.recordName): \(pError.localizedDescription)")
                            }
                        }
                        
                        // Se sono quasi tutti conflitti, non lo consideriamo un errore fatale per il batch
                        if conflictCount > 0 {
                            print("[CloudKitSinistro]   -> \(conflictCount) conflitti ignorati (il server ha dati più recenti)")
                        }
                        
                        continuation.resume(returning: saved ?? [])
                        return
                    }
                    
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: saved ?? [])
            }
            self.publicDB.add(op)
        }
    }
    
    private func fetchRecord(_ recordID: CKRecord.ID) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            publicDB.fetch(withRecordID: recordID) { record, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: record!)
            }
        }
    }
    
    /// Upsert con CKModifyRecordsOperation e savePolicy .changedKeys per evitare conflitti oplock.
    private func upsertRecordResolvingConflicts(_ ourRecord: CKRecord, sinistro: Sinistro, attempt: Int = 1) async throws {
        let maxAttempts = 3
        let recordID = ourRecord.recordID
        
        // 1. Fetch esistente (o nil se non esiste)
        let existing: CKRecord?
        do {
            existing = try await fetchRecord(recordID)
        } catch let e as CKError where e.code == .unknownItem {
            existing = nil
        } catch {
            throw error
        }
        
        // 2. Prepara il target (record esistente aggiornato, oppure nostro record se nuovo)
        let target = existing ?? ourRecord
        if existing != nil {
            for key in ourRecord.allKeys() {
                target[key] = ourRecord[key]
            }
        }
        
        // 3. Salva con CKModifyRecordsOperation e savePolicy .changedKeys
        do {
            try await saveRecordWithChangedKeysPolicy(target)
        } catch let ckError as CKError {
            // Retry su conflitti
            let retryableCodes: Set<CKError.Code> = [.serverRecordChanged, .batchRequestFailed, .zoneBusy, .requestRateLimited]
            let isOplock = ckError.localizedDescription.contains("oplock")
            if (retryableCodes.contains(ckError.code) || isOplock) && attempt < maxAttempts {
                try await Task.sleep(nanoseconds: UInt64(150_000_000 * attempt)) // 150ms * attempt
                try await upsertRecordResolvingConflicts(ourRecord, sinistro: sinistro, attempt: attempt + 1)
                return
            }
            throw ckError
        }
    }
    
    /// Salva un record usando CKModifyRecordsOperation con savePolicy .changedKeys
    private func saveRecordWithChangedKeysPolicy(_ record: CKRecord) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let op = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            op.savePolicy = .changedKeys
            op.isAtomic = false
            op.modifyRecordsCompletionBlock = { saved, _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
            self.publicDB.add(op)
        }
    }
    
    // MARK: - Eliminazione Sinistri da CloudKit
    
    /// Elimina un sinistro da CloudKit (minimal + full)
    /// - Parameter riferimento: Il riferimento del sinistro da eliminare
    func deleteSinistro(riferimento: String) async {
        guard settings.isEnabled else {
            print("[CloudKitSinistro] ⚠️ CloudKit disabilitato, skip delete \(riferimento)")
            return
        }
        
        // Prepara gli ID dei record da eliminare
        let minimalID = CKRecord.ID(recordName: "minimal_\(riferimento)")
        let fullID = CKRecord.ID(recordName: "full_\(riferimento)")
        
        do {
            try await deleteRecords([minimalID, fullID])
            print("[CloudKitSinistro] 🗑️ Sinistro \(riferimento) eliminato da CloudKit")
        } catch {
            print("[CloudKitSinistro] ❌ Errore eliminazione \(riferimento) da CloudKit: \(error.localizedDescription)")
            recordError(
                type: .other,
                message: "Errore eliminazione sinistro",
                details: error.localizedDescription,
                context: "Sinistro: \(riferimento)"
            )
        }
    }
    
    /// Elimina più sinistri da CloudKit
    /// - Parameter riferimenti: Array di riferimenti da eliminare
    func deleteSinistri(riferimenti: [String]) async {
        guard settings.isEnabled else {
            print("[CloudKitSinistro] ⚠️ CloudKit disabilitato, skip delete batch")
            return
        }
        
        guard !riferimenti.isEmpty else { return }
        
        // Prepara tutti gli ID (minimal + full per ogni sinistro)
        var recordIDs: [CKRecord.ID] = []
        for rif in riferimenti {
            recordIDs.append(CKRecord.ID(recordName: "minimal_\(rif)"))
            recordIDs.append(CKRecord.ID(recordName: "full_\(rif)"))
        }
        
        do {
            try await deleteRecords(recordIDs)
            print("[CloudKitSinistro] 🗑️ \(riferimenti.count) sinistri eliminati da CloudKit")
        } catch {
            print("[CloudKitSinistro] ❌ Errore eliminazione batch da CloudKit: \(error.localizedDescription)")
            recordError(
                type: .other,
                message: "Errore eliminazione batch sinistri",
                details: error.localizedDescription,
                context: "\(riferimenti.count) sinistri"
            )
        }
    }
    
    private func deleteRecords(_ recordIDs: [CKRecord.ID]) async throws {
        guard !recordIDs.isEmpty else { return }
        
        // Elabora in batch
        var idx = 0
        while idx < recordIDs.count {
            let end = min(idx + Self.modifyBatchSize, recordIDs.count)
            let chunk = Array(recordIDs[idx..<end])
            try await deleteRecordsChunk(chunk)
            idx = end
        }
    }
    
    private func deleteRecordsChunk(_ recordIDs: [CKRecord.ID]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let op = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIDs)
            op.isAtomic = false
            
            op.modifyRecordsCompletionBlock = { _, deletedIDs, error in
                if let error = error {
                    // Ignora errori "record not found" - il sinistro potrebbe non esistere su CloudKit
                    if let ckError = error as? CKError {
                        if ckError.code == .unknownItem || ckError.code == .partialFailure {
                            // Non è un vero errore, il record semplicemente non esisteva
                            continuation.resume()
                            return
                        }
                    }
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume()
            }
            self.publicDB.add(op)
        }
    }
    
    private func performQuery(_ query: CKQuery) async throws -> [CKRecord] {
        let lock = NSLock()
        var all: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor? = nil
        
        while true {
            let nextCursor = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKQueryOperation.Cursor?, Error>) in
                let op: CKQueryOperation = {
                    if let cursor {
                        return CKQueryOperation(cursor: cursor)
                    } else {
                        return CKQueryOperation(query: query)
                    }
                }()
                op.resultsLimit = Self.queryBatchSize
                op.recordFetchedBlock = { record in
                    lock.lock()
                    all.append(record)
                    lock.unlock()
                }
                op.queryCompletionBlock = { newCursor, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    continuation.resume(returning: newCursor)
                }
                self.publicDB.add(op)
            }
            
            cursor = nextCursor
            if cursor == nil { break }
        }
        
        return all
    }
}
