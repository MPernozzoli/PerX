import SwiftUI

struct TelefonoCommunicationView: View {
    @State private var selectedFilter: CallFilter = .recenti
    @State private var searchText = ""
    @State private var resolution = CommunicationResolution(selected: nil, candidates: [], isAmbiguous: false)
    @State private var callState: CommunicationCallState = .pending
    @State private var activeCall: CommunicationCallLogItem?
    @State private var activeLiveKitToken: CommunicationLiveKitToken?
    @State private var errorMessage: String?
    @State private var recentCalls = TelefonoCommunicationView.seedCalls
    @State private var showKeypad = false
    @FocusState private var searchFocused: Bool

    private var isTouchIdiom: Bool {
        #if os(macOS)
        return false
        #else
        return true
        #endif
    }

    private let resolver: CommunicationDestinationResolving
    private let context: CommunicationContext
    private let suggestions: [CommunicationContactSuggestion]
    private let frequentContacts: [CommunicationContactSuggestion]
    private let myExtension: String?
    private let myExtensionEnabled: Bool

    init(
        resolver: CommunicationDestinationResolving = CommunicationDestinationResolver(),
        context: CommunicationContext = CommunicationContext(tenantId: "default", claimId: nil, claimReference: nil, source: "telefono-ui"),
        suggestions: [CommunicationContactSuggestion] = TelefonoCommunicationView.seedSuggestions,
        frequentContacts: [CommunicationContactSuggestion] = TelefonoCommunicationView.seedFrequentContacts,
        myExtension: String? = nil,
        myExtensionEnabled: Bool = true
    ) {
        self.resolver = resolver
        self.context = context
        self.suggestions = suggestions
        self.frequentContacts = frequentContacts
        self.myExtension = myExtension
        self.myExtensionEnabled = myExtensionEnabled
    }

    var body: some View {
        HStack(spacing: 0) {
            callList
                .frame(minWidth: 300, idealWidth: 360, maxWidth: 420)

            Divider()

            VStack(spacing: 0) {
                header
                Divider()
                dialerAndContacts
            }
        }
        .navigationTitle("Telefono")
        .onChange(of: searchText) { _, newValue in
            resolve(newValue)
        }
        .onChange(of: callState) { _, newState in
            switch newState {
            case .ringing:
                RingbackPlayer.shared.start()
            case .active, .failed, .completed:
                RingbackPlayer.shared.stop()
            default:
                break
            }
        }
        .onDisappear {
            RingbackPlayer.shared.stop()
        }
        .sheet(item: $activeLiveKitToken) { token in
            CommunicationLiveKitCallView(token: token, displayName: activeCall?.displayName ?? "Chiamata PerX") {
                activeLiveKitToken = nil
                callState = .completed
            }
        }
        .alert("Errore chiamata", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var callList: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedFilter) {
                ForEach(CallFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            List(filteredCalls) { call in
                callRow(call)
            }
            .listStyle(.plain)
            .overlay {
                if filteredCalls.isEmpty {
                    ContentUnavailableView("Nessuna chiamata", systemImage: "phone", description: Text("Le chiamate appariranno qui"))
                }
            }
        }
    }

    @ViewBuilder
    private var myExtensionBanner: some View {
        if let myExtension, !myExtension.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: myExtensionEnabled ? "number.circle.fill" : "number.circle")
                    .foregroundStyle(myExtensionEnabled ? Color.accentColor : .secondary)
                Text("Tuo interno:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(myExtension)
                    .font(.caption.monospaced().weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                if !myExtensionEnabled {
                    Text("non attivo")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Spacer()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            myExtensionBanner
            HStack(spacing: 12) {
                Image(systemName: activeCall == nil ? "phone.circle.fill" : "phone.connection.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(activeCall == nil ? Color.accentColor : .green)

                VStack(alignment: .leading, spacing: 4) {
                    Text(activeCall?.displayName ?? "Pronto per chiamare")
                        .font(.title3.bold())
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let activeCall {
                    Button {
                        openClaim(activeCall)
                    } label: {
                        Label("Apri sinistro", systemImage: "folder")
                    }
                    .disabled(activeCall.effectiveClaimId == nil)
                }
            }

            if let selected = resolution.selected {
                Label("\(selected.displayName) - \(selected.transportLabel)", systemImage: icon(for: selected.destinationType))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if resolution.isAmbiguous {
                Label("Destinazione ambigua: scegli una candidata", systemImage: "questionmark.circle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
    }

    private var dialerAndContacts: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                dialInputRow
                    .padding(.top)

                if isTouchIdiom || showKeypad {
                    keypad
                }

                if !resolution.candidates.isEmpty {
                    sectionTitle("Destinazioni risolte")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                        ForEach(resolution.candidates) { destination in
                            destinationCard(destination)
                        }
                    }
                }

                sectionTitle("Contatti suggeriti")
                contactGrid(suggestions)

                sectionTitle("Contatti frequenti")
                contactGrid(frequentContacts)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    private var dialInputRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Numero, interno, contatto, team o link", text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                #if os(macOS)
                .onSubmit {
                    Task { await callSelectedDestination() }
                }
                #endif

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    resolution = CommunicationResolution(selected: nil, candidates: [], isAmbiguous: false)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            if !isTouchIdiom {
                Button {
                    showKeypad.toggle()
                } label: {
                    Image(systemName: showKeypad ? "circle.grid.3x3.fill" : "circle.grid.3x3")
                        .foregroundStyle(showKeypad ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(showKeypad ? "Nascondi tastierino" : "Mostra tastierino")
            }

            Button {
                Task { await callSelectedDestination() }
            } label: {
                Label("Chiama", systemImage: "phone.fill")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(callableDestination == nil)
            .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var keypad: some View {
        let buttonSize: CGFloat = isTouchIdiom ? 56 : 38
        let buttonFont: Font = isTouchIdiom ? .title2.bold() : .body.weight(.semibold)
        let spacing: CGFloat = isTouchIdiom ? 10 : 6

        return VStack(spacing: spacing) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: 3), spacing: spacing) {
                ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", "+", "0", "#"], id: \.self) { value in
                    Button {
                        searchText.append(value)
                    } label: {
                        Text(value)
                            .font(buttonFont)
                            .frame(maxWidth: .infinity, minHeight: buttonSize)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: isTouchIdiom ? .infinity : 320, alignment: .leading)
        }
    }

    private func contactGrid(_ contacts: [CommunicationContactSuggestion]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
            ForEach(contacts) { contact in
                Button {
                    searchText = contact.rawDestination
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: icon(for: contact.destinationTypeHint ?? .externalPhone))
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(contact.displayName).font(.subheadline.bold())
                            Text(contact.detail).font(.caption).foregroundStyle(.secondary)
                            if let claimReference = contact.claimReference {
                                Text("Sinistro \(claimReference)").font(.caption2).foregroundStyle(.blue)
                            }
                        }
                        Spacer()
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func destinationCard(_ destination: CommunicationDestination) -> some View {
        Button {
            resolution = CommunicationResolution(selected: destination, candidates: resolution.candidates, isAmbiguous: false)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon(for: destination.destinationType))
                    Text(destination.displayName).font(.subheadline.bold())
                    Spacer()
                }
                Text(destination.transportLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if destination.contextClaimId != nil {
                    Label("Contesto sinistro collegato", systemImage: "folder")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(resolution.selected == destination ? 0.18 : 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func callRow(_ call: CommunicationCallLogItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: callIcon(call))
                .foregroundStyle(call.direction == .missed || call.state == .missed ? .red : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(call.displayName).font(.subheadline.bold())
                Text(call.subtitle).font(.caption).foregroundStyle(.secondary)
                if let claimContext = call.effectiveClaimContext {
                    claimBadge(claimContext)
                    if let insuredName = claimContext.insuredName, !insuredName.isEmpty {
                        Text(insuredName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if let claimReference = call.claimReference {
                    Text("Sinistro \(claimReference)").font(.caption2).foregroundStyle(.blue)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(call.startedAt, style: .time).font(.caption)
                Text(call.state.rawValue).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .padding(.top, 4)
    }

    private func claimBadge(_ claimContext: CommunicationClaimContext) -> some View {
        let presentation = CommunicationClaimStatusPresentation(status: claimContext.claimStatus)
        return HStack(spacing: 4) {
            Image(systemName: presentation.icon)
            Text("Sinistro \(claimContext.displayReference)")
        }
        .font(.caption2)
        .foregroundStyle(presentation.color)
    }

    private var filteredCalls: [CommunicationCallLogItem] {
        switch selectedFilter {
        case .recenti: return recentCalls
        case .perse: return recentCalls.filter { $0.direction == .missed || $0.state == .missed }
        case .uscita: return recentCalls.filter { $0.direction == .outbound }
        case .ricevute: return recentCalls.filter { $0.direction == .inbound }
        }
    }

    private var callableDestination: CommunicationDestination? {
        resolution.selected ?? (resolution.candidates.count == 1 ? resolution.candidates.first : nil)
    }

    private var statusText: String {
        if let activeCall {
            return "\(activeCall.state.rawValue) - \(activeCall.destination.transportLabel)"
        }
        return "Inserisci una destinazione: PerX risolve automaticamente il trasporto"
    }

    private func resolve(_ rawValue: String) {
        resolution = resolver.resolve(destination: rawValue, context: context)
    }

    private func callSelectedDestination() async {
        guard let destination = callableDestination else { return }
        callState = .ringing
        do {
            let (call, response) = try await CommunicationStartService.shared.startCommunication(destination: destination, context: context)
            await MainActor.run {
                activeCall = call
                callState = .active
                recentCalls.insert(call, at: 0)
                activeLiveKitToken = response?.livekitToken
            }
        } catch {
            await MainActor.run {
                callState = .failed
                errorMessage = error.localizedDescription
            }
        }
    }

    private func openClaim(_ call: CommunicationCallLogItem) {
        // TODO: wire to existing claim navigation once the communication session
        // carries a stable claim route for every target surface.
        activeCall = call
    }

    private func icon(for type: CommunicationDestinationType) -> String {
        switch type {
        case .externalPhone: return "phone"
        case .internalUser: return "person.wave.2"
        case .internalExtension: return "number"
        case .internalTeam: return "person.3"
        case .queue: return "list.bullet.rectangle"
        case .livekitRoom: return "video"
        case .externalGuestLink: return "link"
        case .crossTenantPerX: return "building.2"
        }
    }

    private func callIcon(_ call: CommunicationCallLogItem) -> String {
        switch call.direction {
        case .inbound: return "phone.arrow.down.left"
        case .outbound: return "phone.arrow.up.right"
        case .missed: return "phone.down"
        }
    }
}

private struct CommunicationClaimStatusPresentation {
    let icon: String
    let color: Color

    init(status: String?) {
        switch status {
        case .some("SV001"), .some("da_scaricare"):
            icon = "tray.and.arrow.down"
            color = .orange
        case .some("SV002"), .some("SV022"), .some("SV023"), .some("in_attesa"):
            icon = "hourglass.circle"
            color = .yellow
        case .some("SV003"), .some("SV005"), .some("SV010"), .some("perizia_da_eseguire"):
            icon = "doc.text.magnifyingglass"
            color = .cyan
        case .some("SV004"), .some("SV014"), .some("videoperizia"):
            icon = "video.circle"
            color = .orange.opacity(0.8)
        case .some("SV011"), .some("SV012"), .some("SV013"), .some("in_gestione"):
            icon = "gearshape"
            color = .blue
        case .some("SV020"), .some("SV031"), .some("SV032"), .some("SV033"), .some("atto"):
            icon = "envelope.badge"
            color = .purple
        case .some("SV021"), .some("SV030"), .some("esito"):
            icon = "megaphone"
            color = .mint
        case .some("SV040"), .some("SV041"), .some("SV042"), .some("SV043"), .some("controllo"):
            icon = "checklist"
            color = .mint.opacity(0.7)
        case .some("SV050"), .some("SV051"), .some("sopralluogo"):
            icon = "mappin.and.ellipse"
            color = .pink
        case .some("SV090"), .some("chiusa"):
            icon = "lock.circle"
            color = .green
        case .some("SV091"), .some("richiesta_revisione"):
            icon = "arrow.counterclockwise.circle"
            color = .red.opacity(0.8)
        case .some("SI001"), .some("revocata"):
            icon = "xmark.circle"
            color = .red
        case .some("SI002"), .some("annullata"):
            icon = "trash.circle"
            color = .gray
        default:
            icon = "folder"
            color = .blue
        }
    }
}

private enum CallFilter: String, CaseIterable {
    case recenti = "Recenti"
    case perse = "Perse"
    case uscita = "In uscita"
    case ricevute = "Ricevute"
}

private extension TelefonoCommunicationView {
    static let seedSuggestions: [CommunicationContactSuggestion] = [
        CommunicationContactSuggestion(id: "insured-1", displayName: "Mario Rossi", detail: "Assicurato - +39 333 1234567", rawDestination: "+393331234567", destinationTypeHint: .externalPhone, claimReference: "SX-2026-001"),
        CommunicationContactSuggestion(id: "agency-1", displayName: "Agenzia Milano Centro", detail: "Agenzia - 02 555010", rawDestination: "02555010", destinationTypeHint: .externalPhone, claimReference: "SX-2026-014"),
        CommunicationContactSuggestion(id: "guest-link-1", displayName: "Ospite videoperizia", detail: "Link room LiveKit ospite", rawDestination: "https://perx.app/guest/demo", destinationTypeHint: .externalGuestLink)
    ]

    static let seedFrequentContacts: [CommunicationContactSuggestion] = [
        CommunicationContactSuggestion(id: "perito-perx", displayName: "Perito PerX", detail: "Interno 101 - perito@perx.it", rawDestination: "101", destinationTypeHint: .internalExtension),
        CommunicationContactSuggestion(id: "admin-perx", displayName: "Admin PerX", detail: "Interno 102 - admin@perx.it", rawDestination: "102", destinationTypeHint: .internalExtension),
        CommunicationContactSuggestion(id: "cat-perx", displayName: "CAT PerX", detail: "Interno 103 - cat@perx.it", rawDestination: "103", destinationTypeHint: .internalExtension),
        CommunicationContactSuggestion(id: "team-periti", displayName: "Team periti", detail: "Routing interno", rawDestination: "team:periti", destinationTypeHint: .internalTeam),
        CommunicationContactSuggestion(id: "queue-triage", displayName: "Coda triage", detail: "Coda PerX", rawDestination: "queue:triage", destinationTypeHint: .queue)
    ]

    static let seedCalls: [CommunicationCallLogItem] = [
        CommunicationCallLogItem(displayName: "Mario Rossi", subtitle: "Provider telefonico", direction: .inbound, state: .completed, startedAt: Date().addingTimeInterval(-3600), durationSeconds: 180, destination: CommunicationDestination(destinationType: .externalPhone, transport: .telecomProvider, targetId: "+393331234567", displayName: "Mario Rossi", tenantId: "default", rawValue: "+393331234567"), claimReference: "SX-2026-001", claimId: "claim-1", claimContext: CommunicationClaimContext(claimId: "claim-1", claimReference: "SX-2026-001", claimNumber: "SX-2026-001", claimStatus: "SV012", insuredName: "Mario Rossi")),
        CommunicationCallLogItem(displayName: "Perito PerX", subtitle: "Interno 101 - PerX", direction: .outbound, state: .completed, startedAt: Date().addingTimeInterval(-7200), durationSeconds: 96, destination: CommunicationDestination(destinationType: .internalExtension, transport: .livekit, targetId: "user-perito-perx", displayName: "Perito PerX", tenantId: "default", rawValue: "101")),
        CommunicationCallLogItem(displayName: "Agenzia Milano Centro", subtitle: "Provider telefonico", direction: .missed, state: .missed, startedAt: Date().addingTimeInterval(-10800), destination: CommunicationDestination(destinationType: .externalPhone, transport: .telecomProvider, targetId: "02555010", displayName: "Agenzia Milano Centro", tenantId: "default", rawValue: "02555010"), claimReference: "SX-2026-014", claimId: "claim-14", claimContext: CommunicationClaimContext(claimId: "claim-14", claimReference: "SX-2026-014", claimNumber: "SX-2026-014", claimStatus: "SV020", insuredName: "Luigi Bianchi"))
    ]
}
