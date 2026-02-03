import Foundation

/// Tag per file - schema condiviso tra Client e Hub
/// Replica la logica di FileTagManager.FileTag del client
public struct HubFileTag: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let colorHex: String
    public let requiresAdditionalText: Bool
    public let category: TagCategory?
    
    public enum TagCategory: String, Codable, CaseIterable, Sendable {
        case foto = "Foto"
    }
    
    public init(id: String, name: String, colorHex: String, requiresAdditionalText: Bool = false, category: TagCategory? = nil) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.requiresAdditionalText = requiresAdditionalText
        self.category = category
    }
    
    // MARK: - Tag disponibili (stessa lista del client)
    
    public static let availableTags: [HubFileTag] = [
        // Documenti principali - ordine logico di utilizzo
        HubFileTag(id: "atto_da_firmare", name: "Atto da Firmare", colorHex: "#FF69B4"),
        HubFileTag(id: "atto_firmato", name: "Atto Firmato", colorHex: "#98FF98"),
        HubFileTag(id: "allegati_atto", name: "Allegati Atto", colorHex: "#98FF98"),
        HubFileTag(id: "fattura", name: "Fattura", colorHex: "#0066CC"),
        HubFileTag(id: "preventivo", name: "Preventivo", colorHex: "#0066CC"),
        HubFileTag(id: "fulminazione", name: "Fulminazione", colorHex: "#FFCC00"),
        HubFileTag(id: "perizia", name: "Perizia", colorHex: "#00CC00"),
        HubFileTag(id: "verbale", name: "Verbale", colorHex: "#FF9900"),
        
        // Tag per file generati nella cartella "Da Chiudere"
        HubFileTag(id: "file_foto", name: "File Foto", colorHex: "#808080"),
        HubFileTag(id: "file_atto", name: "File Atto", colorHex: "#808080"),
        HubFileTag(id: "file_giustificativi", name: "File Giustificativi", colorHex: "#808080"),
        HubFileTag(id: "file_perizia", name: "File Perizia", colorHex: "#808080"),
        HubFileTag(id: "file_verbale", name: "File Verbale", colorHex: "#808080"),
        HubFileTag(id: "file_fulminazione", name: "File Fulminazione", colorHex: "#808080"),
        HubFileTag(id: "file_altro", name: "Altro file di chiusura", colorHex: "#808080"),
        HubFileTag(id: "dichiarazione", name: "Dichiarazione", colorHex: "#9933FF"),
        HubFileTag(id: "denuncia", name: "Denuncia", colorHex: "#FF0000"),
        
        // Documenti secondari/informativi
        HubFileTag(id: "elaborato_excel", name: "Elaborato Excel", colorHex: "#00CC00"),
        HubFileTag(id: "report_cat", name: "Report CAT", colorHex: "#4B0082"),
        HubFileTag(id: "simplo_di_polizza", name: "Simplo di Polizza", colorHex: "#0066CC"),
        HubFileTag(id: "cga", name: "CGA", colorHex: "#4B0082"),
        HubFileTag(id: "incarico", name: "Incarico", colorHex: "#8B4513"),
        
        // Categoria Foto
        HubFileTag(id: "foto_ubicazione_rischio", name: "Ubicazione del rischio", colorHex: "#FF0000", category: .foto),
        HubFileTag(id: "foto_ubicazione_tecnico", name: "Ubicazione tecnico riparatore", colorHex: "#FF0000", category: .foto),
        HubFileTag(id: "foto_ubicazione_amministratore", name: "Ubicazione amministratore", colorHex: "#FF0000", category: .foto),
        HubFileTag(id: "foto_ubicazione_altra", name: "Altra ubicazione", colorHex: "#FF0000", requiresAdditionalText: true, category: .foto),
        HubFileTag(id: "foto_bene", name: "Bene", colorHex: "#FF0000", requiresAdditionalText: true, category: .foto),
        HubFileTag(id: "foto_componente", name: "Componente", colorHex: "#FF0000", requiresAdditionalText: true, category: .foto),
        HubFileTag(id: "foto_ripristino", name: "Ripristino", colorHex: "#FF0000", requiresAdditionalText: true, category: .foto),
        HubFileTag(id: "foto_test_funzionale", name: "Test funzionale", colorHex: "#FF0000", category: .foto),
        HubFileTag(id: "test_strumentale", name: "Test strumentale", colorHex: "#FF0000", category: .foto)
    ]
    
    /// Tag che supportano sottotipo atto (accertamento/liquidazione)
    public static let attoTags = ["atto_da_firmare", "atto_firmato"]
    
    /// Tag che supportano sottotipo fulminazione (positiva/negativa)
    public static let fulminazioneTags = ["fulminazione"]
    
    /// Tag che supportano tipo giustificativi (fattura/preventivo)
    public static let giustificativiTags = ["fattura", "preventivo"]
    
    /// Tag ubicazione
    public static let ubicazioneTags = ["foto_ubicazione_rischio", "foto_ubicazione_tecnico", "foto_ubicazione_amministratore", "foto_ubicazione_altra"]
    
    /// Tag che supportano selezione bene di riferimento
    public static let beneRiferimentoTags = ["foto_componente", "foto_ripristino", "foto_test_funzionale", "test_strumentale"]
    
    /// Tag per file generati nella cartella "Da Chiudere"
    public static let closureGeneratedTags = ["file_foto", "file_atto", "file_giustificativi", "file_perizia", "file_verbale", "file_fulminazione", "file_altro"]
    
    public static func find(byId id: String) -> HubFileTag? {
        return availableTags.first { $0.id == id }
    }
}

// MARK: - Tag Application Data (per applicare tag con metadati)

public struct HubTagApplicationData: Codable, Sendable {
    public let tagId: String
    public var additionalText: String?
    public var daAllegareInChiusura: Bool?
    public var attoSottotipo: String?
    public var attoStato: String?
    public var giustificativiTipo: String?
    public var fulminazioneSottotipo: String?
    public var allegatiAttoSottotipo: String?
    public var beneRiferimento: String?
    public var ubicazioneTipo: String?
    public var ubicazioneAltraDescrizione: String?
    
    public init(tagId: String) {
        self.tagId = tagId
    }
}

// MARK: - Tagged File Result

public struct HubTaggedFile: Codable, Sendable {
    public let fileId: String
    public let filename: String
    public let relativePath: String
    public var tags: [HubTagApplicationData]
    
    public init(fileId: String, filename: String, relativePath: String, tags: [HubTagApplicationData] = []) {
        self.fileId = fileId
        self.filename = filename
        self.relativePath = relativePath
        self.tags = tags
    }
}
