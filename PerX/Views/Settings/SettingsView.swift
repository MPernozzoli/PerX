import SwiftUI
import CoreData

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedSection: SettingsSection = .sinistri
    @AppStorage("useSingleDirectory") private var useSingleDirectory = false
    @AppStorage("activeDirectory") private var activeDirectory = ""
    @AppStorage("closedDirectory") private var closedDirectory = ""
    @ObservedObject private var authService = GoogleAuthService.shared
    @StateObject private var whatsNewService = WhatsNewService.shared
    @StateObject private var onboardingService = OnboardingService.shared
    @State private var showWhatsNew = false
    @State private var showOnboarding = false
    
    enum SettingsSection: String, CaseIterable {
        case account = "Account e Mail"
        case sinistri = "Sinistri"
        case compagnie = "Compagnie"
        case billing = "Fatturazione"
        case ai = "Intelligenza Artificiale"
        case sync = "Sincronizzazione"
        case info = "Info"
        
        var title: String { rawValue }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Menu superiore
            Picker("", selection: $selectedSection) {
                ForEach(SettingsSection.allCases, id: \.self) { section in
                    Text(section.title)
                        .tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
            
            // Contenuto scrollabile
            ScrollView {
                VStack(spacing: 20) {
                    switch selectedSection {
                    case .account:
                        AccountSettingsView()
                        
                    case .sinistri:
                        SinistriSettingsView()
                        
                    case .compagnie:
                        CompagnieSettingsView()
                        
                    case .billing:
                        CompensationSettingsView()
                        
                    case .ai:
                        AISettingsView()

                    case .sync:
                        VStack(spacing: 20) {
                            HubSettingsView()
                            CloudSettingsView()
                        }
                        
                    case .info:
                        VStack(spacing: 20) {
                            GroupBox {
                                VStack(alignment: .leading, spacing: 16) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "doc.text.magnifyingglass")
                                            .font(.system(size: 40))
                                            .foregroundColor(.blue)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("PerX")
                                                .font(.title2.bold())
                                            
                                            if let update = whatsNewService.latestUpdate {
                                                Text("Versione \(update.version)")
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        
                                        Spacer()
                                    }
                                    
                                    Divider()
                                    
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Sistema di gestione sinistri professionale")
                                            .foregroundColor(.secondary)
                                        
                                        Text("Sviluppato per periti assicurativi italiani")
                                            .foregroundColor(.secondary)
                                            .font(.caption)
                                    }
                                }
                                .padding()
                            } label: {
                                Label("Informazioni App", systemImage: "info.circle")
                            }
                            
                            GroupBox {
                                VStack(alignment: .leading, spacing: 16) {
                                    Button {
                                        showOnboarding = true
                                    } label: {
                                        HStack {
                                            Label("Mostra Guida Introduttiva", systemImage: "book.circle")
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Divider()
                                    
                                    Button {
                                        showWhatsNew = true
                                    } label: {
                                        HStack {
                                            Label("Mostra Novità", systemImage: "sparkles")
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Divider()
                                    
                                    Button {
                                        whatsNewService.resetSeenUpdates()
                                    } label: {
                                        HStack {
                                            Label("Reset Aggiornamenti Visti", systemImage: "arrow.counterclockwise")
                                            Spacer()
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding()
                            } label: {
                                Label("Guida e Aggiornamenti", systemImage: "arrow.down.circle")
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView(isPresented: $showWhatsNew)
                .frame(minWidth: 900, minHeight: 700)
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
                .frame(minWidth: 800, minHeight: 600)
        }
    }
} 