import SwiftUI

/// Modale "Invia atto" — selezione canali + invio multipart al backend.
struct AttoSendSheet: View {
    let claimId: String
    let claimRef: String
    let pdfData: Data
    let fileName: String
    let suggestedWhatsAppAccountId: String?

    @Environment(\.dismiss) private var dismiss

    @State private var selectedChannels: Set<AttoSendChannel> = [.push, .email]
    @State private var whatsAppAccountId: String = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var resultSummary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    intro
                    channelsSection
                    if selectedChannels.contains(.whatsapp) {
                        whatsAppAccountSection
                    }
                    if let resultSummary {
                        successCard(resultSummary)
                    }
                    if let errorMessage {
                        errorCard(errorMessage)
                    }
                }
                .padding(20)
            }

            Divider()

            footer
        }
        .frame(minWidth: 520, minHeight: 480)
        .onAppear {
            if let id = suggestedWhatsAppAccountId {
                whatsAppAccountId = id
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Invia atto all'assicurato")
                    .font(.title3.bold())
                Text("Sinistro \(claimRef)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Scegli i canali di invio. Email e push viaggiano sempre insieme come traccia scritta + notifica immediata.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var channelsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Canali")
                .font(.headline)
            ForEach(AttoSendChannel.allCases) { channel in
                Toggle(isOn: bindingFor(channel)) {
                    HStack(spacing: 10) {
                        Image(systemName: iconFor(channel))
                            .frame(width: 22)
                        Text(channel.displayName)
                    }
                }
                .toggleStyle(.switch)
            }
        }
    }

    private var whatsAppAccountSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Account WhatsApp del perito")
                .font(.subheadline.weight(.medium))
            TextField("Es. studio-rossi", text: $whatsAppAccountId)
                .textFieldStyle(.roundedBorder)
            Text("Identificativo dell'account collegato al perx_wa_bridge.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func successCard(_ summary: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(.green)
            Text(summary)
                .font(.subheadline)
        }
        .padding(12)
        .background(Color.green.opacity(0.1))
        .cornerRadius(8)
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.subheadline)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Chiudi") { dismiss() }
                .buttonStyle(.bordered)
            Button {
                Task { await sendAtto() }
            } label: {
                if isSending {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Invia atto")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSending || selectedChannels.isEmpty || waAccountMissingWhenNeeded)
        }
        .padding(16)
    }

    // MARK: - Helpers

    private var waAccountMissingWhenNeeded: Bool {
        selectedChannels.contains(.whatsapp) && whatsAppAccountId.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func bindingFor(_ channel: AttoSendChannel) -> Binding<Bool> {
        Binding(
            get: { selectedChannels.contains(channel) },
            set: { isOn in
                if isOn { selectedChannels.insert(channel) } else { selectedChannels.remove(channel) }
            }
        )
    }

    private func iconFor(_ channel: AttoSendChannel) -> String {
        switch channel {
        case .push: return "bell.badge.fill"
        case .email: return "envelope.fill"
        case .whatsapp: return "bubble.left.fill"
        }
    }

    private func sendAtto() async {
        isSending = true
        errorMessage = nil
        resultSummary = nil
        defer { isSending = false }

        do {
            let response = try await AttoSendService.shared.sendAtto(
                claimId: claimId,
                pdfData: pdfData,
                fileName: fileName,
                channels: selectedChannels,
                whatsAppAccountId: selectedChannels.contains(.whatsapp)
                    ? whatsAppAccountId.trimmingCharacters(in: .whitespaces)
                    : nil
            )
            let push = response.delivery.push.filter { $0.success == true }.count
            let email = response.delivery.email.filter { $0.success == true }.count
            let whatsapp = response.delivery.whatsapp.filter { $0.success == true }.count
            resultSummary = "Atto inviato. Push: \(push), email: \(email), WhatsApp: \(whatsapp)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
