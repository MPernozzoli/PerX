import SwiftUI
import Combine

@MainActor
final class CallListViewModel: ObservableObject {
    @Published var incoming: [IncomingCallDTO] = []
    @Published var history: [CallHistoryDTO] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let inc: IncomingCallListDTO = APIClient.shared.get("/api/v1/communications/incoming")
            async let hist: CallHistoryListDTO = APIClient.shared.get("/api/v1/communications/sessions?limit=50")
            self.incoming = try await inc.items
            self.history = try await hist.items
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    func dial(rawValue: String, displayName: String?, tenantId: String?) async -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespaces)
        let isInternal = trimmed.count <= 4 && trimmed.allSatisfy(\.isNumber)
        let tid = tenantId ?? "default"
        let req = CommunicationStartRequestDTO(
            destination: .init(
                destination_type: isInternal ? "internal_extension" : "external_phone",
                transport: isInternal ? "livekit" : "telecom_provider",
                target_id: nil,
                raw_value: trimmed,
                display_name: displayName,
                tenant_id: tid
            ),
            context: .init(claim_id: nil, tenant_id: tid)
        )
        do {
            let resp: CommunicationStartResponseDTO = try await APIClient.shared.post(
                "/api/v1/communications/start",
                body: req
            )
            return resp.session_id
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }
}

private enum LiteCallFilter: String, CaseIterable, Identifiable {
    case all = "Tutte"
    case missed = "Perse"
    case outbound = "Uscita"
    case inbound = "Ricevute"
    var id: String { rawValue }
}

struct CallListView: View {
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var vm = CallListViewModel()
    @State private var showDial = false
    @State private var filter: LiteCallFilter = .all

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                myExtensionCard

                if !vm.incoming.isEmpty {
                    incomingSection
                }

                filterPicker

                historySection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 96)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Chiamate")
        .navigationBarTitleDisplayMode(.large)
        .overlay(alignment: .bottomTrailing) {
            Button {
                showDial = true
            } label: {
                Image(systemName: "phone.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(Color.green.gradient, in: Circle())
                    .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 24)
            .accessibilityLabel("Nuova chiamata")
        }
        .sheet(isPresented: $showDial) {
            DialerSheet { phone, name in
                await vm.dial(rawValue: phone, displayName: name, tenantId: auth.tenantId) != nil
            }
            .presentationDetents([.large])
        }
        .refreshable { await vm.load() }
        .task {
            await vm.load()
            await auth.refreshProfile()
        }
        .onReceive(NotificationCenter.default.publisher(for: .perxRealtimeIncomingCall)) { _ in
            Task { await vm.load() }
            RingbackPlayer.shared.start()
        }
        .onReceive(CallSessionShared.shared.$roomState) { state in
            if state == "connected" || state == "disconnected" {
                RingbackPlayer.shared.stop()
            }
        }
        .alert("Errore", isPresented: .constant(vm.errorMessage != nil), actions: {
            Button("OK") { vm.errorMessage = nil }
        }, message: { Text(vm.errorMessage ?? "") })
    }

    // MARK: - Sections

    @ViewBuilder
    private var myExtensionCard: some View {
        if let ext = auth.myExtension, !ext.isEmpty {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(auth.myExtensionEnabled ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: "number")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(auth.myExtensionEnabled ? Color.accentColor : .secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tuo interno")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text(ext)
                            .font(.title2.monospaced().weight(.bold))
                            .foregroundStyle(.primary)
                        if !auth.myExtensionEnabled {
                            Text("non attivo")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.18), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var incomingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("In arrivo", icon: "phone.arrow.down.left.fill", tint: .green)
            VStack(spacing: 0) {
                ForEach(Array(vm.incoming.enumerated()), id: \.element.id) { idx, call in
                    IncomingCallRow(call: call)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    if idx < vm.incoming.count - 1 { Divider().padding(.leading, 56) }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var filterPicker: some View {
        Picker("", selection: $filter) {
            ForEach(LiteCallFilter.allCases) { f in
                Text(f.rawValue).tag(f)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .padding(.top, 4)
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Recenti", icon: "clock", tint: .secondary)
            if filteredHistory.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "phone.down")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("Nessuna chiamata")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filteredHistory.enumerated()), id: \.element.id) { idx, call in
                        HistoryCallRow(call: call)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                        if idx < filteredHistory.count - 1 { Divider().padding(.leading, 56) }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func sectionHeader(_ title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.caption.weight(.semibold)).foregroundStyle(tint)
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.4)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.leading, 4)
    }

    private var filteredHistory: [CallHistoryDTO] {
        switch filter {
        case .all: return vm.history
        case .missed: return vm.history.filter { $0.state == "missed" || $0.state == "rejected" || $0.state == "failed" }
        case .outbound: return vm.history.filter { $0.direction == "outbound" }
        case .inbound: return vm.history.filter { $0.direction == "inbound" }
        }
    }
}

private struct IncomingCallRow: View {
    let call: IncomingCallDTO

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.green.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: "phone.arrow.down.left.fill")
                    .foregroundStyle(.green)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(call.display_name ?? "Sconosciuto").font(.headline).lineLimit(1)
                Text("\(call.transport.capitalized) · \(call.state)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(call.created_at, style: .time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

private struct HistoryCallRow: View {
    let call: CallHistoryDTO

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(color.opacity(0.15)).frame(width: 40, height: 40)
                Image(systemName: icon).foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(call.display_name ?? otherParty ?? "Sconosciuto")
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(call.transport.capitalized)
                    Text("·")
                    Text(stateLabel)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(call.created_at, style: .time)
                    .font(.caption.monospacedDigit())
                Text(call.created_at, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var otherParty: String? {
        call.direction == "inbound" ? call.from_value : call.to_value
    }

    private var stateLabel: String {
        switch call.state {
        case "ended", "completed": return "completata"
        case "missed": return "persa"
        case "rejected": return "rifiutata"
        case "failed": return "fallita"
        case "ringing": return "in arrivo"
        case "active": return "in corso"
        default: return call.state
        }
    }

    private var icon: String {
        switch (call.direction ?? "", call.state) {
        case ("inbound", let s) where s == "missed" || s == "rejected": return "phone.arrow.down.left"
        case ("inbound", _): return "phone.arrow.down.left.fill"
        case ("outbound", _): return "phone.arrow.up.right.fill"
        default: return "phone"
        }
    }

    private var color: Color {
        switch call.state {
        case "ended", "completed": return .secondary
        case "missed", "rejected", "failed": return .red
        case "ringing", "active": return .green
        default: return .blue
        }
    }
}

private struct DialerSheet: View {
    let onCall: (String, String?) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var phone: String = ""
    @State private var name: String = ""
    @State private var isCalling = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 18) {
                        Text(displayedPhone)
                            .font(.system(size: 38, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .padding(.top, 8)
                            .contentShape(Rectangle())
                            .overlay(alignment: .trailing) {
                                if !phone.isEmpty {
                                    Button {
                                        if !phone.isEmpty { phone.removeLast() }
                                    } label: {
                                        Image(systemName: "delete.left.fill")
                                            .font(.title2)
                                            .foregroundStyle(.secondary)
                                            .padding(.trailing, 8)
                                    }
                                    .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                                        phone = ""
                                    })
                                }
                            }

                        TextField("Nome (opzionale)", text: $name)
                            .focused($nameFocused)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.done)

                        Keypad { key in
                            phone.append(key)
                        } onLongZero: {
                            phone.append("+")
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 100)
                }

                callBar
            }
            .background(Color(.systemBackground))
            .navigationTitle("Nuova chiamata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
            }
        }
    }

    private var displayedPhone: String {
        phone.isEmpty ? "Componi numero" : phone
    }

    private var canCall: Bool {
        !phone.trimmingCharacters(in: .whitespaces).isEmpty && !isCalling
    }

    private var callBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                Task {
                    isCalling = true
                    let ok = await onCall(
                        phone.trimmingCharacters(in: .whitespaces),
                        name.isEmpty ? nil : name
                    )
                    isCalling = false
                    if ok { dismiss() }
                }
            } label: {
                HStack {
                    if isCalling {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "phone.fill")
                    }
                    Text(isCalling ? "Chiamata in corso…" : "Chiama")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(canCall ? Color.green : Color.green.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!canCall)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 16)
            .background(.thinMaterial)
        }
    }
}

private struct Keypad: View {
    let onKey: (String) -> Void
    let onLongZero: () -> Void

    private let keys: [[(String, String)]] = [
        [("1", ""), ("2", "ABC"), ("3", "DEF")],
        [("4", "GHI"), ("5", "JKL"), ("6", "MNO")],
        [("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ")],
        [("✱", ""), ("0", "+"), ("#", "")]
    ]

    var body: some View {
        VStack(spacing: 14) {
            ForEach(0..<keys.count, id: \.self) { row in
                HStack(spacing: 22) {
                    ForEach(0..<keys[row].count, id: \.self) { col in
                        let (digit, letters) = keys[row][col]
                        Button {
                            let value = digit == "✱" ? "*" : digit
                            onKey(value)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        } label: {
                            VStack(spacing: 0) {
                                Text(digit)
                                    .font(.system(size: 30, weight: .regular, design: .rounded))
                                if !letters.isEmpty {
                                    Text(letters)
                                        .font(.system(size: 10, weight: .semibold))
                                        .tracking(1.5)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 72, height: 72)
                            .background(Color(.secondarySystemBackground), in: Circle())
                            .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                                if digit == "0" {
                                    onLongZero()
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                }
                            }
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
