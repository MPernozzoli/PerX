import Foundation

/// Cosa lo studio può usare. Chiari è un solo perito: niente funzioni che
/// mostrano PerX a colleghi o assicurati.
struct StudioAccess: Codable, Equatable {
    var workflowProfile: String
    var singleOperator: Bool
    var sinistri: Bool
    var stima: Bool
    var documenti: Bool
    var posta: Bool
    var salaRegia: Bool
    var consuntivo: Bool
    var rubrica: Bool
    var portalAssicurati: Bool
    var catDispatcher: Bool
    var videoperizia: Bool
    var invitiUtenti: Bool
    var directoryColleghi: Bool
    var chatColleghi: Bool
    var whatsapp: Bool
    var telegram: Bool
    var chiamatePerx: Bool
    var messaggiEsterni: Bool
    var linkPubblici: Bool
    var programmazioneRete: Bool
    var studioCondiviso: Bool

    static let studio = StudioAccess(
        workflowProfile: "studio",
        singleOperator: false,
        sinistri: true,
        stima: true,
        documenti: true,
        posta: true,
        salaRegia: false,
        consuntivo: true,
        rubrica: true,
        portalAssicurati: true,
        catDispatcher: true,
        videoperizia: true,
        invitiUtenti: true,
        directoryColleghi: true,
        chatColleghi: true,
        whatsapp: true,
        telegram: true,
        chiamatePerx: true,
        messaggiEsterni: true,
        linkPubblici: true,
        programmazioneRete: true,
        studioCondiviso: true
    )

    static let chiari = StudioAccess(
        workflowProfile: "chiari",
        singleOperator: true,
        sinistri: true,
        stima: true,
        documenti: true,
        posta: true,
        salaRegia: true,
        consuntivo: true,
        rubrica: true,
        portalAssicurati: false,
        catDispatcher: false,
        videoperizia: false,
        invitiUtenti: false,
        directoryColleghi: false,
        chatColleghi: false,
        whatsapp: false,
        telegram: false,
        chiamatePerx: false,
        messaggiEsterni: false,
        linkPubblici: false,
        programmazioneRete: false,
        studioCondiviso: false
    )

    static func resolved(
        profile: String?,
        singleOperator: Bool?,
        capabilities: [String: Bool]?,
        slug: String
    ) -> StudioAccess {
        let isChiari = (profile ?? (slug == "chiari" ? "chiari" : "studio")) == "chiari"
        var access = isChiari ? StudioAccess.chiari : StudioAccess.studio
        if let capabilities {
            access.apply(capabilities, lockOutward: isChiari)
        }
        if let singleOperator {
            access.singleOperator = singleOperator || isChiari
        }
        if isChiari {
            access = access.lockedChiari()
        }
        return access
    }

    func lockedChiari() -> StudioAccess {
        var copy = self
        copy.workflowProfile = "chiari"
        copy.singleOperator = true
        copy.salaRegia = true
        copy.posta = true
        copy.portalAssicurati = false
        copy.catDispatcher = false
        copy.videoperizia = false
        copy.invitiUtenti = false
        copy.directoryColleghi = false
        copy.chatColleghi = false
        copy.whatsapp = false
        copy.telegram = false
        copy.chiamatePerx = false
        copy.messaggiEsterni = false
        copy.linkPubblici = false
        copy.programmazioneRete = false
        copy.studioCondiviso = false
        return copy
    }

    private mutating func apply(_ capabilities: [String: Bool], lockOutward: Bool) {
        func set(_ keyPath: WritableKeyPath<StudioAccess, Bool>, key: String, outward: Bool) {
            guard let value = capabilities[key] else { return }
            if lockOutward && outward { return }
            self[keyPath: keyPath] = value
        }
        set(\.sinistri, key: "sinistri", outward: false)
        set(\.stima, key: "stima", outward: false)
        set(\.documenti, key: "documenti", outward: false)
        set(\.posta, key: "posta", outward: false)
        set(\.salaRegia, key: "sala_regia", outward: false)
        set(\.consuntivo, key: "consuntivo", outward: false)
        set(\.rubrica, key: "rubrica", outward: false)
        set(\.portalAssicurati, key: "portal_assicurati", outward: true)
        set(\.catDispatcher, key: "cat_dispatcher", outward: true)
        set(\.videoperizia, key: "videoperizia", outward: true)
        set(\.invitiUtenti, key: "inviti_utenti", outward: true)
        set(\.directoryColleghi, key: "directory_colleghi", outward: true)
        set(\.chatColleghi, key: "chat_colleghi", outward: true)
        set(\.whatsapp, key: "whatsapp", outward: true)
        set(\.telegram, key: "telegram", outward: true)
        set(\.chiamatePerx, key: "chiamate_perx", outward: true)
        set(\.messaggiEsterni, key: "messaggi_esterni", outward: true)
        set(\.linkPubblici, key: "link_pubblici", outward: true)
        set(\.programmazioneRete, key: "programmazione_rete", outward: true)
        set(\.studioCondiviso, key: "studio_condiviso", outward: true)
    }
}
