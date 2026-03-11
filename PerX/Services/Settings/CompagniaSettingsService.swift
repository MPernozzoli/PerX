//
//  CompagniaSettingsService.swift
//  PerX
//
//  Gestisce override persistenti per i parametri delle compagnie assicurative.
//

import Foundation
import SwiftUI
import Combine
import AppKit

/// Override per i parametri di una compagnia (salvati in UserDefaults, sync CloudKit)
struct CompagniaOverride: Codable, Equatable {
    var usaComunicaEsitoPerAtto: Bool?
    var sempreAllegaFulminazione: Bool?
    var attoSempreRichiesto: Bool?
    var fileObbligatoriChiusura: [String]? // rawValue di TipoFileCompagnia
    var rangeLiquidatoMedioMin: Double?
    var rangeLiquidatoMedioMax: Double?
    var rangePLMin: Double?
    var rangePLMax: Double?
    var targetLiquidatoMedio: Double?
    var targetNegative: Double?
    var targetTempoGestione: Double?
    var targetConcordate: Double?
    var uiColorHex: String?
    var shortLabel: String?
    var logoAssetName: String?
    /// Logo PNG in base64 per sync CloudKit
    var logoBase64: String?
}

final class CompagniaSettingsService: ObservableObject {
    static let shared = CompagniaSettingsService()
    
    private let key = "compagniaOverrides_v1"
    private var overrides: [String: CompagniaOverride] = [:] {
        didSet { save() }
    }
    
    private init() {
        load()
        setupSyncObserver()
    }
    
    private func setupSyncObserver() {
        NotificationCenter.default.addObserver(
            forName: NotificationNames.cloudKitSharedSettingsUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.load()
            self?.writeLogosFromOverrides()
        }
    }
    
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: CompagniaOverride].self, from: data) else {
            overrides = [:]
            return
        }
        overrides = decoded
        writeLogosFromOverrides()
    }
    
    /// Scrive i loghi da logoBase64 negli override (usato dopo sync CloudKit)
    private func writeLogosFromOverrides() {
        for (raw, o) in overrides {
            guard let b64 = o.logoBase64, !b64.isEmpty,
                  let data = Data(base64Encoded: b64),
                  let compagnia = Compagnia(rawValue: raw) else { continue }
            let url = loghiDirectory.appendingPathComponent("logo_\(compagnia.sigla).png")
            try? data.write(to: url)
        }
    }
    
    private func save() {
        guard let encoded = try? JSONEncoder().encode(overrides) else { return }
        UserDefaults.standard.set(encoded, forKey: key)
        objectWillChange.send()
    }
    
    private func override(for compagnia: Compagnia) -> CompagniaOverride? {
        overrides[compagnia.rawValue]
    }
    
    private func setOverride(for compagnia: Compagnia, _ block: (inout CompagniaOverride) -> Void) {
        var o = overrides[compagnia.rawValue] ?? CompagniaOverride()
        block(&o)
        overrides[compagnia.rawValue] = o
    }
    
    // MARK: - Valori effettivi (override ?? default)
    
    func effectiveUsaComunicaEsitoPerAtto(_ compagnia: Compagnia) -> Bool {
        override(for: compagnia)?.usaComunicaEsitoPerAtto ?? compagnia.usaComunicaEsitoPerAtto
    }
    
    func effectiveSempreAllegaFulminazione(_ compagnia: Compagnia) -> Bool {
        override(for: compagnia)?.sempreAllegaFulminazione ?? compagnia.sempreAllegaFulminazione
    }
    
    func effectiveAttoSempreRichiesto(_ compagnia: Compagnia) -> Bool {
        override(for: compagnia)?.attoSempreRichiesto ?? compagnia.attoSempreRichiesto
    }
    
    func effectiveFileObbligatoriChiusura(_ compagnia: Compagnia) -> [TipoFileCompagnia] {
        guard let raw = override(for: compagnia)?.fileObbligatoriChiusura else {
            return compagnia.fileObbligatoriChiusura
        }
        return raw.compactMap { TipoFileCompagnia(rawValue: $0) }
    }
    
    func effectiveRangeLiquidatoMedio(_ compagnia: Compagnia) -> (min: Double, max: Double) {
        let o = override(for: compagnia)
        let def = compagnia.rangeLiquidatoMedio
        return (
            min: o?.rangeLiquidatoMedioMin ?? def.min,
            max: o?.rangeLiquidatoMedioMax ?? def.max
        )
    }
    
    func effectiveRangePL(_ compagnia: Compagnia) -> (min: Double, max: Double) {
        let o = override(for: compagnia)
        let def = compagnia.rangePL
        return (
            min: o?.rangePLMin ?? def.min,
            max: o?.rangePLMax ?? def.max
        )
    }
    
    func effectiveTargetLiquidatoMedio(_ compagnia: Compagnia) -> Double {
        override(for: compagnia)?.targetLiquidatoMedio ?? compagnia.targetLiquidatoMedio
    }
    
    func effectiveTargetNegative(_ compagnia: Compagnia) -> Double {
        override(for: compagnia)?.targetNegative ?? compagnia.targetNegative
    }
    
    func effectiveTargetTempoGestione(_ compagnia: Compagnia) -> Double {
        override(for: compagnia)?.targetTempoGestione ?? compagnia.targetTempoGestione
    }
    
    func effectiveTargetConcordate(_ compagnia: Compagnia) -> Double {
        override(for: compagnia)?.targetConcordate ?? compagnia.targetConcordate
    }
    
    func effectiveUiColor(_ compagnia: Compagnia) -> Color {
        if let hex = override(for: compagnia)?.uiColorHex, !hex.isEmpty {
            return Color(hex: hex)
        }
        let c = compagnia.uiColor
        return Color(red: c.red, green: c.green, blue: c.blue)
    }
    
    func effectiveShortLabel(_ compagnia: Compagnia) -> String {
        override(for: compagnia)?.shortLabel ?? compagnia.shortLabel
    }
    
    func effectiveLogoAssetName(_ compagnia: Compagnia) -> String? {
        override(for: compagnia)?.logoAssetName ?? compagnia.logoAssetName
    }
    
    // MARK: - Gruppo (delega alla prima compagnia)
    
    func effectiveUiColor(_ gruppo: GruppoAssicurativo) -> Color {
        gruppo.compagnie.first.map { effectiveUiColor($0) } ?? Color.gray
    }
    
    func effectiveShortLabel(_ gruppo: GruppoAssicurativo) -> String {
        gruppo.compagnie.first.map { effectiveShortLabel($0) } ?? gruppo.shortLabel
    }
    
    // MARK: - Setters
    
    func setUsaComunicaEsitoPerAtto(_ compagnia: Compagnia, _ value: Bool) {
        setOverride(for: compagnia) { $0.usaComunicaEsitoPerAtto = value }
    }
    
    func setSempreAllegaFulminazione(_ compagnia: Compagnia, _ value: Bool) {
        setOverride(for: compagnia) { $0.sempreAllegaFulminazione = value }
    }
    
    func setAttoSempreRichiesto(_ compagnia: Compagnia, _ value: Bool) {
        setOverride(for: compagnia) { $0.attoSempreRichiesto = value }
    }
    
    func setFileObbligatoriChiusura(_ compagnia: Compagnia, _ value: [TipoFileCompagnia]) {
        setOverride(for: compagnia) { $0.fileObbligatoriChiusura = value.map(\.rawValue) }
    }
    
    func setRangeLiquidatoMedio(_ compagnia: Compagnia, min: Double, max: Double) {
        setOverride(for: compagnia) {
            $0.rangeLiquidatoMedioMin = min
            $0.rangeLiquidatoMedioMax = max
        }
    }
    
    func setRangePL(_ compagnia: Compagnia, min: Double, max: Double) {
        setOverride(for: compagnia) {
            $0.rangePLMin = min
            $0.rangePLMax = max
        }
    }
    
    func setTargetLiquidatoMedio(_ compagnia: Compagnia, _ value: Double) {
        setOverride(for: compagnia) { $0.targetLiquidatoMedio = value }
    }
    
    func setTargetNegative(_ compagnia: Compagnia, _ value: Double) {
        setOverride(for: compagnia) { $0.targetNegative = value }
    }
    
    func setTargetTempoGestione(_ compagnia: Compagnia, _ value: Double) {
        setOverride(for: compagnia) { $0.targetTempoGestione = value }
    }
    
    func setTargetConcordate(_ compagnia: Compagnia, _ value: Double) {
        setOverride(for: compagnia) { $0.targetConcordate = value }
    }
    
    func setUiColor(_ compagnia: Compagnia, _ color: Color) {
        setOverride(for: compagnia) { $0.uiColorHex = color.toHex() }
    }
    
    func setShortLabel(_ compagnia: Compagnia, _ value: String?) {
        setOverride(for: compagnia) { $0.shortLabel = value?.isEmpty == true ? nil : value }
    }
    
    func setLogoAssetName(_ compagnia: Compagnia, _ value: String?) {
        setOverride(for: compagnia) { $0.logoAssetName = value?.isEmpty == true ? nil : value }
    }
    
    // MARK: - Logo caricato dall'utente
    
    private var loghiDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent(AppConstants.appName).appendingPathComponent("LoghiCompagnie")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    /// URL del logo salvato per la compagnia (se presente)
    func logoURL(for compagnia: Compagnia) -> URL? {
        let filename = "logo_\(compagnia.sigla).png"
        let url = loghiDirectory.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    
    /// Salva un'immagine come logo della compagnia (file + base64 per sync)
    func setLogoFromImage(_ compagnia: Compagnia, image: NSImage) {
        let filename = "logo_\(compagnia.sigla).png"
        let url = loghiDirectory.appendingPathComponent(filename)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
        setOverride(for: compagnia) {
            $0.logoAssetName = filename
            $0.logoBase64 = png.base64EncodedString()
        }
    }
    
    /// Rimuove il logo caricato dall'utente
    func clearLogo(for compagnia: Compagnia) {
        if let url = logoURL(for: compagnia) {
            try? FileManager.default.removeItem(at: url)
        }
        setOverride(for: compagnia) {
            $0.logoAssetName = nil
            $0.logoBase64 = nil
        }
    }
    
    func resetOverride(for compagnia: Compagnia) {
        clearLogo(for: compagnia)
        overrides.removeValue(forKey: compagnia.rawValue)
    }
    
    func hasOverride(for compagnia: Compagnia) -> Bool {
        overrides[compagnia.rawValue] != nil
    }
}
