import SwiftUI
import CoreData

// Componenti condivisi del motore di stima, usati nelle pagine Elaborato Calcoli, Riepilogo e Atto.

func euroStima(_ valore: Decimal?) -> String {
    guard let valore else { return "—" }
    return "€ " + euroIt(valore)
}

/// Ricalcola la vista a ogni modifica del contesto (voci e beni non notificano la perizia).
struct RicalcoloSuModifiche: ViewModifier {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var token: Int

    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: viewContext)) { _ in
            token &+= 1
        }
    }
}

extension View {
    func ricalcolaSuModifiche(_ token: Binding<Int>) -> some View {
        modifier(RicalcoloSuModifiche(token: token))
    }
}

// MARK: - Riquadri Richiesto / Accertato / Liquidabile

struct StimaKPIView: View {
    let calcolo: StimaCalcolo

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(righe.enumerated()), id: \.offset) { _, riga in
                VStack(alignment: .leading, spacing: 3) {
                    Text(riga.0.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                    Text(euroStima(riga.1))
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundColor(riga.3)
                    Text(riga.2)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(riga.3.opacity(0.08)))
            }
        }
    }

    private var righe: [(String, Decimal?, String, Color)] {
        let t = calcolo.totali
        if calcolo.dannoNonAccertato {
            return [("Richiesto", t.richiesta, "dall'assicurato", .blue),
                    ("Stima", t.stimaConservativa, "conservativa, non accertata", .orange),
                    ("Riserva", t.riserva, "non si paga", .red)]
        }
        if calcolo.esito == .negativo {
            return [("Richiesto", t.richiesta, "dall'assicurato", .blue),
                    ("Accertato", t.dannoAccertato, "non indennizzabile", .orange),
                    ("Riserva", t.riserva, "non si paga", .red)]
        }
        return [("Richiesto", t.richiesta, "dall'assicurato", .blue),
                ("Accertato", t.dannoAccertato, "riconosciuto in stima", .primary),
                ("Liquidabile", t.liquidabile, t.liquidabileDifferito > 0 ? "di cui \(euroStima(t.liquidabileDifferito)) a ripristini" : "importo dell'atto", .green)]
    }
}

// MARK: - Scomposizione

struct ScomposizioneStimaView: View {
    let calcolo: StimaCalcolo
    var compatta: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            riga("Richiesto", calcolo.totali.richiesta ?? 0, nota: calcolo.totali.richiesta == nil ? "nessuna richiesta: valori di stima" : "", forte: true)
            ForEach(calcolo.scomposizione.filter { $0.fase == .richiestaAccertato }) { p in
                riga(p.etichetta, p.importo, nota: p.nota)
            }
            Divider()
            riga("Accertato", calcolo.totali.dannoAccertato, forte: true)
            ForEach(calcolo.scomposizione.filter { $0.fase == .accertatoLiquidabile }) { p in
                riga(p.etichetta, p.importo, nota: p.nota)
            }
            Divider()
            riga(calcolo.esito == .negativo ? "Liquidabile (negativa)" : "Liquidabile", calcolo.totali.liquidabile, forte: true, colore: .green)
            if calcolo.totali.ivaASaldo > 0 {
                riga("IVA a saldo", calcolo.totali.ivaASaldo, nota: "a ripristini ultimati, fuori dall'atto", colore: .secondary)
            }
            if calcolo.totali.riserva > 0 {
                riga("Riserva", calcolo.totali.riserva, nota: calcolo.dannoNonAccertato ? "stima conservativa" : "voci non riconosciute", colore: .red)
            }
        }
        .font(compatta ? .caption : .callout)
    }

    private func riga(_ etichetta: String, _ importo: Decimal, nota: String = "", forte: Bool = false, colore: Color = .primary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(etichetta).fontWeight(forte ? .semibold : .regular)
                if !nota.isEmpty && !compatta {
                    Text(nota).font(.caption2).foregroundColor(.secondary).lineLimit(2)
                }
            }
            Spacer()
            Text((importo < 0 ? "− " : "") + euroStima(abs(importo)))
                .font(.system(compatta ? .caption : .callout, design: .monospaced).weight(forte ? .semibold : .regular))
                .foregroundColor(importo < 0 ? .red : colore)
        }
    }
}

// MARK: - Avvisi ed errori

struct AvvisiStimaView: View {
    var errori: [String] = []
    var avvisi: [String] = []

    var body: some View {
        if !errori.isEmpty || !avvisi.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(errori, id: \.self) { e in
                    Label(e, systemImage: "xmark.octagon.fill").foregroundColor(.red)
                }
                ForEach(avvisi, id: \.self) { a in
                    Label(a, systemImage: "exclamationmark.triangle.fill").foregroundColor(.orange)
                }
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill((errori.isEmpty ? Color.orange : Color.red).opacity(0.08)))
        }
    }
}

// MARK: - Stato revisione

struct StatoStimaBadge: View {
    let stato: StimaService.StatoStima

    var body: some View {
        Label(stato.etichetta, systemImage: icona)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(colore.opacity(0.15)))
            .foregroundColor(colore)
    }

    private var icona: String {
        switch stato {
        case .errori: return "xmark.octagon.fill"
        case .nessunaRevisione, .daSalvare: return "square.and.arrow.down"
        case .daApprovare: return "hourglass"
        case .approvata: return "checkmark.seal.fill"
        }
    }

    private var colore: Color {
        switch stato {
        case .errori: return .red
        case .nessunaRevisione, .daSalvare: return .orange
        case .daApprovare: return .blue
        case .approvata: return .green
        }
    }
}

// MARK: - Esito

struct EsitoStimaEditor: View {
    @ObservedObject var perizia: Perizia
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Esito", selection: Binding(
                get: { perizia.esitoStimaValue },
                set: { nuovo in
                    perizia.esitoStimaValue = nuovo
                    if nuovo != .negativo { perizia.dannoNonAccertato = false }
                    salva()
                }
            )) {
                ForEach(EsitoStima.allCases) { Text($0.etichetta).tag($0) }
            }
            .pickerStyle(.segmented)

            switch perizia.esitoStimaValue {
            case .nonConcordato:
                Picker("Motivo", selection: Binding(
                    get: { perizia.motivoNonConcordato.flatMap(MotivoNonConcordato.init(rawValue:)) ?? .senzaRisposta },
                    set: { perizia.motivoNonConcordato = $0.rawValue; salva() }
                )) {
                    ForEach(MotivoNonConcordato.allCases) { Text($0.etichetta).tag($0) }
                }
                TextField("Dettaglio del motivo (obbligatorio con «Altro»)", text: Binding(
                    get: { perizia.motivoNonConcordatoTesto ?? "" },
                    set: { perizia.motivoNonConcordatoTesto = $0.isEmpty ? nil : $0; salva() }
                ))
                .textFieldStyle(.roundedBorder)
            case .negativo:
                Toggle("Danno non accertato: indennizzo nullo con stima conservativa (la stima diventa riserva)", isOn: Binding(
                    get: { perizia.dannoNonAccertato },
                    set: { perizia.dannoNonAccertato = $0; salva() }
                ))
                .font(.caption)
                if !perizia.dannoNonAccertato {
                    TextField("Motivo della riserva / della negativa", text: Binding(
                        get: { perizia.noteRiserva ?? "" },
                        set: { perizia.noteRiserva = $0.isEmpty ? nil : $0; salva() }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
            default:
                EmptyView()
            }
        }
    }

    private func salva() { try? viewContext.save() }
}

// MARK: - Revisioni e approvazione

struct RevisioniStimaView: View {
    @ObservedObject var perizia: Perizia
    let calcolo: StimaCalcolo?
    @Environment(\.managedObjectContext) private var viewContext
    @State private var errore: String?
    @State private var mostraStorico = false

    private let service = StimaService.shared

    var body: some View {
        let stato = service.stato(perizia, calcolo: calcolo)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StatoStimaBadge(stato: stato)
                Spacer()
                if mostraAzioni(stato) {
                    Button {
                        salvaRevisione()
                    } label: {
                        Label("Salva revisione", systemImage: "square.and.arrow.down")
                    }
                    .disabled(!salvabile(stato))
                    .help("Fotografa input e calcolo: la revisione resta immutabile")

                    Button {
                        approvaUltima()
                    } label: {
                        Label("Approva stima", systemImage: "checkmark.seal")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(calcolo == nil)
                    .help("Salva (se serve) e approva la stima corrente: le revisioni precedenti diventano superate")
                }
                if !perizia.stimaRevisioniArray.isEmpty {
                    Button {
                        mostraStorico.toggle()
                    } label: {
                        Image(systemName: mostraStorico ? "chevron.up" : "clock.arrow.circlepath")
                    }
                    .buttonStyle(.borderless)
                    .help("Storico delle revisioni")
                }
            }
            if let errore {
                Text(errore).font(.caption).foregroundColor(.red)
            }
            if mostraStorico {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(perizia.stimaRevisioniArray.reversed()) { r in
                        HStack {
                            Text("Rev. \(r.numero)").fontWeight(.semibold)
                            Text(r.dataCreazione.map { DateUtils.formatLong($0) } ?? "")
                                .foregroundColor(.secondary)
                            Text(r.esitoValue.etichetta).foregroundColor(.secondary)
                            Spacer()
                            Text(euroStima(r.liquidabile?.decimalValue))
                                .font(.system(.caption, design: .monospaced))
                            if r.superata {
                                Text("superata").foregroundColor(.secondary).italic()
                            } else if r.approvata {
                                Text(r.ereditataDa > 0 ? "approvata (eredit.)" : "approvata").foregroundColor(.green)
                            }
                        }
                        .font(.caption)
                        .help(r.approvataDa.map { "Approvata da \($0)" } ?? "Non approvata")
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.controlBackgroundColor)))
            }
        }
    }

    private func mostraAzioni(_ stato: StimaService.StatoStima) -> Bool {
        switch stato {
        case .approvata, .errori: return false
        default: return true
        }
    }

    private func salvabile(_ stato: StimaService.StatoStima) -> Bool {
        switch stato {
        case .nessunaRevisione, .daSalvare: return true
        default: return false
        }
    }

    private func salvaRevisione() {
        do {
            try service.salvaRevisione(perizia, context: viewContext)
            errore = nil
        } catch {
            errore = error.localizedDescription
        }
    }

    private func approvaUltima() {
        do {
            let stato = service.stato(perizia, calcolo: calcolo)
            if salvabile(stato) { try service.salvaRevisione(perizia, context: viewContext) }
            guard let ultima = service.ultimaRevisione(perizia) else { return }
            if !ultima.approvata {
                let chi = GoogleAuthService.shared.userEmail ?? "perito"
                try service.approva(ultima, da: chi, context: viewContext)
            }
            errore = nil
        } catch {
            errore = error.localizedDescription
        }
    }
}
