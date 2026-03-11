//
//  AgenziaDetailWindowManager.swift
//  PerX
//
//  Apre la finestra dettaglio agenzia (rubrica) via WindowManager.
//

import SwiftUI
import AppKit

@MainActor
final class AgenziaDetailWindowManager: ObservableObject {
    static let shared = AgenziaDetailWindowManager()
    
    private static let windowIdentifierPrefix = "com.perx.agenziaDetail"
    
    private init() {}
    
    /// Apre (o porta in primo piano) la finestra dettaglio per l'agenzia
    func openAgenziaDetail(agenzia: RubricaAgenzia) {
        let windowId = "\(Self.windowIdentifierPrefix).\(agenzia.id)"
        let title = "Agenzia: \(agenzia.nomeCompleto)"
        
        let configuration = WindowConfiguration(
            identifier: windowId,
            title: title,
            minSize: CGSize(width: 480, height: 420),
            defaultSize: CGSize(width: 560, height: 520),
            isAlwaysOnTop: false
        )
        
        let contentView = AgenziaDetailWindowContent(agenzia: agenzia)
            .frame(minWidth: 480, minHeight: 420)
        
        WindowManager.shared.openWindow(
            identifier: windowId,
            content: contentView,
            configuration: configuration,
            tabId: agenzia.id,
            tabTitle: agenzia.nomeCompleto
        )
    }
}

// MARK: - Contenuto finestra dettaglio agenzia

struct AgenziaDetailWindowContent: View {
    let agenzia: RubricaAgenzia
    @StateObject private var rubricaService = CloudKitRubricaSyncService.shared
    
    private var filiali: [RubricaAgenzia] {
        rubricaService.filialiPer(agenziaId: agenzia.id)
    }
    
    private var agenti: [RubricaAgente] {
        rubricaService.agentiPer(agenziaId: agenzia.id)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text(agenzia.nomeCompleto)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(Compagnia(rawValue: agenzia.compagniaId)?.rawValue ?? agenzia.compagniaId)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // Flag attivi
                VStack(alignment: .leading, spacing: 8) {
                    Text("Note / Comportamenti")
                        .font(.headline)
                    let activeFlags = RubricaAgenziaFlag.allCases.filter { $0.isOn(in: agenzia) }
                    if activeFlags.isEmpty {
                        Text("Nessun flag impostato")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        AgenziaDetailWindowContent.flagTags(flags: activeFlags)
                    }
                }
                
                // Contatti
                if !agenzia.telefoni.isEmpty || !agenzia.email.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Contatti")
                            .font(.headline)
                        if !agenzia.telefoni.isEmpty {
                            ForEach(Array(agenzia.telefoni.enumerated()), id: \.offset) { _, tel in
                                Label(tel, systemImage: "phone")
                                    .font(.subheadline)
                            }
                        }
                        if !agenzia.email.isEmpty {
                            ForEach(Array(agenzia.email.enumerated()), id: \.offset) { _, em in
                                Label(em, systemImage: "envelope")
                                    .font(.subheadline)
                            }
                        }
                    }
                }
                
                // Indirizzo
                if !agenzia.indirizzoCompleto.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Indirizzo")
                            .font(.headline)
                        Text(agenzia.indirizzoCompleto)
                            .font(.subheadline)
                    }
                }
                
                // Filiali
                if !filiali.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Filiali (\(filiali.count))")
                            .font(.headline)
                        ForEach(filiali) { f in
                            Text(f.nomeConTipoSede)
                                .font(.subheadline)
                        }
                    }
                }
                
                // Agenti
                if !agenti.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Agenti (\(agenti.count))")
                            .font(.headline)
                        ForEach(agenti) { ag in
                            Text(ag.nomeCompleto)
                                .font(.subheadline)
                        }
                    }
                }
                
                if let note = agenzia.note, !note.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Note")
                            .font(.headline)
                        Text(note)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private static func flagTags(flags: [RubricaAgenziaFlag]) -> some View {
        FlowLayout(spacing: 6) {
            ForEach(flags) { flag in
                Text(flag.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.2))
                    .cornerRadius(6)
            }
        }
    }
}
