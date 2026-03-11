//
//  CompagnieSettingsView.swift
//  PerX
//
//  Gestione parametri personalizzabili per ogni compagnia assicurativa.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CompagnieSettingsView: View {
    @StateObject private var settings = CompagniaSettingsService.shared
    @State private var expandedCompagnia: Compagnia?
    @State private var showingColorPicker = false
    @State private var tempColor = Color.blue
    @State private var showingLogoCrop = false
    @State private var logoImageToCrop: NSImage?
    @State private var compagniaForLogo: Compagnia?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                compagnieList
            }
            .padding(24)
        }
        .sheet(isPresented: $showingColorPicker) {
            if let comp = expandedCompagnia {
                ColorPickerView(selectedColor: $tempColor)
                    .onDisappear { updateColor(for: comp) }
            }
        }
        .sheet(isPresented: $showingLogoCrop) {
            if let img = logoImageToCrop, let comp = compagniaForLogo {
                LogoCropSheet(
                    image: img,
                    compagnia: comp,
                    onConfirm: { cropped in
                        settings.setLogoFromImage(comp, image: cropped)
                        showingLogoCrop = false
                        logoImageToCrop = nil
                        compagniaForLogo = nil
                    },
                    onCancel: {
                        showingLogoCrop = false
                        logoImageToCrop = nil
                        compagniaForLogo = nil
                    }
                )
            }
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Parametri Compagnie", systemImage: "building.columns.fill")
                .font(.title2.bold())
            Text("Personalizza regole, valori di riferimento e aspetto per ogni compagnia. Le modifiche sovrascrivono i valori di default.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var compagnieList: some View {
        VStack(spacing: 12) {
            ForEach(Compagnia.allCases.filter { $0 != .unknown }, id: \.self) { compagnia in
                compagniaCard(compagnia)
            }
        }
    }
    
    private func compagniaCard(_ compagnia: Compagnia) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                // Header espandibile
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        expandedCompagnia = expandedCompagnia == compagnia ? nil : compagnia
                        if expandedCompagnia == compagnia {
                            tempColor = settings.effectiveUiColor(compagnia)
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        // Logo o icona
                        logoPreview(for: compagnia)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(compagnia.rawValue)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("Sigla: \(compagnia.sigla)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if settings.hasOverride(for: compagnia) {
                            Text("Modificato")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .foregroundColor(.orange)
                                .cornerRadius(4)
                        }
                        Image(systemName: expandedCompagnia == compagnia ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .padding(16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                if expandedCompagnia == compagnia {
                    Divider()
                        .padding(.horizontal)
                    compagniaEditor(compagnia)
                        .padding(16)
                }
            }
        }
    }
    
    @ViewBuilder
    private func logoPreview(for compagnia: Compagnia) -> some View {
        Group {
            if let url = settings.logoURL(for: compagnia),
               let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Circle()
                    .fill(settings.effectiveUiColor(compagnia).opacity(0.3))
                    .overlay(
                        Image(systemName: compagnia.uiIconSystemName)
                            .font(.title2)
                            .foregroundColor(settings.effectiveUiColor(compagnia))
                    )
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
    }
    
    @ViewBuilder
    private func compagniaEditor(_ compagnia: Compagnia) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Sezione Logo
            logoSection(compagnia)
            
            Divider()
            
            // Sezione Regole
            sectionTitle("Regole Chiusura")
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Usa comunica esito per data atto", isOn: bindingUsaComunicaEsito(compagnia))
                Toggle("Sempre allega fulminazione", isOn: bindingSempreAllegaFulminazione(compagnia))
                Toggle("Atto sempre richiesto", isOn: bindingAttoSempreRichiesto(compagnia))
            }
            
            Divider()
            
            // File Obbligatori
            sectionTitle("File obbligatori per chiusura")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 8) {
                ForEach(TipoFileCompagnia.allCases, id: \.self) { tipo in
                    Toggle(tipoLabel(tipo), isOn: bindingFileObbligatorio(compagnia, tipo))
                }
            }
            
            Divider()
            
            // Range e Target
            sectionTitle("Range e Target")
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                GridRow {
                    rangeLiquidatoFields(compagnia)
                    rangePLFields(compagnia)
                }
                GridRow {
                    targetLiquidatoField(compagnia)
                    targetNegativeField(compagnia)
                    targetTempoField(compagnia)
                    targetConcordateField(compagnia)
                }
            }
            
            Divider()
            
            // Aspetto
            sectionTitle("Aspetto")
            HStack(spacing: 24) {
                colorPickerButton(compagnia)
                shortLabelField(compagnia)
            }
            
            Divider()
            
            // Azioni
            HStack {
                Spacer()
                Button(role: .destructive) {
                    settings.resetOverride(for: compagnia)
                    expandedCompagnia = nil
                } label: {
                    Label("Ripristina default", systemImage: "arrow.counterclockwise")
                }
            }
        }
    }
    
    private func logoSection(_ compagnia: Compagnia) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Logo")
            HStack(spacing: 16) {
                logoPreview(for: compagnia)
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Button {
                            selectLogo(for: compagnia)
                        } label: {
                            Label("Carica logo", systemImage: "photo.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)
                        
                        if settings.logoURL(for: compagnia) != nil {
                            Button(role: .destructive) {
                                settings.clearLogo(for: compagnia)
                            } label: {
                                Label("Rimuovi", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    Text("Formati: PNG, JPG, GIF. Il logo sarà ritagliato in forma circolare.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(10)
        }
    }
    
    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.secondary)
    }
    
    private func colorPickerButton(_ compagnia: Compagnia) -> some View {
        HStack(spacing: 8) {
            Text("Colore")
                .frame(width: 80, alignment: .leading)
            Button {
                expandedCompagnia = compagnia
                tempColor = settings.effectiveUiColor(compagnia)
                showingColorPicker = true
            } label: {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(settings.effectiveUiColor(compagnia))
                        .frame(width: 28, height: 28)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                    Text("Modifica")
                        .font(.subheadline)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
    }
    
    private func shortLabelField(_ compagnia: Compagnia) -> some View {
        HStack(spacing: 8) {
            Text("Label breve")
                .frame(width: 80, alignment: .leading)
            TextField("Es. Zurich", text: bindingShortLabel(compagnia))
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)
        }
    }
    
    private func selectLogo(for compagnia: Compagnia) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Seleziona il logo della compagnia"
        
        if panel.runModal() == .OK, let url = panel.url {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            
            if let image = NSImage(contentsOf: url) {
                logoImageToCrop = image
                compagniaForLogo = compagnia
                showingLogoCrop = true
            }
        }
    }
    
    private func tipoLabel(_ tipo: TipoFileCompagnia) -> String {
        switch tipo {
        case .perizia: return "Perizia"
        case .foto: return "Foto"
        case .atto: return "Atto"
        case .giustificativi: return "Giustificativi"
        case .verbale: return "Verbale"
        case .fulminazione: return "Fulminazione"
        case .altro: return "Altro"
        }
    }
    
    private func bindingUsaComunicaEsito(_ compagnia: Compagnia) -> Binding<Bool> {
        Binding(
            get: { settings.effectiveUsaComunicaEsitoPerAtto(compagnia) },
            set: { settings.setUsaComunicaEsitoPerAtto(compagnia, $0) }
        )
    }
    
    private func bindingSempreAllegaFulminazione(_ compagnia: Compagnia) -> Binding<Bool> {
        Binding(
            get: { settings.effectiveSempreAllegaFulminazione(compagnia) },
            set: { settings.setSempreAllegaFulminazione(compagnia, $0) }
        )
    }
    
    private func bindingAttoSempreRichiesto(_ compagnia: Compagnia) -> Binding<Bool> {
        Binding(
            get: { settings.effectiveAttoSempreRichiesto(compagnia) },
            set: { settings.setAttoSempreRichiesto(compagnia, $0) }
        )
    }
    
    private func bindingFileObbligatorio(_ compagnia: Compagnia, _ tipo: TipoFileCompagnia) -> Binding<Bool> {
        Binding(
            get: { settings.effectiveFileObbligatoriChiusura(compagnia).contains(tipo) },
            set: { isOn in
                var list = settings.effectiveFileObbligatoriChiusura(compagnia)
                if isOn {
                    if !list.contains(tipo) { list.append(tipo) }
                } else {
                    list.removeAll { $0 == tipo }
                }
                settings.setFileObbligatoriChiusura(compagnia, list)
            }
        )
    }
    
    private func rangeLiquidatoFields(_ compagnia: Compagnia) -> some View {
        let eff = settings.effectiveRangeLiquidatoMedio(compagnia)
        return HStack(spacing: 8) {
            Text("Liquidato medio")
                .frame(width: 110, alignment: .leading)
            TextField("Min", value: Binding(get: { eff.min }, set: { settings.setRangeLiquidatoMedio(compagnia, min: $0, max: eff.max) }), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
            TextField("Max", value: Binding(get: { eff.max }, set: { settings.setRangeLiquidatoMedio(compagnia, min: eff.min, max: $0) }), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
        }
    }
    
    private func rangePLFields(_ compagnia: Compagnia) -> some View {
        let eff = settings.effectiveRangePL(compagnia)
        return HStack(spacing: 8) {
            Text("PL")
                .frame(width: 110, alignment: .leading)
            TextField("Min", value: Binding(get: { eff.min }, set: { settings.setRangePL(compagnia, min: $0, max: eff.max) }), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
            TextField("Max", value: Binding(get: { eff.max }, set: { settings.setRangePL(compagnia, min: eff.min, max: $0) }), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
        }
    }
    
    private func targetLiquidatoField(_ compagnia: Compagnia) -> some View {
        HStack(spacing: 8) {
            Text("Target liquidato")
                .frame(width: 110, alignment: .leading)
            TextField("", value: Binding(get: { settings.effectiveTargetLiquidatoMedio(compagnia) }, set: { settings.setTargetLiquidatoMedio(compagnia, $0) }), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
        }
    }
    
    private func targetNegativeField(_ compagnia: Compagnia) -> some View {
        HStack(spacing: 8) {
            Text("Target negative %")
                .frame(width: 110, alignment: .leading)
            TextField("", value: Binding(get: { settings.effectiveTargetNegative(compagnia) }, set: { settings.setTargetNegative(compagnia, $0) }), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
        }
    }
    
    private func targetTempoField(_ compagnia: Compagnia) -> some View {
        HStack(spacing: 8) {
            Text("Target tempo giorni")
                .frame(width: 110, alignment: .leading)
            TextField("", value: Binding(get: { settings.effectiveTargetTempoGestione(compagnia) }, set: { settings.setTargetTempoGestione(compagnia, $0) }), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
        }
    }
    
    private func targetConcordateField(_ compagnia: Compagnia) -> some View {
        HStack(spacing: 8) {
            Text("Target concordate %")
                .frame(width: 110, alignment: .leading)
            TextField("", value: Binding(get: { settings.effectiveTargetConcordate(compagnia) }, set: { settings.setTargetConcordate(compagnia, $0) }), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
        }
    }
    
    private func bindingShortLabel(_ compagnia: Compagnia) -> Binding<String> {
        Binding(
            get: { settings.effectiveShortLabel(compagnia) },
            set: { settings.setShortLabel(compagnia, $0.isEmpty ? nil : $0) }
        )
    }
    
    private func updateColor(for compagnia: Compagnia) {
        settings.setUiColor(compagnia, tempColor)
    }
}
