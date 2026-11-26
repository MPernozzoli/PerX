---
tags: [perx, funzionalita, sinistri, perizia, stima]
updated: 2026-11-26
---

# Motore di stima deterministico

Dal 2026-11-26 tutti gli importi della perizia nell'app macOS (Elaborato Calcoli, Riepilogo, Atto,
relazione, scheda Importi del sinistro) vengono da **un solo motore**, portato dal sistema
«sinistri chiari» del perito (`stima.py`, vedi [[06-Decisioni-e-Intenzioni-Future]]) e adattato ai
criteri PerX (VSU/SI, IVA a saldo, forzature). Il flusso di compilazione **resta quello a pagine**
della perizia: Perxia → Quadro contrattuale → Elaborato Calcoli → Relazione peritale → Riepilogo →
Atto (vedi [[PerX-App-Principale]], [[Gestione-Sinistri]]).

## Principi

- **Deterministico**: il motore riceve una fotografia di soli valori (`StimaInput`) e restituisce
  sempre lo stesso calcolo (`StimaCalcolo`) e lo stesso hash. L'IA (Perxia) può compilare gli
  input, mai i totali.
- **Decimal al centesimo** con arrotondamento ROUND_HALF_UP; ogni voce è arrotondata prima di
  essere sommata, così ciò che si vede è ciò che si somma.
- **Errori bloccanti vs avvisi**: input impossibili (percentuali oltre 100, scoperto minimo oltre
  il massimo, arrotondamento oltre ±100 €, quota di bene comune non valida, riparto senza polizze)
  fermano il calcolo e vengono mostrati in rosso; le anomalie da guardare (centesimi, liquidabile
  oltre la richiesta, voce esclusa senza motivo, richiesta senza giustificativo, limiti applicati,
  IBAN non valido…) sono avvisi arancioni.

## Dove sta il codice

| File | Ruolo |
|---|---|
| `PerX/Services/Claims/Stima/StimaModels.swift` | Tipi di input/output, enum di dominio (esito, motivi di esclusione, criteri, motivi del non concordato) |
| `PerX/Services/Claims/Stima/StimaEngine.swift` | Validazione, calcolo, avvisi, scomposizione, arrotondamento assistito, IBAN mod 97, hash |
| `PerX/Services/Claims/Stima/StimaTesti.swift` | Testi generati: frase per l'atto, conclusioni per esito, frase IVA, grammatica dei beni |
| `PerX/Services/Claims/Stima/StimaService.swift` | Ponte Core Data ↔ motore, valori derivati delle voci, revisioni, approvazione, verifica atto firmato |
| `PerX/Services/Claims/CalcoliService.swift` | Facciata storica: stessa API di prima, ora delega al motore |
| `PerX/Views/Sinistri/Perizia/Stima/StimaComponents.swift` | Riquadri Richiesto/Accertato/Liquidabile, scomposizione, avvisi, esito, revisioni |
| `PerXTests/StimaEngineTests.swift` | Test Swift Testing del motore |

## Ordine del calcolo

**Per voce** (in «Elaborato Calcoli»): totale a nuovo = quantità × unitario → netto migliorie →
netto illesi → VSU (deprezzamento del bene o della riga; **non si applica a «Valore a nuovo»**) →
SI secondo il criterio (VSU + SI, max doppio/triplo/quadruplo; zero a valore a nuovo e allo stato
d'uso). Ogni passaggio forzato a mano (modalità «Forzatura») sostituisce il valore calcolato. Bene a
servizio comune: si imputa la sola quota della polizza.

**Per bene**: IVA per voce (aliquota del bene o della riga). Valori IVA inclusa → si scorpora.
IVA riconosciuta e ripristini ultimati → IVA in liquidazione; non ultimati → **IVA a saldo** (fuori
dall'atto). La «liquidazione forzata» del bene è l'importo finale del bene, IVA riconosciuta
compresa (come lo mostra la scheda bene).

**Per garanzia**:
1. danno accertato = imponibile ammesso + IVA in liquidazione + **arrotondamento** (con segno,
   ±100 €, sulla garanzia scelta o su quella con il danno maggiore);
2. **regola proporzionale** (art. 1907 c.c.), solo per partite a valore intero con «valore reale»
   indicato oltre la deroga;
3. **franchigia** oppure **scoperto** % con minimo/massimo, mai oltre il danno;
4. **somme assicurate per partita**: ogni partita paga al più la sua somma; la trattenuta si
   sconta prima sulle eccedenze oltre i limiti, poi sulle partite in ordine;
5. **massimale** della garanzia. Con «Massimale prima della franchigia» (salvato in perizia) limiti
   e massimale si applicano prima della trattenuta;
6. **riparto art. 1910 c.c.** (facoltativo): quota = danno × indennizzo virtuale proprio / somma
   degli indennizzi virtuali, con le coassicurazioni indirette del Quadro contrattuale;
7. **rettifiche manuali** dopo i limiti (le vecchie «voci personalizzate»).

Il liquidabile dei beni non ripristinati ha una quota **differita** (il supplemento), indicata
nell'atto. Le voci escluse formano la **riserva**.

## Richiesta

Priorità esclusiva, mai sommata due volte: richiesta a corpo del sinistro (Liquidazione) →
richiesta del bene → somma delle richieste delle voci. La richiesta va letta da un giustificativo:
ogni voce ha il flag «Giust.», l'importo richiesto e (clic destro) «richiesta IVA inclusa».

## Voci escluse

Una voce non indennizzabile ha un **motivo** (non indennizzabile, danno indiretto, bene non
visionato, non pertinente, non documentato, fuori garanzia, duplicata, opere accessorie, residui
non mantenuti, altro) e una nota interna. Nel testo per l'atto le voci escluse sono elencate per
motivo con una frase sobria, senza importi né criteri peritali. Con «residui mantenuti: No» le voci
del bene diventano escluse per «residui non mantenuti».

## Esiti

`In lavorazione` / `Concordato` / `Non concordato` (con motivo: atto non restituito, solleciti,
quantificazione non condivisa, documenti mancanti, irreperibile, intestazione contestata, altro) /
`Negativo` (accertato e liquidabile a zero, riserva = tutta la stima). Negativo con **danno non
accertato**: indennizzo nullo, la stima conservativa delle voci ammesse diventa la riserva e
l'importo dell'atto di accertamento. Ogni esito genera la sua frase per le conclusioni della
relazione («Frasi della stima» nella pagina Relazione peritale).

## Scomposizione richiesto → accertato → liquidabile

Cascata leggibile dal perito e dal cliente: voci escluse per motivo, migliorie/illesi/deprezzamento,
IVA non riconosciuta o a saldo, valutazione inferiore al richiesto, quota di beni comuni, forzature,
IVA riconosciuta, arrotondamento, differenza residua sulla richiesta; poi regola proporzionale,
franchigia/scoperto, limiti di polizza, riparto, rettifiche. Le due fasi tornano sempre con
accertato e liquidabile.

## Soglia di controllo

`workflow.relazioneCompleta` è vero oltre la soglia (default **5.000,00 €**, chiave UserDefaults
`perx.stima.sogliaControllo`), per i non concordati e per i negativi: è l'«authority check» di
[[Gestione-Sinistri]]. Nel sistema del perito corrisponde a ReClaim Light/Over, che qui non è
modellato (PerX non compila ReClaim/Salesforce).

## Revisioni e approvazione

- **Salva revisione** fotografa input e calcolo (entità Core Data `StimaRevisione`, JSON + hash).
- **Approva stima** salva se serve e approva; tutte le revisioni precedenti diventano **superate**:
  vale solo l'ultima approvata.
- **Hash economico**: impronta dei soli importi (esito positivo/negativo/non concordato, voci,
  limiti, totali). Se una nuova revisione ha lo stesso hash economico di una approvata,
  l'approvazione si **eredita** (cambiano solo testi, nomi, note). Se cambia l'economia, la stima
  torna «da approvare» e la pagina Atto lo segnala.
- **Verifica atto firmato** (pagina Atto): confronta l'importo dell'atto firmato con l'ultima stima
  approvata → `ok`, `stima_superata` (è l'importo di una revisione vecchia: va firmato l'atto
  aggiornato), `importo_diverso`, `senza_approvazione`; esito e data restano in perizia.

L'importo dell'atto è sempre quello del motore: liquidabile, oppure riserva per i negativi.

## Modello dati (Core Data v2)

Nuova versione `PerX v2.xcdatamodel` (corrente), migrazione leggera automatica; il modello `PerX`
resta nel bundle come sorgente. Solo attributi facoltativi:

- `Perizia`: `esitoStima`, `dannoNonAccertato`, `motivoNonConcordato`, `motivoNonConcordatoTesto`,
  `richiestaSinistro`, `arrotondamentoGaranziaId`, `massimalePrimaFranchigia`,
  `accompagnatoriaExtra`, `riparto1910Attivo`, `attoFirmatoImporto/Esito/Data`, relazione
  `stimaRevisioni`;
- `VoceCosto`: `motivoEsclusione`, `notaVoce`, `giustificativo`, `richiesta`,
  `richiestaIvaInclusa`, `deprezzamentoRiga`, `aliquotaIVARiga`;
- `Bene`: `genere`, `quotaComunePercentuale`, `unitaServite`;
- `Partita`: `valoreReale`; `Coassicurazione`: `indennizzoVirtuale`;
- nuova entità `StimaRevisione`.

Se lo store non si apre, `Persistence.swift` ora lo **sposta in backup**
(`PerX.backup-AAAAMMGG-HHMMSS.sqlite`) invece di cancellarlo.

## Cambi di comportamento rispetto al calcolo precedente

Da tenere presenti riaprendo perizie già impostate (le revisioni approvate restano congelate):

- **Valore a nuovo** non applica più il deprezzamento (prima pagava VSU deprezzato, come «stato d'uso»).
- Deprezzamento **0%** vale 0% (prima veniva letto come 20%).
- Deprezzamento e IVA **per riga** («Diversi per riga») vengono salvati e usati in liquidazione
  (prima erano solo stato temporaneo della tabella).
- La **somma assicurata** della partita fa da tetto; l'inserimento ora legge il formato italiano
  («250.000» = 250.000 €, prima diventava 250).
- L'**arrotondamento** entra nel danno accertato prima della franchigia (prima si sommava alla fine)
  ed è limitato a ±100 €; gli strumenti «↓ unità/decina» e «Importo finale» calcolano
  l'arrotondamento esatto anche con lo scoperto.
- Lo **scoperto** si calcola sul danno accertato comprensivo dell'IVA riconosciuta.
- «Massimale prima della franchigia» è salvato in perizia (prima era un interruttore non salvato
  e il Riepilogo calcolava sempre nell'altro ordine).
- Riepilogo laterale e schede bene usano deprezzamento e IVA dei beni (prima 20% e 22% fissi).

## Cosa non è stato portato da «sinistri chiari»

Payload Salesforce/ReClaim e selezione allegati, sinistri collegati multi-pratica (qui il bene
comune è per singola perizia), catalogo frasi completo (`frasi.py`), annualità del massimale per
più sinistri dello stesso assicurato, override di chiusura. Vedi
[[06-Decisioni-e-Intenzioni-Future]] e [[05-Stato-Sviluppo-e-Roadmap]].

---
Ultimo aggiornamento: 2026-11-26
