---
tags: [perx, piattaforma, ios]
updated: 2026-09-05
---

# Varianti iOS: PerX Lite e PerX per iPad

Due target Apple aggiuntivi rispetto all'[[PerX-App-Principale|app principale]], entrambi con
struttura interna analoga (`Models/`, `Services/`, `Views/`) ma perimetro di funzionalità più
ridotto.

## PerX Lite (`PerX Lite/`)

- Target pensato per iPhone, ~24 file Swift.
- Entry point `PerX_LiteApp.swift`, entitlements `PerX_Lite.entitlements`.
- Ha test dedicati: `PerX LiteTests/`, `PerX LiteUITests/`.

## PerX per iPad (`PerX per iPad/`)

- Viste e servizi specifici per l'esperienza iPad, ~46 file Swift.
- Entry point `PerX_iPadApp.swift`, con due set di entitlements (`PerX_iPad.entitlements`,
  `PerX_per_iPad.entitlements` — verificare quale sia quello attivo prima di modifiche ai
  permessi).
- Ha test dedicati: `PerX per iPadTests/`, `PerX per iPadUITests/`.

## Nota per chi sviluppa

Quando una funzionalità condivisa (es. sistema task, adapter, AI) viene modificata nell'app
principale, verificare se le due varianti la replicano e se vanno aggiornate di conseguenza:
al momento non risulta un modulo Swift Package condiviso dedicato oltre a `PerXCore/` — verificare
nel codice corrente prima di assumere parità di funzionalità tra i tre target.

---
Ultimo aggiornamento: 2026-09-05
