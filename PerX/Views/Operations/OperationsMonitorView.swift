import SwiftUI
import CoreData

private enum MonitorWindow: String, CaseIterable, Identifiable {
    case today = "Oggi"
    case month = "Mese"
    case year = "Anno"

    var id: String { rawValue }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .today:
            return calendar.isDateInToday(date)
        case .month:
            return calendar.isDate(date, equalTo: Date(), toGranularity: .month)
        case .year:
            return calendar.isDate(date, equalTo: Date(), toGranularity: .year)
        }
    }
}

private struct MonitorSegment: Identifiable {
    let id: String
    let label: String
    let icon: String
    let color: Color
    let count: Int
}

private struct StudioCompanySnapshot: Identifiable {
    let id: String
    let company: Compagnia
    let activeClaims: Int
    let closedClaims: Int
    let target: Int
    let segments: [MonitorSegment]

    var completion: Double {
        guard target > 0 else { return 0 }
        return min(1, Double(closedClaims) / Double(target))
    }
}

private struct TeamMemberSnapshot: Identifiable {
    let id: String
    let email: String
    let displayName: String
    let profile: UserProfile?
    let company: Compagnia
    let activeClaims: [Sinistro]
    let controlClaims: [Sinistro]
    let closedInPeriod: Int
    let monthlyTarget: Int
    let workSummary: String?
    let workLocation: CloudKitUserDirectoryService.WorkLocation?
    let onlineStatus: CloudKitUserDirectoryService.OnlineStatus?
    let maxAuthority: Double
    let segments: [MonitorSegment]

    var completionRate: Double {
        guard monthlyTarget > 0 else { return 0 }
        return min(1, Double(closedInPeriod) / Double(monthlyTarget))
    }
}

private struct TeamSnapshot {
    let company: Compagnia
    let triageClaims: [Sinistro]
    let members: [TeamMemberSnapshot]
    let activeClaims: Int
    let closedClaims: Int
    let averagePriority: Double
    let target: Int
    let coverageRatio: Double
}

private enum OperationsMetricsBuilder {
    static let triageStates: Set<StatoManager.StatoSinistro> = Set(
        StatoManager.StatoSinistro.allCases.filter { $0.requiredRole == .manager && !$0.isSystem }
    )

    static let orderedGroups: [StateGroup] = [
        .daScaricare,
        .inAttesa,
        .periziaDaEseguire,
        .videoperizia,
        .inGestione,
        .controllo,
        .esito,
        .atto,
        .chiusura
    ]

    static func company(for sinistro: Sinistro) -> Compagnia {
        Compagnia.detect(gruppo: sinistro.gruppo, compagnia: sinistro.nomeCompagnia)
    }

    static func state(for sinistro: Sinistro) -> StatoManager.StatoSinistro? {
        guard let raw = sinistro.stato else { return nil }
        return StatoManager.StatoSinistro.allCases.first(where: { $0.descrizione == raw })
    }

    static func isClosed(_ sinistro: Sinistro) -> Bool {
        guard let state = state(for: sinistro) else { return false }
        return state.isClosureState
    }

    static func isTriage(_ sinistro: Sinistro) -> Bool {
        guard let state = state(for: sinistro) else { return false }
        return triageStates.contains(state)
    }

    static func isAssigned(to email: String, sinistro: Sinistro) -> Bool {
        let owner = (sinistro.assignedToUserEmail ?? sinistro.ownerEmail)?.lowercased()
        return owner == email.lowercased()
    }

    static func currentPriority(for sinistro: Sinistro) -> Double {
        PriorityCalculator.shared.calculateDynamicPriority(
            for: sinistro,
            monthlyGoal: WorkScheduleManager.shared.getMonthlyTarget(for: Date()),
            currentClosures: 0,
            needsAcceleration: false
        )
    }

    static func segments(for claims: [Sinistro]) -> [MonitorSegment] {
        orderedGroups.compactMap { group in
            let members = Set(group.members.map(\.descrizione))
            let count = claims.filter { members.contains($0.stato ?? "") }.count
            guard count > 0 else { return nil }
            return MonitorSegment(
                id: group.rawValue,
                label: group.shortLabel,
                icon: group.icon,
                color: group.color,
                count: count
            )
        }
    }
}

struct StudioMonitorView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Sinistro.dataIncarico, ascending: false)],
        animation: .default
    ) private var sinistri: FetchedResults<Sinistro>

    @StateObject private var configService = TeamConfigurationService.shared
    @StateObject private var profileService = UserProfileService.shared
    @State private var window: MonitorWindow = .month

    private var claims: [Sinistro] { Array(sinistri) }

    private var snapshots: [StudioCompanySnapshot] {
        let companies = Set(claims.map(OperationsMetricsBuilder.company(for:)).filter { $0 != .unknown })
        return companies.map { company in
            let companyClaims = claims.filter { OperationsMetricsBuilder.company(for: $0) == company }
            let activeClaims = companyClaims.filter { !OperationsMetricsBuilder.isClosed($0) }
            let closedClaims = companyClaims.filter {
                guard let closeDate = $0.dataChiusura else { return false }
                return OperationsMetricsBuilder.isClosed($0) && window.contains(closeDate)
            }
            let target = companyTarget(for: company)
            return StudioCompanySnapshot(
                id: company.rawValue,
                company: company,
                activeClaims: activeClaims.count,
                closedClaims: closedClaims.count,
                target: target,
                segments: OperationsMetricsBuilder.segments(for: activeClaims)
            )
        }
        .sorted { $0.activeClaims > $1.activeClaims }
    }

    private var totalActive: Int { snapshots.reduce(0) { $0 + $1.activeClaims } }
    private var totalClosed: Int { snapshots.reduce(0) { $0 + $1.closedClaims } }
    private var totalTarget: Int { snapshots.reduce(0) { $0 + $1.target } }
    private var triageCount: Int { claims.filter { OperationsMetricsBuilder.isTriage($0) && ($0.assignedToUserEmail ?? "").isEmpty }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                OperationsHeader(title: "Studio", window: $window)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
                    OperationsKPI(title: "Perizie Attive", value: "\(totalActive)", detail: "monitoraggio realtime", accent: .blue)
                    OperationsKPI(title: "Completate", value: "\(totalClosed)", detail: window.rawValue.lowercased(), accent: .green)
                    OperationsKPI(title: "Obiettivo Studio", value: "\(totalTarget)", detail: totalTarget > 0 ? "\(Int((Double(totalClosed) / Double(totalTarget)) * 100))%" : "n/d", accent: .orange)
                    OperationsKPI(title: "Pool Triage", value: "\(triageCount)", detail: "sinistri non assegnati", accent: .teal)
                }

                VStack(spacing: 16) {
                    ForEach(snapshots) { snapshot in
                        CompanyMonitorRow(snapshot: snapshot)
                    }
                }
            }
            .padding(20)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            await profileService.refreshAllProfiles()
        }
    }

    private func companyTarget(for company: Compagnia) -> Int {
        profileService.allProfiles.reduce(0) { partialResult, profile in
            let settings = configService.settings(for: profile.email, fallbackName: profile.displayName)
            guard settings.assignedCompanies.contains(company.rawValue) else { return partialResult }
            return partialResult + settings.monthlyClaimTarget
        }
    }
}

struct TeamMonitorView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Sinistro.dataIncarico, ascending: false)],
        animation: .default
    ) private var sinistri: FetchedResults<Sinistro>

    @StateObject private var configService = TeamConfigurationService.shared
    @StateObject private var profileService = UserProfileService.shared
    @StateObject private var userDirectory = CloudKitUserDirectoryService.shared
    @StateObject private var appState = AppState.shared
    @State private var window: MonitorWindow = .month
    @State private var selectedCompany: Compagnia?
    @State private var selectedMemberForSettings: UserProfile?
    @State private var selectedControlSnapshot: TeamMemberSnapshot?
    @State private var selectedPoolClaims: [Sinistro] = []
    @State private var isOpeningChat = false

    private var claims: [Sinistro] { Array(sinistri) }

    private var availableCompanies: [Compagnia] {
        let claimCompanies = claims.map(OperationsMetricsBuilder.company(for:)).filter { $0 != .unknown }
        let configuredCompanies = profileService.allProfiles.flatMap { profile in
            configService.assignedCompanies(for: profile.email)
        }
        return Array(Set(claimCompanies + configuredCompanies)).sorted { $0.shortLabel < $1.shortLabel }
    }

    private var currentCompany: Compagnia? {
        selectedCompany ?? availableCompanies.first
    }

    private var teamSnapshot: TeamSnapshot? {
        guard let currentCompany else { return nil }
        let companyClaims = claims.filter { OperationsMetricsBuilder.company(for: $0) == currentCompany }
        let triageClaims = companyClaims
            .filter { OperationsMetricsBuilder.isTriage($0) && ($0.assignedToUserEmail ?? "").isEmpty }
            .sorted { OperationsMetricsBuilder.currentPriority(for: $0) > OperationsMetricsBuilder.currentPriority(for: $1) }

        let profiles = teamProfiles(for: currentCompany)
        let members = profiles.map { profile -> TeamMemberSnapshot in
            let userClaims = companyClaims.filter { OperationsMetricsBuilder.isAssigned(to: profile.email, sinistro: $0) && !OperationsMetricsBuilder.isClosed($0) }
            let controlClaims = userClaims.filter {
                guard let state = OperationsMetricsBuilder.state(for: $0) else { return false }
                return state.stateGroup == .controllo
            }
            let closedInPeriod = companyClaims.filter {
                guard let closeDate = $0.dataChiusura else { return false }
                return OperationsMetricsBuilder.isAssigned(to: profile.email, sinistro: $0) &&
                    OperationsMetricsBuilder.isClosed($0) &&
                    window.contains(closeDate)
            }.count

            let settings = configService.settings(for: profile.email, fallbackName: profile.displayName)
            let cloudUser = userDirectory.user(email: profile.email)
            return TeamMemberSnapshot(
                id: profile.email,
                email: profile.email,
                displayName: configService.displayName(for: profile),
                profile: profile,
                company: currentCompany,
                activeClaims: userClaims.sorted { OperationsMetricsBuilder.currentPriority(for: $0) > OperationsMetricsBuilder.currentPriority(for: $1) },
                controlClaims: controlClaims,
                closedInPeriod: closedInPeriod,
                monthlyTarget: settings.monthlyClaimTarget,
                workSummary: cloudUser?.workScheduleToday,
                workLocation: cloudUser?.workLocation,
                onlineStatus: cloudUser?.onlineStatus,
                maxAuthority: settings.maxAuthority,
                segments: OperationsMetricsBuilder.segments(for: userClaims)
            )
        }
        .sorted { $0.activeClaims.count > $1.activeClaims.count }

        let activeClaims = members.reduce(0) { $0 + $1.activeClaims.count }
        let closedClaims = members.reduce(0) { $0 + $1.closedInPeriod }
        let target = members.reduce(0) { $0 + $1.monthlyTarget }
        let teamClaimsForPriority = triageClaims + members.flatMap(\.activeClaims)
        let averagePriority = teamClaimsForPriority.isEmpty ? 0 : teamClaimsForPriority.map(OperationsMetricsBuilder.currentPriority(for:)).reduce(0, +) / Double(teamClaimsForPriority.count)
        let coverageRatio = target > 0 ? Double(closedClaims) / Double(target) : 0

        return TeamSnapshot(
            company: currentCompany,
            triageClaims: triageClaims,
            members: members,
            activeClaims: activeClaims,
            closedClaims: closedClaims,
            averagePriority: averagePriority,
            target: target,
            coverageRatio: coverageRatio
        )
    }

    private var canManageTeam: Bool {
        guard let currentCompany else { return false }
        return configService.canManageTeam(
            company: currentCompany,
            currentEmail: CurrentUserService.shared.currentEmail,
            profiles: profileService.allProfiles
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                OperationsHeader(title: currentCompany.map { "Team: \($0.shortLabel)" } ?? "Team", window: $window) {
                    if !availableCompanies.isEmpty {
                        Picker("Compagnia", selection: Binding(
                            get: { currentCompany ?? availableCompanies.first ?? .unknown },
                            set: { selectedCompany = $0 }
                        )) {
                            ForEach(availableCompanies, id: \.self) { company in
                                Text(company.shortLabel).tag(company)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 180)
                    }
                }

                if let snapshot = teamSnapshot {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
                        OperationsKPI(title: "Perizie Attive", value: "\(snapshot.activeClaims)", detail: snapshot.company.shortLabel, accent: .blue)
                        OperationsKPI(title: "Priorità Media", value: String(format: "%.2f", snapshot.averagePriority), detail: "pool + assegnati", accent: .purple)
                        OperationsKPI(title: "Completate", value: "\(snapshot.closedClaims)", detail: window.rawValue.lowercased(), accent: .green)
                        OperationsKPI(title: "Copertura Target", value: "\(Int(snapshot.coverageRatio * 100))%", detail: "\(snapshot.target) obiettivo", accent: .orange)
                    }

                    PoolMonitorCard(
                        company: snapshot.company,
                        triageClaims: snapshot.triageClaims,
                        onOpenPool: { selectedPoolClaims = snapshot.triageClaims }
                    )

                    VStack(spacing: 16) {
                        ForEach(snapshot.members) { member in
                            TeamMemberMonitorRow(
                                snapshot: member,
                                canManageTeam: canManageTeam,
                                onOpenControls: { selectedControlSnapshot = member },
                                onOpenSettings: {
                                    if let profile = member.profile { selectedMemberForSettings = profile }
                                },
                                onOpenChat: {
                                    Task { await openDirectChat(with: member.email, displayName: member.displayName) }
                                }
                            )
                        }
                    }
                } else {
                    ContentUnavailableView("Nessun team configurato", systemImage: "person.3.sequence")
                }
            }
            .padding(20)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .task {
            await profileService.refreshAllProfiles()
            if selectedCompany == nil {
                selectedCompany = availableCompanies.first
            }
        }
        .sheet(item: $selectedMemberForSettings) { profile in
            TeamMemberSettingsSheet(profile: profile)
        }
        .sheet(item: $selectedControlSnapshot) { snapshot in
            ControlClaimsSheet(snapshot: snapshot)
                .environment(\.managedObjectContext, viewContext)
                .environmentObject(appState)
        }
        .sheet(isPresented: Binding(
            get: { !selectedPoolClaims.isEmpty },
            set: { if !$0 { selectedPoolClaims = [] } }
        )) {
            TriagePoolSheet(company: currentCompany, claims: selectedPoolClaims)
                .environment(\.managedObjectContext, viewContext)
                .environmentObject(appState)
        }
    }

    private func teamProfiles(for company: Compagnia) -> [UserProfile] {
        let assignedByConfig = profileService.allProfiles.filter { profile in
            configService.assignedCompanies(for: profile.email).contains(company)
        }
        let assignedByClaimsEmails = Set(
            claims.filter { OperationsMetricsBuilder.company(for: $0) == company }
                .compactMap { ($0.assignedToUserEmail ?? $0.ownerEmail)?.lowercased() }
        )
        let assignedByClaims = profileService.allProfiles.filter { assignedByClaimsEmails.contains($0.email.lowercased()) }

        let merged = Dictionary(
            uniqueKeysWithValues: (assignedByConfig + assignedByClaims)
                .filter { !configService.effectiveRoles(for: $0).isEmpty }
                .map { ($0.email.lowercased(), $0) }
        )
        return merged.values
            .filter {
                let roles = Set(configService.effectiveRoles(for: $0))
                return roles.contains(.expert) || roles.contains(.teamLeader)
            }
            .sorted { configService.displayName(for: $0) < configService.displayName(for: $1) }
    }

    private func openDirectChat(with userEmail: String, displayName: String) async {
        guard !isOpeningChat else { return }
        guard let currentUserEmail = CurrentUserService.shared.currentEmail else { return }

        isOpeningChat = true
        defer { isOpeningChat = false }

        do {
            let room = try await CloudKitChatService.shared.findOrCreateDirectChat(
                with: userEmail,
                currentUserEmail: currentUserEmail
            )

            await MainActor.run {
                let chatView = ChatDetailView(roomId: room.id, currentUserEmail: currentUserEmail)
                WindowManager.shared.openWindow(
                    identifier: "team-chat-\(room.id)",
                    content: chatView,
                    configuration: WindowConfiguration(
                        identifier: "team-chat-\(room.id)",
                        title: "Chat: \(displayName)",
                        minSize: CGSize(width: 560, height: 720),
                        defaultSize: CGSize(width: 720, height: 900)
                    )
                )
            }
        } catch {
            print("[TeamMonitorView] ❌ Impossibile aprire la chat con \(userEmail): \(error.localizedDescription)")
        }
    }
}

private struct OperationsHeader<Trailing: View>: View {
    let title: String
    @Binding var window: MonitorWindow
    @ViewBuilder var trailing: () -> Trailing

    init(title: String, window: Binding<MonitorWindow>, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self._window = window
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.largeTitle.weight(.semibold))
            Spacer()
            Picker("", selection: $window) {
                ForEach(MonitorWindow.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            trailing()
        }
    }
}

private struct OperationsKPI: View {
    let title: String
    let value: String
    let detail: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(accent)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct CompanyMonitorRow: View {
    let snapshot: StudioCompanySnapshot

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(companyColor)
                    .frame(width: 48, height: 48)
                Text(String(snapshot.company.shortLabel.prefix(1)))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.company.shortLabel)
                    .font(.headline)
                Text("\(snapshot.activeClaims) attive · \(snapshot.closedClaims)/\(snapshot.target) completate")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 220, alignment: .leading)

            MonitorTimelineBar(segments: snapshot.segments)
        }
        .padding(18)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var companyColor: Color {
        let color = snapshot.company.uiColor
        return Color(red: color.red, green: color.green, blue: color.blue)
    }
}

private struct PoolMonitorCard: View {
    let company: Compagnia
    let triageClaims: [Sinistro]
    let onOpenPool: () -> Void

    private var segments: [MonitorSegment] {
        OperationsMetricsBuilder.segments(for: triageClaims)
    }

    var body: some View {
        HStack(spacing: 16) {
            Label("Pool triage", systemImage: "shippingbox.fill")
                .font(.headline)
                .frame(width: 180, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text("\(triageClaims.count) sinistri non assegnati")
                    .font(.subheadline.weight(.semibold))
                Text(company.shortLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 220, alignment: .leading)

            MonitorTimelineBar(segments: segments)

            Button("Dettaglio") {
                onOpenPool()
            }
            .buttonStyle(.bordered)
        }
        .padding(18)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct TeamMemberMonitorRow: View {
    let snapshot: TeamMemberSnapshot
    let canManageTeam: Bool
    let onOpenControls: () -> Void
    let onOpenSettings: () -> Void
    let onOpenChat: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    AvatarFromEmailView(
                        email: snapshot.email,
                        size: 42,
                        fallbackName: snapshot.displayName,
                        showOnlineStatus: snapshot.onlineStatus != nil
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text(snapshot.displayName)
                            .font(.headline)
                        Text("\(snapshot.closedInPeriod)/\(snapshot.monthlyTarget) chiuse · \(Int(snapshot.completionRate * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    if let location = snapshot.workLocation {
                        StatusPill(
                            text: location.label,
                            icon: location.icon,
                            color: location == .remote ? .blue : (location == .office ? .green : .secondary)
                        )
                    }
                    if let workSummary = snapshot.workSummary, !workSummary.isEmpty {
                        StatusPill(text: workSummary, icon: "clock", color: .orange)
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        onOpenChat()
                    } label: {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                    }
                    .buttonStyle(.bordered)
                    .help("Apri chat diretta")

                    if canManageTeam {
                        Button {
                            onOpenControls()
                        } label: {
                            Label("\(snapshot.controlClaims.count)", systemImage: "eye.fill")
                        }
                        .buttonStyle(.bordered)
                        .help("Sinistri in controllo")

                        Button {
                            onOpenSettings()
                        } label: {
                            Image(systemName: "gearshape.fill")
                        }
                        .buttonStyle(.bordered)
                        .help("Impostazioni membro")
                    }
                }
            }
            .frame(width: 280, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                MonitorTimelineBar(segments: snapshot.segments)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(snapshot.segments) { segment in
                            StatusPill(
                                text: "\(segment.label) \(segment.count)",
                                icon: segment.icon,
                                color: segment.color
                            )
                        }
                        if snapshot.maxAuthority > 0 {
                            StatusPill(
                                text: "Authority \(CurrencyFormatter.shared.format(snapshot.maxAuthority))",
                                icon: "eurosign.circle",
                                color: .mint
                            )
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct MonitorTimelineBar: View {
    let segments: [MonitorSegment]

    private var total: Int {
        max(segments.reduce(0) { $0 + $1.count }, 1)
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(segments) { segment in
                    let width = max(36, geometry.size.width * CGFloat(segment.count) / CGFloat(total))
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(segment.color)
                        HStack(spacing: 6) {
                            Image(systemName: segment.icon)
                                .font(.caption.bold())
                            Text("\(segment.count)")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                    }
                    .frame(width: width)
                }
            }
        }
        .frame(height: 34)
    }
}

private struct StatusPill: View {
    let text: String
    let icon: String
    let color: Color

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color)
    }
}

private struct TeamMemberSettingsSheet: View {
    let profile: UserProfile

    @Environment(\.dismiss) private var dismiss
    @StateObject private var configService = TeamConfigurationService.shared
    @State private var tenantSettings = TenantMailSettingsService.shared.settings

    @State private var selectedRoles: Set<UserRole> = []
    @State private var selectedCompanies: Set<Compagnia> = []
    @State private var monthlyTarget: String = ""
    @State private var maxAuthority: String = ""
    @State private var preferredAgencies: String = ""
    @State private var preferredPolicies: String = ""
    @State private var preferredInsureds: String = ""
    @State private var selectedGuarantees: Set<String> = ["Fenomeno Elettrico"]
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Profilo") {
                    Text(profile.displayName)
                    Text(profile.email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Ruoli") {
                    ForEach(UserRole.allCases.filter { $0 != .admin }, id: \.self) { role in
                        Toggle(role.displayName, isOn: Binding(
                            get: { selectedRoles.contains(role) },
                            set: { isOn in
                                if isOn { selectedRoles.insert(role) } else { selectedRoles.remove(role) }
                            }
                        ))
                    }
                }

                Section("Team") {
                    ForEach(Compagnia.allCases.filter { $0 != .unknown }, id: \.self) { company in
                        Toggle(company.shortLabel, isOn: Binding(
                            get: { selectedCompanies.contains(company) },
                            set: { isOn in
                                if isOn { selectedCompanies.insert(company) } else { selectedCompanies.remove(company) }
                            }
                        ))
                    }
                }

                Section("Capacity") {
                    TextField("Obiettivo mensile", text: $monthlyTarget)
                    TextField("Authority massima", text: $maxAuthority)
                }

                Section("Preferenze") {
                    TextField("Agenzie preferenziali (CSV)", text: $preferredAgencies, axis: .vertical)
                    TextField("Polizze preferenziali (CSV)", text: $preferredPolicies, axis: .vertical)
                    TextField("Assicurati preferenziali (CSV)", text: $preferredInsureds, axis: .vertical)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Garanzie")
                            .font(.subheadline.weight(.medium))
                        ForEach(guaranteeOptions, id: \.self) { guarantee in
                            Toggle(guarantee, isOn: Binding(
                                get: { selectedGuarantees.contains(guarantee) },
                                set: { isOn in
                                    if isOn { selectedGuarantees.insert(guarantee) } else { selectedGuarantees.remove(guarantee) }
                                    if selectedGuarantees.isEmpty {
                                        selectedGuarantees = [tenantSettings.defaultClaimGaranzia]
                                    }
                                }
                            ))
                        }
                        Text("Le opzioni arrivano dalle impostazioni tenant e usano come default la garanzia predefinita del tenant.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Note") {
                    TextField("Note operative", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle("Impostazioni membro")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        var settings = configService.settings(for: profile.email, fallbackName: profile.displayName)
                        settings.roleOverrides = selectedRoles.map(\.rawValue)
                        settings.assignedCompanies = selectedCompanies.map(\.rawValue).sorted()
                        settings.monthlyClaimTarget = Int(monthlyTarget) ?? 0
                        settings.maxAuthority = Double(maxAuthority.replacingOccurrences(of: ",", with: ".")) ?? 0
                        settings.preferredAgencyCodes = splitCSV(preferredAgencies)
                        settings.preferredPolicyNumbers = splitCSV(preferredPolicies)
                        settings.preferredInsureds = splitCSV(preferredInsureds)
                        settings.preferredGuarantees = selectedGuarantees.sorted()
                        settings.notes = notes.nilIfBlank
                        configService.save(settings: settings)
                        dismiss()
                    }
                }
            }
            .onAppear {
                tenantSettings = TenantMailSettingsService.shared.settings
                let settings = configService.settings(for: profile.email, fallbackName: profile.displayName)
                selectedRoles = Set(settings.roleOverrides.compactMap(UserRole.init(rawValue:)))
                if selectedRoles.isEmpty { selectedRoles = Set(profile.roles) }
                selectedCompanies = Set(settings.assignedCompanies.compactMap { value in
                    Compagnia.allCases.first(where: { $0.rawValue == value })
                })
                monthlyTarget = settings.monthlyClaimTarget == 0 ? "" : "\(settings.monthlyClaimTarget)"
                maxAuthority = settings.maxAuthority == 0 ? "" : CurrencyFormatter.shared.format(settings.maxAuthority).replacingOccurrences(of: ".", with: ",")
                preferredAgencies = settings.preferredAgencyCodes.joined(separator: ", ")
                preferredPolicies = settings.preferredPolicyNumbers.joined(separator: ", ")
                preferredInsureds = settings.preferredInsureds.joined(separator: ", ")
                selectedGuarantees = Set(settings.preferredGuarantees.isEmpty ? [tenantSettings.defaultClaimGaranzia] : settings.preferredGuarantees)
                notes = settings.notes ?? ""
            }
        }
        .frame(minWidth: 560, minHeight: 640)
    }

    private var guaranteeOptions: [String] {
        let values = tenantSettings.claimGaranzie
        return values.isEmpty ? ["Fenomeno Elettrico"] : values
    }

    private func splitCSV(_ value: String) -> [String] {
        value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct ControlClaimsSheet: View {
    let snapshot: TeamMemberSnapshot

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            List(snapshot.controlClaims, id: \.objectID) { sinistro in
                Button {
                    appState.openSinistro(sinistro)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sinistro.riferimentoVisualizzato)
                                .font(.headline)
                            Text(sinistro.nomeAssicurato ?? sinistro.nomeContraente ?? "Assicurato")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(sinistro.stato ?? "N/D")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("In controllo · \(snapshot.displayName)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 420)
    }
}

private struct TriagePoolSheet: View {
    let company: Compagnia?
    let claims: [Sinistro]

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            List(claims, id: \.objectID) { sinistro in
                Button {
                    appState.openSinistro(sinistro)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(sinistro.riferimentoVisualizzato)
                                .font(.headline)
                            Text(sinistro.nomeAssicurato ?? sinistro.nomeContraente ?? "Assicurato")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(sinistro.stato ?? "N/D")
                                .font(.caption)
                            Text(String(format: "P %.2f", OperationsMetricsBuilder.currentPriority(for: sinistro)))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(company.map { "Pool triage · \($0.shortLabel)" } ?? "Pool triage")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
        .frame(minWidth: 620, minHeight: 460)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
