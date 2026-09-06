# PerX Lite - Compila da Excel

Estensione Chrome (Manifest V3) che legge un Excel (Elaborato Peritale) e una foto, e compila i
campi corrispondenti sulla pagina JFish aperta. Nessun account, nessun Hub, nessun sync cloud:
tutto resta nel browser dell'utente.

Per architettura, scelte e rischi noti → vedi la nota di progetto
[`Documentation/Piattaforme/PerX-Lite-Extension.md`](../Documentation/Piattaforme/PerX-Lite-Extension.md).
Questo file contiene solo le istruzioni pratiche di installazione e uso.

## Installazione (modalità sviluppatore)

1. Apri Chrome e vai a `chrome://extensions`
2. Attiva "Modalità sviluppatore" (in alto a destra)
3. Clicca "Carica estensione non pacchettizzata"
4. Seleziona questa cartella (`perx_lite_extension`)
5. L'icona comparirà nella barra degli strumenti — clicca sul puzzle per fissarla

> La cartella deve restare al suo posto: Chrome carica l'estensione direttamente da lì, non ne fa
> una copia.

## Uso

1. Apri il dettaglio del sinistro sulla pagina JFish (`https://act.jfish.it/...`)
2. Clicca sull'icona dell'estensione
3. Carica il file Excel dell'Elaborato Peritale (`.xlsx`/`.xlsm`)
4. Se l'Excel ha più fogli, scegli quello giusto dal menu "Foglio"
5. Per ogni valore trovato, scegli dal menu a tendina in quale campo della pagina va inserito
   (la scelta viene ricordata per la prossima volta con lo stesso template)
6. Carica opzionalmente una foto da allegare
7. Clicca "Compila pagina"

Se la pagina ha più campi per caricare file, l'estensione chiede quale usare per la foto prima di
caricarla.

## Struttura file

```
perx_lite_extension/
├── manifest.json     # Manifest V3: solo activeTab + scripting + storage
├── popup.html/css/js # UI ed logica: lettura Excel, mappatura, orchestrazione
├── filler.js          # Iniettato on-demand nella tab attiva: compila i campi e allega la foto
├── vendor/
│   └── xlsx.full.min.js  # SheetJS, vendorizzato localmente (nessuna chiamata di rete)
└── icons/
```

## Limiti noti

- Pensata per il gestionale JFish (`act.jfish.it`): il rilevamento dell'ID sinistro e i selettori
  dei campi sono specifici per quel DOM.
- L'allegato della foto usa `DataTransfer` + eventi `change`/`drop` su `input[type=file]`: se il
  campo upload della pagina è un componente Syncfusion Uploader con logica di caricamento
  asincrona propria, potrebbe non bastare — non ancora verificato contro il DOM live.
- Riconoscimento etichetta→valore basato su euristica (celle numeriche/data sempre valori; celle
  testuali solo se precedute da un'etichetta terminante con `:`). Se l'estrazione non trova un
  valore atteso, resta comunque possibile mapparlo a mano scorrendo l'elenco nel popup.
