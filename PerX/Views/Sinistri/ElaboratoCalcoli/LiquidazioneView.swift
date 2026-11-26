import SwiftUI
import CoreData

/// Rettifica manuale applicata dopo franchigia/scoperto e limiti (es. quota conto terzi).
/// Salvata in `Perizia.vociPersonalizzateJSON`; il motore la somma al liquidabile e la mostra nella scomposizione.
struct VocePersonalizzata: Identifiable, Codable, Equatable {
    let id: UUID
    var descrizione: String
    var valore: Double

    init(id: UUID = UUID(), descrizione: String, valore: Double) {
        self.id = id
        self.descrizione = descrizione
        self.valore = valore
    }
}

/// Liquidazione della perizia (pagina «Elaborato Calcoli»): tutto viene dal motore di stima deterministico.
/// Ordine del calcolo per garanzia: voci ammesse (+ IVA riconosciuta) + arrotondamento = danno accertato →
/// regola proporzionale → franchigia/scoperto → somme assicurate per partita → massimale → riparto 1910 → rettifiche.
struct LiquidazioneView: View {
    @ObservedObject var perizia: Perizia
    @Environment(\.managedObjectContext) private var viewContext

    @State private var token = 0
    @State private var importoFinaleDesiderato: String = ""
    @State private var messaggioArrotondamento: String?
    @State private var vociPersonalizzate: [VocePersonalizzata] = []
    @State private var showAggiungiVoceSheet = false
    @State private var nuovaVoceDescrizione = ""
    @State private var nuovaVoceValore = ""
    @State private var mostraScomposizione = true

    private let service = StimaService.shared

    var body: some View {
        let risultato = service.calcola(perizia)
        let _ = token
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                header(risultato)
                Divider()
                esitoSection
                switch risultato {
                case .failure(let errori):
                    AvvisiStimaView(errori: errori.messaggi)
                case .success(let calcolo):
                    contenuto(calcolo)
                }
            }
            .padding(16)
        }
        .backgroundStyle(.regularMaterial)
        .ricalcolaSuModifiche($token)
        .onAppear {
            caricaVociPersonalizzate()
            allineaStimaSalvata()
        }
        .onChange(of: token) { _, _ in allineaStimaSalvata() }
        .sheet(isPresented: $showAggiungiVoceSheet) {
            AggiungiVocePersonalizzataSheet(
                descrizione: $nuovaVoceDescrizione,
                valore: $nuovaVoceValore,
                onAggiungi: aggiungiRettifica
            )
        }
    }

    // MARK: - Header

    private func header(_ risultato: Result<StimaCalcolo, StimaErrori>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "eurosign.circle.fill").foregroundColor(.green)
                Text("Liquidazione").font(.title3).fontWeight(.bold)
                Spacer()
                Toggle("Massimale prima della franchigia", isOn: Binding(
                    get: { perizia.massimalePrimaFranchigia },
                    set: { perizia.massimalePrimaFranchigia = $0; salva() }
                ))
                .toggleStyle(.switch)
                .font(.caption)
                .help("Ordine alternativo previsto da alcune polizze: limiti e massimale si applicano prima di franchigia/scoperto")
            }
            RevisioniStimaView(perizia: perizia, calcolo: try? risultato.get())
        }
    }

    private var esitoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Esito della perizia").font(.subheadline.weight(.semibold))
            EsitoStimaEditor(perizia: perizia)
            HStack {
                Text("Richiesta a corpo per il sinistro")
                    .font(.caption).foregroundColor(.secondary)
                TextField("dal giustificativo, prevale su beni e voci", value: Binding(
                    get: { perizia.richiestaSinistro?.doubleValue },
                    set: { perizia.richiestaSinistro = $0.flatMap { $0 > 0 ? NSDecimalNumber(value: $0) : nil }; salva() }
                ), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            }
        }
    }

    // MARK: - Contenuto

    @ViewBuilder
    private func contenuto(_ calcolo: StimaCalcolo) -> some View {
        StimaKPIView(calcolo: calcolo)
        AvvisiStimaView(avvisi: calcolo.avvisi)

        ForEach(calcolo.liquidazioni) { l in
            garanziaCard(l, calcolo: calcolo)
        }

        if let riparto = calcolo.riparto1910 {
            ripartoCard(riparto)
        }
        ripartoToggle

        arrotondamentoSection(calcolo)
        rettificheSection

        DisclosureGroup(isExpanded: $mostraScomposizione) {
            ScomposizioneStimaView(calcolo: calcolo)
                .padding(.top, 6)
        } label: {
            Text("Scomposizione richiesto → accertato → liquidabile").font(.subheadline.weight(.semibold))
        }

        workflowRow(calcolo.workflow)
        testiSection(calcolo)
    }

    private func garanziaCard(_ l: LiquidazioneGaranzia, calcolo: StimaCalcolo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "shield.lefthalf.filled").foregroundColor(.blue)
                Text(l.nome).font(.headline)
                Spacer()
                if l.tuttoNonIndennizzabile {
                    Text("NON INDENNIZZABILE").font(.caption.weight(.bold)).foregroundColor(.red)
                }
            }
            riga("VSU", l.vsu)
            if l.si > 0 { riga("Supplemento d'indennizzo (SI)", l.si) }
            if l.ivaInLiquidazione > 0 { riga("IVA riconosciuta", l.ivaInLiquidazione) }
            if l.arrotondamento != 0 { riga("Arrotondamento", l.arrotondamento) }
            riga("Danno accertato", l.dannoAccertato, forte: true)
            if l.riduzioneProporzionale > 0 { riga("Regola proporzionale (art. 1907 c.c.)", -l.riduzioneProporzionale) }
            if l.trattenuta > 0 {
                riga(l.tipoTrattenuta == .scoperto ? "Scoperto" : "Franchigia", -l.trattenuta)
            }
            ForEach(l.partite, id: \.partitaId) { p in
                HStack {
                    Text("Partita \(p.nome)").font(.caption)
                    if let r = p.rapportoProporzionale {
                        Text("rapporto \(percentualeIt((r * 100).arrotondato()))").font(.caption2).foregroundColor(.orange)
                    }
                    Spacer()
                    Text("somma \(euroStima(p.sommaAssicurata))").font(.caption2).foregroundColor(.secondary)
                    Text(euroStima(p.liquidabile))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(p.limitata ? .orange : .primary)
                }
                .padding(.leading, 12)
            }
            if l.massimale > 0 {
                HStack {
                    Text("Massimale").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text(euroStima(l.massimale))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(l.massimaleApplicato ? .orange : .secondary)
                }
            }
            if let prima = l.liquidabilePrimaRiparto { riga("Liquidabile prima del riparto", prima) }
            Divider()
            riga("Liquidabile", l.liquidabile, forte: true, colore: .green)
            if l.liquidabileDifferito > 0 {
                riga("di cui a ripristini ultimati", l.liquidabileDifferito, colore: .secondary)
            }
            if l.ivaASaldo > 0 { riga("IVA a saldo (fuori atto)", l.ivaASaldo, colore: .secondary) }
            if l.dannoNonIndennizzabile > 0 { riga("Riserva (voci escluse)", l.dannoNonIndennizzabile, colore: .red) }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(NSColor.controlBackgroundColor)))
    }

    private func riga(_ etichetta: String, _ valore: Decimal, forte: Bool = false, colore: Color = .primary) -> some View {
        HStack {
            Text(etichetta).font(forte ? .callout.weight(.semibold) : .callout)
            Spacer()
            Text((valore < 0 ? "− " : "") + euroStima(abs(valore)))
                .font(.system(.callout, design: .monospaced).weight(forte ? .semibold : .regular))
                .foregroundColor(valore < 0 ? .red : colore)
        }
    }

    // MARK: - Riparto art. 1910

    private var ripartoToggle: some View {
        Toggle("Riparto art. 1910 c.c. con le altre polizze (coassicurazioni indirette del Quadro contrattuale)", isOn: Binding(
            get: { perizia.riparto1910Attivo },
            set: { perizia.riparto1910Attivo = $0; salva() }
        ))
        .font(.caption)
        .help("Quota = danno accertato × indennizzo virtuale di questa polizza / somma degli indennizzi virtuali. Indicare l'indennizzo virtuale delle altre polizze nelle coassicurazioni indirette.")
    }

    private func ripartoCard(_ r: RipartoCalcolato) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Riparto art. 1910 c.c.").font(.subheadline.weight(.semibold))
            riga("Indennizzo virtuale di questa polizza", r.indennizzoVirtuale)
            riga("Somma degli indennizzi virtuali", r.sommaIndennizziVirtuali)
            ForEach(r.righe, id: \.descrizione) { riga($0.descrizione, $0.importo) }
            riga("Quota a carico della polizza", r.quota, forte: true, colore: .green)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.06)))
    }

    // MARK: - Arrotondamento

    private func arrotondamentoSection(_ calcolo: StimaCalcolo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Arrotondamento").font(.subheadline.weight(.semibold))
                Text("(entro ± 100 €, sommato al danno accertato prima della franchigia)")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Text(euroStima(decimale(perizia.arrotondamentoLiquidazione)))
                    .font(.system(.callout, design: .monospaced))
            }
            HStack(spacing: 6) {
                Button("↓ unità") { arrotonda(calcolo, passo: 1) }
                Button("↓ decina") { arrotonda(calcolo, passo: 10) }
                Button("↓ cinquantina") { arrotonda(calcolo, passo: 50) }
                TextField("Importo finale", text: $importoFinaleDesiderato)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .onSubmit { applicaImportoFinale() }
                Button("Applica") { applicaImportoFinale() }
                    .disabled(importoFinaleDesiderato.isEmpty)
                Button(role: .destructive) {
                    perizia.arrotondamentoLiquidazione = nil
                    perizia.arrotondamentoGaranziaId = nil
                    messaggioArrotondamento = nil
                    salva()
                } label: { Image(systemName: "xmark.circle") }
                .disabled((perizia.arrotondamentoLiquidazione?.doubleValue ?? 0) == 0)
                .help("Elimina arrotondamento")
                if perizia.garanzieArray.count > 1 {
                    Picker("su", selection: Binding(
                        get: { perizia.arrotondamentoGaranziaId },
                        set: { perizia.arrotondamentoGaranziaId = $0; salva() }
                    )) {
                        Text("Garanzia principale").tag(nil as UUID?)
                        ForEach(perizia.garanzieArray) { g in
                            Text(g.nomeEditabile).tag(g.id as UUID?)
                        }
                    }
                    .frame(width: 220)
                }
            }
            .font(.caption)
            if let messaggioArrotondamento {
                Text(messaggioArrotondamento).font(.caption).foregroundColor(.orange)
            }
        }
    }

    private func arrotonda(_ calcolo: StimaCalcolo, passo: Decimal) {
        let attuale = calcolo.totali.liquidabile
        var q = attuale / passo
        var giu = Decimal()
        NSDecimalRound(&giu, &q, 0, .down)
        imposta(obiettivo: giu * passo)
    }

    private func applicaImportoFinale() {
        let testo = importoFinaleDesiderato
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard let obiettivo = Decimal(string: testo) else {
            messaggioArrotondamento = "Importo non valido"
            return
        }
        imposta(obiettivo: obiettivo)
        importoFinaleDesiderato = ""
    }

    private func imposta(obiettivo: Decimal) {
        let input = service.input(per: perizia)
        guard let arr = StimaEngine.arrotondamentoPer(obiettivo: obiettivo, input: input) else {
            messaggioArrotondamento = "Non è possibile ottenere \(euroStima(obiettivo)) con un arrotondamento entro ± 100 €: riduci o escludi le voci."
            return
        }
        messaggioArrotondamento = nil
        perizia.arrotondamentoLiquidazione = arr == 0 ? nil : NSDecimalNumber(decimal: arr)
        salva()
    }

    // MARK: - Rettifiche manuali

    private var rettificheSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Rettifiche dopo i limiti").font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    showAggiungiVoceSheet = true
                } label: {
                    Label("Aggiungi", systemImage: "plus")
                }
                .font(.caption)
            }
            ForEach(vociPersonalizzate) { voce in
                HStack {
                    Text(voce.descrizione).font(.caption)
                    Spacer()
                    Text(CurrencyFormatter.shared.formatWithSymbol(voce.valore))
                        .font(.system(.caption, design: .monospaced))
                    Button {
                        vociPersonalizzate.removeAll { $0.id == voce.id }
                        salvaVociPersonalizzate()
                    } label: { Image(systemName: "trash").foregroundColor(.red) }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func aggiungiRettifica() {
        let normalizzato = nuovaVoceValore
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let valore = Double(normalizzato) else { return }
        vociPersonalizzate.append(VocePersonalizzata(descrizione: nuovaVoceDescrizione, valore: valore))
        salvaVociPersonalizzate()
        nuovaVoceDescrizione = ""
        nuovaVoceValore = ""
        showAggiungiVoceSheet = false
    }

    private func caricaVociPersonalizzate() {
        guard let json = perizia.vociPersonalizzateJSON,
              let data = json.data(using: .utf8),
              let voci = try? JSONDecoder().decode([VocePersonalizzata].self, from: data) else {
            vociPersonalizzate = []
            return
        }
        vociPersonalizzate = voci
    }

    private func salvaVociPersonalizzate() {
        if let data = try? JSONEncoder().encode(vociPersonalizzate), let json = String(data: data, encoding: .utf8) {
            perizia.vociPersonalizzateJSON = vociPersonalizzate.isEmpty ? nil : json
            salva()
        }
    }

    // MARK: - Workflow e testi

    private func workflowRow(_ w: WorkflowStima) -> some View {
        Label(w.motivo, systemImage: w.relazioneCompleta ? "doc.text.magnifyingglass" : "bolt.horizontal.circle")
            .font(.caption)
            .foregroundColor(w.relazioneCompleta ? .purple : .secondary)
            .help("Soglia configurabile in UserDefaults «\(StimaService.chiaveSogliaControllo)»")
    }

    private func testiSection(_ calcolo: StimaCalcolo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Testo per l'atto (generato)").font(.subheadline.weight(.semibold))
            Text(calcolo.testi.accompagnatoria.isEmpty ? "Nessuna frase da aggiungere." : calcolo.testi.accompagnatoria)
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(NSColor.textBackgroundColor)))
            TextField("Frase aggiuntiva per l'atto (es. vincolo bancario, bene equivalente)", text: Binding(
                get: { perizia.accompagnatoriaExtra ?? "" },
                set: { perizia.accompagnatoriaExtra = $0.isEmpty ? nil : $0; salva() }
            ), axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(1...3)
            if !calcolo.testi.conclusioniEsito.isEmpty {
                Text("Conclusioni per la relazione: " + calcolo.testi.conclusioniEsito)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Persistenza

    /// Tiene allineati i valori derivati delle voci e la stima del danno salvata in perizia.
    private func allineaStimaSalvata() {
        service.allineaValoriDerivati(perizia)
        if viewContext.hasChanges { try? viewContext.save() }
    }

    private func salva() {
        try? viewContext.save()
    }

    private func decimale(_ n: NSDecimalNumber?) -> Decimal? {
        guard let n, n != NSDecimalNumber.notANumber else { return nil }
        return n.decimalValue
    }
}

struct AggiungiVocePersonalizzataSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var descrizione: String
    @Binding var valore: String
    let onAggiungi: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Aggiungi rettifica manuale")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                Text("Descrizione:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField("Es: quota conto terzi, maggiorazione della franchigia, etc.", text: $descrizione)
                    .textFieldStyle(.roundedBorder)

                Text("Valore:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                TextField("€ 0,00", text: $valore)
                    .textFieldStyle(.roundedBorder)
                    .help("Inserisci un valore positivo o negativo (es: -50,00 o 100,00)")

                Text("La rettifica si applica dopo franchigia, limiti e massimale e compare nella scomposizione.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Button("Annulla") {
                    dismiss()
                }

                Button("Aggiungi") {
                    onAggiungi()
                }
                .buttonStyle(.borderedProminent)
                .disabled(descrizione.isEmpty || valore.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}
