# Matrice CTU - Somiglianza Funzionale/Architetturale (Modulo CAT)

Data analisi: 2026-02-24  
Ambito: confronto tra repository principale e dump frontend cliente (`ModaleDinamica JFISH`).

## Metodo

1. Confronto su tre livelli:
   - Funzionalita' (cosa fa il sistema).
   - Implementazione (come e' modellato/gestito).
   - Copia letterale (testo/codice identico).
2. Evidenze ancorate a file e linee.
3. Punteggi qualitativi: `Alta`, `Media`, `Bassa`, `Assente`.

## Sintesi tecnica

- Copia letterale: **Assente** (nessun overlap testuale significativo emerso).
- Architettura complessiva: **Divergente** (codebase cliente legacy class-based + Syncfusion; repo principale hook-based + MapLibre + Supabase).
- Modulo CAT: **Somiglianza funzionale parziale significativa** su flussi centrali (mappa territoriale, selezione area, assegnazione CAT, gestione indisponibilita').

## Matrice comparativa (evidenze)

| ID | Elemento | Evidenza cliente | Evidenza repo principale | Valutazione |
|---|---|---|---|---|
| M1 | Configurazione geografica CAT su mappa Italia | `CATDispatcher` inizializza OSM + layer comuni colorati per CAT (`ModaleDinamica JFISH/CATDispatcher.jsx.swift`:723-727, 803-813, 1565) | Mappa raster OSM + poligoni comuni/quartieri colorati da CAT (`src/components/Map.tsx`:115-140, 185-203, 454-473) | Alta (funzionale) |
| M2 | Selezione area geografica e focus/zoom | Click su layer, selezione singola/multipla, focus bounds (`ModaleDinamica JFISH/CATDispatcher.jsx.swift`:818-835, 1048-1054) | Click su feature per selezione comune/quartiere + center su comune/CAT (`src/components/Map.tsx`:315-353, 684-713, 715-741) | Alta (funzionale) |
| M3 | Assegnazione CAT al territorio | Assegna CAT primario ai comuni selezionati (`ModaleDinamica JFISH/CATDispatcher.jsx.swift`:891-939) | Gestione assegnazioni per comune, set primario e add CAT (`src/components/admin/CommuneManager.tsx`:201-219, 231-247) | Alta (funzionale) |
| M4 | Modellazione priorita'/ruoli CAT | Struttura `prio:1/2`, overlap e backup espliciti (`ModaleDinamica JFISH/CATDispatcher.jsx.swift`:133-155, 1068-1102, 1648-1683; `ModaleDinamica JFISH/CATAssignmentResult.jsx`:6-10) | Struttura `is_primary` + `intervention_type` (`src/components/Map.tsx`:89-103; `src/components/admin/CommuneManager.tsx`:202-209, 244-245) | Media (implementativa) |
| M5 | Gestione indisponibilita'/sospensione CAT | Form indisponibilita' con motivo+periodo (`ModaleDinamica JFISH/CATDispatcher.jsx.swift`:1600-1644) | Gestione CAT sospeso/disattivato con motivi e conferma assegnazione (`src/components/CommunePopup.tsx`:221-279; `src/pages/ApiMode.tsx`:244-258, 356-385) | Media (funzionale) |
| M6 | Territori speciali (bonus/disagiati/province logistiche) | Toggle, editing e salvataggio DB (`ModaleDinamica JFISH/CATDispatcher.jsx.swift`:1687-1735, 1130-1263) | Non emerso equivalente diretto nel repo principale | Bassa/Assente |
| M7 | Ricerca comune interna al modulo mappa | Ricerca testuale su comuni + risultati top 10 (`ModaleDinamica JFISH/CATDispatcher.jsx.swift`:699-708) | Ricerca e navigazione mappa presenti via componenti dedicati (`src/pages/Index.tsx`:273-285; `src/components/Map.tsx`:715-741) | Media (funzionale) |
| M8 | Export/print del perimetro CAT | Pipeline `html2canvas` + stampa (`ModaleDinamica JFISH/CATDispatcher.jsx.swift`:1265-1317) | Non emerso equivalente diretto nel modulo mappa principale | Bassa/Assente |
| M9 | Inserimento modulo CAT nella suite applicativa | Menu voce "Configurazione Geografica CAT" con import modulo (`ModaleDinamica JFISH/NavMenu.jsx`:40, 112-118) | Repo principale espone funzionalita' CAT distribuite in map/popup/admin (`src/pages/Index.tsx`:273-285; `src/pages/Admin.tsx`:250-285) | Media (prodotto) |
| M10 | Architettura tecnica complessiva | Legacy class components + Syncfusion (`ModaleDinamica JFISH/PaginaHome.jsx`:44, 815; `ModaleDinamica JFISH/NavMenu.jsx`:4-7) | Hook functional components + MapLibre/Supabase (`src/components/Map.tsx`:1-5, 33-38; `src/pages/Index.tsx`:1-14) | Divergente |

## Indici sintetici (stima tecnica, non giuridica)

- ISF (Indice Somiglianza Funzionale modulo CAT): **64/100** (somiglianza parziale significativa).
- ISI (Indice Somiglianza Implementativa): **18/100** (modello e stack in gran parte differenti).
- ICL (Indice Copia Letterale): **0/100** (nessuna evidenza forte di copia verbatim nel materiale analizzato).

## Lettura CTU operativa

1. L'ipotesi "copia dell'intera architettura software" non e' supportata dai dati disponibili.
2. L'ipotesi "riuso/derivazione del disegno funzionale del modulo CAT" e' tecnicamente plausibile e supportata da piu' convergenze operative.
3. Per rafforzare il nesso causale serve confronto con la versione esatta consegnata in licenza (snapshot firmato/commit hash) e timeline contrattuale.

## Allegati consigliati per fase successiva

1. Snapshot sorgente consegnato al cliente (hash + data certa).
2. Tabella cronologica: consegna, accessi, recesso, messa online della controparte.
3. Diff semantico su naming raro, regole edge-case e sequenza UI (non solo testo).
