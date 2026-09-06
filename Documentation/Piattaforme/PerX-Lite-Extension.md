---
tags: [perx, piattaforma, chrome-extension, jfish]
updated: 2026-09-06
---

# PerX Lite - estensione Chrome (`perx_lite_extension/`)

Estensione Chrome (Manifest V3) volutamente "stupida": legge un file Excel (l'Elaborato Peritale
già prodotto dal perito) e una foto scelti dall'utente, e compila i campi corrispondenti sulla
pagina JFish che l'utente ha aperto. Nessun account, nessun backend, nessun sync cloud, nessun
service worker persistente — tutta la logica gira nel popup al momento del click.

Nasce come primo passo dell'idea "PerX Lite Web" discussa il 2026-09-05 (vedi
[[06-Decisioni-e-Intenzioni-Future]]), limitato per ora alla sola estensione: niente pagina web.

## Cosa fa

1. L'utente apre il popup e carica il file `.xlsx`/`.xlsm` dell'Elaborato Peritale.
2. L'estensione lo legge interamente in locale (libreria [SheetJS](https://sheetjs.com/), vendorizzata
   in `vendor/xlsx.full.min.js`, nessuna chiamata di rete) ed estrae le coppie etichetta→valore
   dal foglio scelto.
3. Per ogni valore trovato, l'utente sceglie a quale campo della pagina JFish va destinato tramite
   un menu a tendina; la scelta viene ricordata (per etichetta normalizzata, in
   `chrome.storage.local`) così le volte successive con lo stesso template la mappatura è già
   pronta.
4. L'utente carica opzionalmente una foto; al click su "Compila pagina" l'estensione inietta
   `filler.js` nella tab attiva, compila i campi mappati e — se c'è una foto — la allega al primo
   `input[type=file]` trovato in pagina (o fa scegliere quale, se ce n'è più di uno).

## Cosa NON fa (a differenza del vecchio `perx_chrome_extension`)

Il vecchio prototipo (mai arrivato su `main`, presente solo su branch di lavoro) era un vero
sincronizzatore bidirezionale JFish↔PerX: login Google OAuth, comunicazione con l'Hub via
Tailscale, icone di sync inline, diario, confronto differenze. PerX Lite rinuncia
deliberatamente a tutto questo:

- Nessuna autenticazione, nessun `oauth2` nel manifest.
- Nessun `background` service worker, nessun `content_scripts` dichiarato, nessun
  `host_permissions` — solo `activeTab` + `scripting` + `storage`. Il codice di riempimento
  (`filler.js`) viene iniettato on-demand nella tab attiva solo quando l'utente clicca "Compila",
  non gira in background.
- Nessuna comunicazione con PerXHub o col backend: è un tool locale, mono-direzionale
  (Excel → pagina), pensato per essere installabile ed eseguibile senza il resto della piattaforma
  PerX (Mac mini, Hub, Tailscale non servono).

## Riuso dal vecchio prototipo

L'unica logica portata 1:1 (perché già verificata sul gestionale reale) è in `filler.js`:
- la mappa `fieldKey → nome campo JFish` e il pattern di selettore
  `#{nomeCampo}{idSinistro}` (gli ID nei form JFish sono dinamici, con suffisso numerico del
  sinistro);
- `fillField()`/`triggerSyncfusionEvents()`: compilazione di input, date picker (formato italiano),
  dropdown Syncfusion (match su value o label) e rich text editor, con la sequenza di eventi
  `input`/`change`/`focus`/`blur` necessaria perché Syncfusion reagisca alla modifica.
- il rilevamento dell'ID sinistro dalla tab attiva (`detectSinistroId`, stessa cascata di fallback
  del vecchio `content.js`).

## Estrazione etichetta→valore dall'Excel

Non esiste un layout di colonne fisso da mappare (a differenza dell'export tabellare gestito da
`ImportService.swift`): l'Elaborato Peritale è un foglio di calcolo con celle etichetta/valore
posizionate liberamente. La regola di estrazione (in `popup.js`, `extractLabelValuePairs`):

- ogni cella **numerica, data o booleana** è considerata un valore candidato "sicuro" (mai
  ambiguo con un'etichetta);
- una cella **testuale** è un valore candidato solo se la cella a sinistra o sopra termina con
  `:` (per non spezzare titoli o testo libero in coppie inventate);
- l'etichetta è la cella non vuota più vicina a sinistra, poi sopra; se non c'è, si usa la
  coordinata (`Foglio - riga N, colonna M`) come etichetta sintetica, così il valore resta comunque
  mappabile a mano.

Le date lette da SheetJS (opzione `cellDates: true`) arrivano come oggetti `Date` nativi — nessun
bisogno di replicare `excelSerialDateToDate` come in `ImportService.swift`.

## Rischio noto: upload della foto su widget Syncfusion

`filler.js` assegna la foto tramite `DataTransfer` su `input.files` e dispatcha sia `change` che
`drop` per coprire sia input file semplici sia uploader drag&drop. Se il campo upload di JFish è
un componente Syncfusion Uploader con logica di caricamento asincrona propria, questo approccio
potrebbe non bastare (va verificato sul gestionale reale) — non testato contro il DOM live di
JFish al momento della scrittura.

## Stato

Implementato 2026-09-06 in una sessione unica (non ancora provato contro il DOM live di JFish).
Vive in `perx_lite_extension/` nella root del repo, non in `apps/` (non è un progetto Next.js/Vercel:
è un pacchetto Chrome caricato come estensione non pacchettizzata). Setup e installazione →
`perx_lite_extension/README.md`.

## Possibili evoluzioni

Vedi la voce del 2026-09-05 in [[06-Decisioni-e-Intenzioni-Future]] per l'idea originale completa
(profili di sito dichiarativi, pagina web come editor di profili condivisi, pubblicazione Chrome
Web Store). Nessuna di queste evoluzioni è stata iniziata: questa prima versione resta mirata solo
a JFish con mappatura salvata localmente per utente.

---
Ultimo aggiornamento: 2026-09-06
