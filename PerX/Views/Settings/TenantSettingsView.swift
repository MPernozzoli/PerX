import SwiftUI
import MapKit

struct TenantSettingsView: View {
    @StateObject private var currentUserService = CurrentUserService.shared
    @StateObject private var apiService = TenantSettingsAPIService.shared
    @State private var tenantSettings = TenantMailSettingsService.shared.settings
    @State private var selectedTenantId: String = ""
    @State private var tenantName = ""
    @State private var tenantSlug = ""
    @State private var internalDomainsText = ""
    @State private var internalEmailsText = ""
    @State private var systemEmailsText = ""
    @State private var secretariatEmailsText = ""
    @State private var claimGaranzieText = ""
    @State private var defaultClaimGaranzia = "Fenomeno Elettrico"
    @State private var catSettings = TenantCATSettings.default
    @State private var providerSettings = TenantInspectionProviderSettings.default
    @State private var territoryCameraPosition: MapCameraPosition = .automatic
    @State private var hasChanges = false
    @State private var saveMessage: String?
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var isPopulating = false

    var body: some View {
        Group {
            if currentUserService.canManageTenantSettings {
                ScrollView {
                    VStack(spacing: 20) {
                        headerCard
                        if currentUserService.isPlatformAdmin && !apiService.availableTenants.isEmpty {
                            tenantPickerCard
                        }
                        identityCard
                        mailCard
                        claimsCard
                        catPlannerCard
                        catTerritoryMapCard
                        catTechniciansCard
                        catMunicipalitiesCard
                        if currentUserService.isPlatformAdmin {
                            providerCredentialsCard
                        } else {
                            providerCredentialsNoticeCard
                        }
                        actionsCard
                    }
                    .padding()
                }
                .task {
                    await bootstrap()
                }
                .onChange(of: tenantName) { _, _ in markDirty() }
                .onChange(of: tenantSlug) { _, _ in markDirty() }
                .onChange(of: internalDomainsText) { _, _ in markDirty() }
                .onChange(of: internalEmailsText) { _, _ in markDirty() }
                .onChange(of: systemEmailsText) { _, _ in markDirty() }
                .onChange(of: secretariatEmailsText) { _, _ in markDirty() }
                .onChange(of: claimGaranzieText) { _, _ in markDirty() }
                .onChange(of: defaultClaimGaranzia) { _, _ in markDirty() }
                .onChange(of: catSettings) { _, _ in
                    markDirty()
                    updateTerritoryMap()
                }
                .onChange(of: providerSettings) { _, _ in
                    guard currentUserService.isPlatformAdmin else { return }
                    markDirty()
                }
            } else {
                ContentUnavailableView(
                    "Accesso riservato",
                    systemImage: "lock.shield",
                    description: Text("Questa sezione è visibile solo all'admin generale dell'app e all'admin del tenant.")
                )
                .padding()
            }
        }
    }

    private var headerCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tenantName.isEmpty ? "Tenant" : tenantName)
                            .font(.title3.bold())

                        HStack(spacing: 12) {
                            permissionBadge(
                                title: currentUserService.isPlatformAdmin ? "Admin Generale" : "Admin Tenant",
                                color: currentUserService.isPlatformAdmin ? Color(hex: "B45309") : .blue
                            )

                            permissionBadge(
                                title: "Slug: \(tenantSlug.isEmpty ? "non impostato" : tenantSlug)",
                                color: Color(hex: "0F766E")
                            )

                            if currentUserService.isPlatformAdmin {
                                permissionBadge(
                                    title: "Chiavi provider Pynkstudio",
                                    color: Color(hex: "7C3AED")
                                )
                            }
                        }
                    }

                    Spacer()

                    if isLoading {
                        ProgressView()
                    }
                }

                Text("Gestisci identità tenant, rete CAT, copertura territoriale e parametri planner. Le credenziali delle integrazioni esterne restano configurabili solo dall'admin generale Pynkstudio.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let lastSyncError = apiService.lastSyncError, !lastSyncError.isEmpty {
                    Text(lastSyncError)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        } label: {
            Label("Gestione Tenant", systemImage: "building.2.crop.circle")
        }
    }

    private var tenantPickerCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Tenant target")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Tenant", selection: $selectedTenantId) {
                    ForEach(apiService.availableTenants) { tenant in
                        Text("\(tenant.name) (\(tenant.slug))")
                            .tag(tenant.id)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedTenantId) { _, _ in
                    Task { await loadSettingsFromBackend() }
                }
            }
            .padding()
        } label: {
            Label("Selezione Tenant", systemImage: "rectangle.stack.badge.person.crop")
        }
    }

    private var identityCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Nome Tenant")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Studio Peritale Rossi", text: $tenantName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Slug Tenant")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("studio-peritale-rossi", text: $tenantSlug)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding()
        } label: {
            Label("Identità Tenant", systemImage: "person.text.rectangle")
        }
    }

    private var mailCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                mailField(
                    title: "Domini interni",
                    text: $internalDomainsText,
                    placeholder: "studio.it, perizie.it",
                    help: "Usati per riconoscere le comunicazioni interne del tenant."
                )

                mailField(
                    title: "Email interne",
                    text: $internalEmailsText,
                    placeholder: "mario@studio.it, laura@studio.it",
                    help: "Caselle personali o condivise interne allo studio."
                )

                mailField(
                    title: "Mail di sistema",
                    text: $systemEmailsText,
                    placeholder: "noreply@studio.it, pratiche@studio.it",
                    help: "Identità applicative o caselle tecniche configurate per il tenant."
                )

                mailField(
                    title: "Mail segreteria",
                    text: $secretariatEmailsText,
                    placeholder: "segreteria@studio.it",
                    help: "Usate per riconoscere i flussi di segreteria dello studio."
                )
            }
            .padding()
        } label: {
            Label("Configurazione Mail Tenant", systemImage: "envelope.badge")
        }
    }

    private var claimsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                mailField(
                    title: "Garanzie sinistri",
                    text: $claimGaranzieText,
                    placeholder: "Fenomeno Elettrico",
                    help: "Enum tenant condiviso per i sinistri e per le preferenze di assegnazione automatica."
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Garanzia predefinita")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("Garanzia predefinita", selection: $defaultClaimGaranzia) {
                        ForEach(availableClaimGaranzie, id: \.self) { garanzia in
                            Text(garanzia).tag(garanzia)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .padding()
        } label: {
            Label("Garanzie Tenant", systemImage: "shield.lefthalf.filled")
        }
    }

    private var catPlannerCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Attiva rete CAT per sopralluoghi", isOn: $catSettings.enabled)

                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Stepper(
                            "Generazione route: \(String(format: "%02d:00", catSettings.planner.routeGenerationHour))",
                            value: $catSettings.planner.routeGenerationHour,
                            in: 0...23
                        )
                        Stepper(
                            "Review CAT: \(catSettings.planner.routeReviewWindowMinutes) minuti",
                            value: $catSettings.planner.routeReviewWindowMinutes,
                            in: 15...180,
                            step: 15
                        )
                        Stepper(
                            "Slot disponibilità: \(catSettings.planner.availabilitySlotMinutes) minuti",
                            value: $catSettings.planner.availabilitySlotMinutes,
                            in: 60...240,
                            step: 30
                        )
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Stepper(
                            "Margine finestre: \(catSettings.planner.availabilityTolerancePercent)%",
                            value: $catSettings.planner.availabilityTolerancePercent,
                            in: 0...100,
                            step: 5
                        )
                        Stepper(
                            "Fuori zona max: \(catSettings.planner.maxOutsideZoneKilometers) km",
                            value: $catSettings.planner.maxOutsideZoneKilometers,
                            in: 0...150,
                            step: 5
                        )
                    }
                }

                Text("Questi parametri governano la mock infrastructure del planner: proposta alle 09:00, disponibilità in slot, margine sulle finestre assicurato e sopralluoghi fuori zona entro soglia.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        } label: {
            Label("Planner Sopralluoghi CAT", systemImage: "calendar.badge.clock")
        }
    }

    private var catTerritoryMapCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Mappa rete CAT")
                            .font(.headline)
                        Text("POI CAT, comuni di competenza e copertura province/regioni del tenant.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 10) {
                        summaryChip("\(catSettings.technicians.count) CAT", color: .red)
                        summaryChip("\(catSettings.municipalities.count) comuni", color: .blue)
                        summaryChip("\(coveredProvinces.count) province", color: .green)
                    }
                }

                Map(position: $territoryCameraPosition) {
                    ForEach(territoryAnnotations) { item in
                        Marker(item.title, coordinate: item.coordinate)
                            .tint(item.tint)
                    }
                }
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Province")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        Text(coveredProvinces.joined(separator: ", "))
                            .font(.caption)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Regioni")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        Text(coveredRegions.joined(separator: ", "))
                            .font(.caption)
                    }
                }
            }
            .padding()
        } label: {
            Label("Territorio CAT", systemImage: "map")
        }
    }

    private var catTechniciansCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Posizioni CAT / POI")
                        .font(.headline)
                    Spacer()
                    Button {
                        catSettings.technicians.append(
                            TenantCATPOI.template(index: catSettings.technicians.count + 1)
                        )
                    } label: {
                        Label("Aggiungi CAT", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }

                if catSettings.technicians.isEmpty {
                    Text("Nessun CAT configurato.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    ForEach($catSettings.technicians) { $technician in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                TextField("Nome CAT", text: $technician.displayName)
                                    .textFieldStyle(.roundedBorder)
                                TextField("Email/utente", text: $technician.email)
                                    .textFieldStyle(.roundedBorder)
                                Button(role: .destructive) {
                                    removeTechnician(id: technician.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }

                            HStack {
                                TextField("Comune base", text: $technician.comune)
                                TextField("Provincia", text: $technician.provincia)
                                TextField("Regione", text: $technician.regione)
                            }
                            .textFieldStyle(.roundedBorder)

                            HStack {
                                TextField("Latitudine", value: $technician.latitude, format: .number.precision(.fractionLength(4)))
                                TextField("Longitudine", value: $technician.longitude, format: .number.precision(.fractionLength(4)))
                            }
                            .textFieldStyle(.roundedBorder)

                            TextField(
                                "Comuni assegnati",
                                text: Binding(
                                    get: { technician.assignedMunicipalities.joined(separator: ", ") },
                                    set: { technician.assignedMunicipalities = splitValues($0) }
                                ),
                                axis: .vertical
                            )
                            .textFieldStyle(.roundedBorder)

                            TextField("Note operative", text: $technician.note, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
            .padding()
        } label: {
            Label("Rete Tecnici CAT", systemImage: "mappin.circle")
        }
    }

    private var catMunicipalitiesCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Comuni / Province / Regioni")
                        .font(.headline)
                    Spacer()
                    Button {
                        catSettings.municipalities.append(
                            TenantCATMunicipality.template(index: catSettings.municipalities.count + 1)
                        )
                    } label: {
                        Label("Aggiungi comune", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }

                ForEach($catSettings.municipalities) { $municipality in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            TextField("Comune", text: $municipality.comune)
                            TextField("Provincia", text: $municipality.provincia)
                            TextField("Regione", text: $municipality.regione)
                            Button(role: .destructive) {
                                removeMunicipality(id: municipality.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        .textFieldStyle(.roundedBorder)

                        HStack {
                            TextField("Latitudine", value: $municipality.latitude, format: .number.precision(.fractionLength(4)))
                            TextField("Longitudine", value: $municipality.longitude, format: .number.precision(.fractionLength(4)))
                            Stepper("Priorità \(municipality.priority)", value: $municipality.priority, in: 1...3)
                        }

                        TextField(
                            "CAT assegnati (email/utenti separati da virgola)",
                            text: Binding(
                                get: { municipality.assignedCATEmails.joined(separator: ", ") },
                                set: { municipality.assignedCATEmails = splitValues($0) }
                            ),
                            axis: .vertical
                        )
                        .textFieldStyle(.roundedBorder)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.45))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding()
        } label: {
            Label("Assegnazione Territori", systemImage: "globe.europe.africa")
        }
    }

    private var providerCredentialsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Text("Configurazione riservata a Pynkstudio. Queste chiavi abilitano mappe, route, geocoding e messaging del flusso sopralluoghi.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                providerPickerRow(
                    title: "Provider mappe",
                    selection: $providerSettings.mapProvider,
                    options: [
                        ("google_maps", "Google Maps"),
                        ("mapbox", "Mapbox"),
                        ("osm", "OpenStreetMap")
                    ]
                )

                SecureField("API Key mappe", text: $providerSettings.mapsAPIKey)
                    .textFieldStyle(.roundedBorder)

                providerPickerRow(
                    title: "Provider routing",
                    selection: $providerSettings.routingProvider,
                    options: [
                        ("google_routes", "Google Routes"),
                        ("mapbox_directions", "Mapbox Directions"),
                        ("ors", "OpenRouteService")
                    ]
                )

                SecureField("API Key routing", text: $providerSettings.routingAPIKey)
                    .textFieldStyle(.roundedBorder)

                providerPickerRow(
                    title: "Provider geocoding",
                    selection: $providerSettings.geocodingProvider,
                    options: [
                        ("google_geocoding", "Google Geocoding"),
                        ("mapbox_geocoding", "Mapbox Geocoding"),
                        ("nominatim", "Nominatim")
                    ]
                )

                SecureField("API Key geocoding", text: $providerSettings.geocodingAPIKey)
                    .textFieldStyle(.roundedBorder)

                providerPickerRow(
                    title: "Provider messaging",
                    selection: $providerSettings.messagingProvider,
                    options: [
                        ("twilio", "Twilio"),
                        ("messente", "Messente"),
                        ("custom", "Custom Gateway")
                    ]
                )

                SecureField("API Key messaging", text: $providerSettings.messagingAPIKey)
                    .textFieldStyle(.roundedBorder)
            }
            .padding()
        } label: {
            Label("Provider e Chiavi Sopralluoghi", systemImage: "key.horizontal")
        }
    }

    private var providerCredentialsNoticeCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Le chiavi Google Maps e le altre credenziali software necessarie al flusso sopralluoghi sono gestite esclusivamente dall'admin generale Pynkstudio.")
                    .font(.subheadline)
                Text("Il tenant admin può configurare rete CAT, planner e territori, ma non può inserire o modificare segreti di integrazione.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        } label: {
            Label("Credenziali Provider", systemImage: "lock.fill")
        }
    }

    private var actionsCard: some View {
        GroupBox {
            HStack {
                if let saveMessage {
                    Text(saveMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isSaving {
                    ProgressView()
                }

                Button("Ripristina") {
                    Task { await loadSettingsFromBackend() }
                }
                .buttonStyle(.bordered)

                Button("Salva") {
                    Task { await saveSettings() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasChanges || isSaving)
            }
            .padding()
        } label: {
            Label("Azioni", systemImage: "square.and.arrow.down")
        }
    }

    private func permissionBadge(title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.14))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private func summaryChip(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.14))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private func mailField(
        title: String,
        text: Binding<String>,
        placeholder: String,
        help: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            TextField(placeholder, text: text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            Text(help)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private func providerPickerRow(
        title: String,
        selection: Binding<String>,
        options: [(String, String)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Picker(title, selection: selection) {
                ForEach(options, id: \.0) { option in
                    Text(option.1).tag(option.0)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var territoryAnnotations: [TenantTerritoryAnnotation] {
        let technicianAnnotations = catSettings.technicians.map {
            TenantTerritoryAnnotation(
                id: "tech-\($0.id)",
                title: $0.displayName,
                coordinate: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude),
                tint: .red
            )
        }

        let municipalityAnnotations = catSettings.municipalities.map {
            TenantTerritoryAnnotation(
                id: "mun-\($0.id)",
                title: $0.comune,
                coordinate: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude),
                tint: $0.priority == 1 ? .blue : .green
            )
        }

        return technicianAnnotations + municipalityAnnotations
    }

    private var coveredProvinces: [String] {
        Array(Set(catSettings.municipalities.map(\.provincia).filter { !$0.isEmpty })).sorted()
    }

    private var coveredRegions: [String] {
        Array(Set(catSettings.municipalities.map(\.regione).filter { !$0.isEmpty })).sorted()
    }

    private func updateTerritoryMap() {
        guard !territoryAnnotations.isEmpty else {
            territoryCameraPosition = .automatic
            return
        }

        let latitudes = territoryAnnotations.map(\.coordinate.latitude)
        let longitudes = territoryAnnotations.map(\.coordinate.longitude)
        guard let minLat = latitudes.min(),
              let maxLat = latitudes.max(),
              let minLon = longitudes.min(),
              let maxLon = longitudes.max() else {
            territoryCameraPosition = .automatic
            return
        }

        territoryCameraPosition = .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: (minLat + maxLat) / 2,
                    longitude: (minLon + maxLon) / 2
                ),
                span: MKCoordinateSpan(
                    latitudeDelta: max((maxLat - minLat) * 1.8, 0.18),
                    longitudeDelta: max((maxLon - minLon) * 1.8, 0.18)
                )
            )
        )
    }

    private func removeTechnician(id: String) {
        catSettings.technicians.removeAll { $0.id == id }
    }

    private func removeMunicipality(id: String) {
        catSettings.municipalities.removeAll { $0.id == id }
    }

    private func loadSettings() {
        isPopulating = true
        defer { isPopulating = false }

        tenantSettings = TenantMailSettingsService.shared.settings
        tenantName = tenantSettings.tenantName
        tenantSlug = tenantSettings.tenantSlug
        internalDomainsText = tenantSettings.internalDomains.joined(separator: ", ")
        internalEmailsText = tenantSettings.internalEmails.joined(separator: ", ")
        systemEmailsText = tenantSettings.systemEmails.joined(separator: ", ")
        secretariatEmailsText = tenantSettings.secretariatEmails.joined(separator: ", ")
        claimGaranzieText = tenantSettings.claimGaranzie.joined(separator: ", ")
        defaultClaimGaranzia = tenantSettings.defaultClaimGaranzia
        catSettings = tenantSettings.catSettings
        providerSettings = tenantSettings.providerSettings ?? .default
        hasChanges = false
        saveMessage = nil
        updateTerritoryMap()
    }

    private func saveSettings() async {
        isSaving = true
        defer { isSaving = false }

        tenantSettings.tenantName = tenantName.trimmingCharacters(in: .whitespacesAndNewlines)
        tenantSettings.tenantSlug = tenantSlug
        tenantSettings.internalDomains = splitValues(internalDomainsText)
        tenantSettings.internalEmails = splitValues(internalEmailsText)
        tenantSettings.systemEmails = splitValues(systemEmailsText)
        tenantSettings.secretariatEmails = splitValues(secretariatEmailsText)
        tenantSettings.claimGaranzie = splitValues(claimGaranzieText)
        if !tenantSettings.claimGaranzie.contains(defaultClaimGaranzia) {
            defaultClaimGaranzia = tenantSettings.claimGaranzie.first ?? "Fenomeno Elettrico"
        }
        tenantSettings.defaultClaimGaranzia = defaultClaimGaranzia
        tenantSettings.catSettings = catSettings
        tenantSettings.providerSettings = currentUserService.isPlatformAdmin ? providerSettings : nil

        let targetTenantId = selectedTenantId.isEmpty ? nil : selectedTenantId
        let saved = await apiService.saveTenantSettings(tenantSettings, targetTenantId: targetTenantId)
        tenantSettings = saved
        TenantMailSettingsService.shared.settings = saved
        loadSettings()
        saveMessage = apiService.lastSyncError == nil
            ? "Impostazioni tenant salvate su backend"
            : "Impostazioni salvate localmente, sync backend non riuscito"
    }

    private func splitValues(_ rawValue: String) -> [String] {
        rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var availableClaimGaranzie: [String] {
        let values = splitValues(claimGaranzieText)
        return values.isEmpty ? ["Fenomeno Elettrico"] : values
    }

    private func bootstrap() async {
        if currentUserService.isPlatformAdmin {
            await apiService.refreshAvailableTenantsIfNeeded()
            if selectedTenantId.isEmpty {
                selectedTenantId = apiService.availableTenants.first?.id ?? ""
            }
        }
        await loadSettingsFromBackend()
    }

    private func loadSettingsFromBackend() async {
        isLoading = true
        defer { isLoading = false }

        let targetTenantId = selectedTenantId.isEmpty ? nil : selectedTenantId
        let loaded = await apiService.loadTenantSettings(targetTenantId: targetTenantId)
        tenantSettings = loaded
        TenantMailSettingsService.shared.settings = loaded
        loadSettings()
        if apiService.lastSyncError == nil {
            saveMessage = "Configurazione tenant caricata dal backend"
        } else {
            saveMessage = "Uso configurazione locale: \(apiService.lastSyncError ?? "")"
        }
    }

    private func markDirty() {
        guard !isPopulating else { return }
        hasChanges = true
        saveMessage = nil
    }
}

private struct TenantTerritoryAnnotation: Identifiable {
    let id: String
    let title: String
    let coordinate: CLLocationCoordinate2D
    let tint: Color
}
