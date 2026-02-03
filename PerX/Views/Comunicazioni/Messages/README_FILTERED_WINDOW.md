# FilteredSinistriWindow - Documentazione

## Descrizione
`FilteredSinistriWindow` è una finestra modale riutilizzabile per visualizzare elenchi filtrati di sinistri. Può essere utilizzata in diversi contesti dell'app.

## Caratteristiche

### 1. **Filtri Predefiniti da Hashtag**
La finestra si configura automaticamente in base all'hashtag cliccato:

- `#chiusi` → Sinistri chiusi
- `#aperti` → Sinistri aperti  
- `#sinistri` → Tutti i sinistri
- `#assegnati` → Sinistri assegnati all'utente
- `#urgenti` → Sinistri con task pendenti
- `#scadenze` → Sinistri con scadenze imminenti (entro 7 giorni)

### 2. **Ambiti di Filtro**
Ogni hashtag supporta tre ambiti:

- **miei/utente**: Sinistri dell'utente che ha inviato il messaggio
- **tutti/studio**: Tutti i sinistri dello studio
- **destinatario**: Sinistri del destinatario del messaggio (da implementare)

### 3. **Funzionalità**

#### Ricerca
- Campo di ricerca in tempo reale
- Cerca in: riferimento, assicurato, compagnia, indirizzo

#### Ordinamento
Menu con 6 opzioni:
- Data Incarico (recente/meno recente)
- Riferimento (A-Z / Z-A)
- Assicurato (A-Z / Z-A)

#### Pin Ontop
- Mantiene la finestra sempre in primo piano
- Toggle rapido dal pulsante pin

#### Esporta
- **CSV**: Con separatore punto e virgola
- **Excel**: Formato .xlsx (da implementare)
- **Export Semplificato**: Usa automaticamente le colonne visibili nella tabella
- Opzione per includere/escludere intestazioni
- Nome file automatico: "Titolo - Data.csv"
- Apertura automatica dopo export

### 4. **Colonne Disponibili**

#### Colonne Base
- **Riferimento** (obbligatoria)
- **Assicurato** (obbligatoria)
- Compagnia
- Data Incarico
- Stato
- Indirizzo

#### Colonne Avanzate
- **Concordato**: Sì/No con icona
- **Liquidazione**: Importo in € (formattato)
- **Giorni Gestione**: Solo per sinistri chiusi (giorni tra assegnazione e chiusura)
- **N° Solleciti**: Con icona colorata (rosso se >2, arancione se >0)
- **N° Beni**: Conteggio beni del sinistro
- **Complessità**: Stelle da 1 a 3

#### Gestione Dinamica
- Pulsante "tablecells" nell'header per gestire colonne visibili
- Colonne obbligatorie non disattivabili
- Preset automatici in base al tipo di filtro:
  - **Chiusi**: riferimento, assicurato, compagnia, data, stato, concordato, liquidazione, giorni gestione
  - **Aperti**: riferimento, assicurato, compagnia, data, stato, solleciti, complessità
  - **Tutti**: riferimento, assicurato, compagnia, data, stato, beni, complessità

## Utilizzo

### Da Chat/Messaggi
La finestra si apre automaticamente cliccando sul pulsante "Visualizza elenco" nel popover dell'hashtag.

```swift
ChatDetailViewHelper.openHashtagWindow(
    hashtag: ChatHashtag(tag: "chiusi", filter: "utente"),
    senderEmail: "m.pernozzoli@actsrl.it",
    senderName: "Marco Pernozzoli"
)
```

### Da ConsuntivoView (da implementare)

#### Per sinistri chiusi:
```swift
let config = FilterConfig(
    title: "Sinistri Chiusi nel Periodo",
    subtitle: "Dal \(startDate) al \(endDate)",
    iconName: "checkmark.circle.fill",
    iconColor: .green,
    states: ["Chiuso"],
    userEmail: selectedUserEmail,
    dateFilter: .custom(from: startDate, to: endDate),
    customFilter: nil,
    columnsToShow: [.riferimento, .assicurato, .compagnia, .dataIncarico, .stato]
)

let windowView = FilteredSinistriWindow(config: config)
    .environment(\.managedObjectContext, viewContext)

// Apri finestra...
```

#### Per dettaglio fatturazione:
```swift
let config = FilterConfig(
    title: "Dettaglio Fatturazione",
    subtitle: "Fattura #\(numeroFattura)",
    iconName: "doc.text.fill",
    iconColor: .blue,
    states: nil,
    userEmail: nil,
    dateFilter: nil,
    customFilter: { sinistro in
        // Filtra sinistri inclusi nella fattura
        fattura.sinistri.contains(sinistro.riferimento)
    },
    columnsToShow: [.riferimento, .assicurato, .dataIncarico, .stato]
)

let windowView = FilteredSinistriWindow(config: config)
    .environment(\.managedObjectContext, viewContext)

// Apri finestra...
```

## Personalizzazione Filtri

### DateFilter
```swift
enum DateFilter {
    case thisYear           // Anno corrente
    case lastYear           // Anno scorso
    case last30Days         // Ultimi 30 giorni
    case custom(from: Date, to: Date)  // Periodo personalizzato
}
```

### Custom Filter
Per logiche di filtro complesse:

```swift
customFilter: { sinistro in
    // Esempio: sinistri con importo > 10.000€
    return (sinistro.importoStimato ?? 0) > 10000
}
```

## Integrazione ConsuntivoView

### 1. Sostituire tabella sinistri chiusi
Nel `ConsuntivoView.swift`, sostituire la sezione dei sinistri chiusi con un pulsante che apre questa finestra:

```swift
Button("Visualizza Sinistri Chiusi (\(count))") {
    let config = FilterConfig(
        title: "Sinistri Chiusi - \(month) \(year)",
        subtitle: "\(count) sinistri",
        iconName: "checkmark.circle.fill",
        iconColor: .green,
        states: ["Chiuso"],
        userEmail: nil,
        dateFilter: .custom(from: monthStart, to: monthEnd),
        customFilter: nil,
        columnsToShow: [.riferimento, .assicurato, .compagnia, .dataIncarico]
    )
    
    openFilteredWindow(config: config)
}
```

### 2. Dettaglio fatturazione
Nella sezione dettaglio fattura, aggiungere pulsante per vedere i sinistri inclusi:

```swift
Button("Dettaglio Sinistri") {
    let config = FilterConfig(
        title: "Fattura #\(fattura.numero)",
        subtitle: "\(fattura.sinistri.count) sinistri",
        iconName: "doc.text.fill",
        iconColor: .blue,
        states: nil,
        userEmail: nil,
        dateFilter: nil,
        customFilter: { sinistro in
            fattura.sinistri.contains(sinistro.riferimento ?? "")
        },
        columnsToShow: [.riferimento, .assicurato, .dataIncarico, .compagnia]
    )
    
    openFilteredWindow(config: config)
}
```

## Note Implementative

### Export Excel
Per implementare l'export Excel vero (non CSV), considerare:

1. **Libreria CSV.swift**
   - Più semplice, genera .csv con formattazione corretta
   - Apribile in Excel

2. **XlsxWriter**
   - Genera file .xlsx nativi
   - Supporta formattazione avanzata

3. **Openpyxl tramite Python**
   - Richiede script Python
   - Massima flessibilità

### Performance
- LazyVStack per scroll performante
- Filtri applicati in memoria (veloce per <10k sinistri)
- Considera paginazione per dataset molto grandi

### Accessibilità
- Tutte le azioni hanno `.help()` tooltips
- Supporto keyboard shortcuts (Esc, Return)
- VoiceOver compatible

## Completato ✅
- [x] Colonne dinamiche configurabili dall'utente
- [x] Rimozione colonne comune/provincia
- [x] Aggiunta colonne avanzate (concordato, liquidazione, giorni gestione, solleciti, beni, complessità)
- [x] Preset automatici per tipo di filtro
- [x] Export semplificato con colonne visibili
- [x] Popover gestione colonne in-app

## TODO
- [ ] Implementare export Excel nativo (.xlsx)
- [ ] Aggiungere filtro "destinatario" per hashtag
- [ ] Supporto drag & drop per riordino colonne nella UI
- [ ] Cache risultati ricerca per performance
- [ ] Integrazione in ConsuntivoView
- [ ] Aggiungere grafici/statistiche nella finestra
- [ ] Supporto print/PDF export
- [ ] Salvataggio preferenze colonne per tipo di filtro
