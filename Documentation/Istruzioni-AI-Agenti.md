---
tags: [perx, meta, ai-instructions]
updated: 2026-09-05
---

# Istruzioni per le IA (e gli sviluppatori) che lavorano su PerX

Questa nota vale per **qualunque agente AI** operi su questo repository — Claude Code, Codex,
Cursor o altro — e per chiunque contribuisca allo sviluppo. Non è una nota opzionale: è una regola
operativa del progetto, richiamata da [[Home]] e dal `CLAUDE.md`/`AGENTS.md` nella root del repo.

## La regola

> **La documentazione in `Documentation/` deve restare sempre allineata al codice e alle decisioni
> prese, senza eccezioni.** Non è un'attività separata da pianificare "dopo": fa parte della
> definizione di "fatto" di qualunque task di sviluppo su questo repo.

Questo significa concretamente:

1. **Ogni modifica architetturale, nuova funzionalità, nuovo endpoint, nuovo modello dati o
   cambio di stato di avanzamento** va riportata nella nota pertinente (piattaforma o
   funzionalità) **nello stesso task** in cui viene realizzata — non rimandata a un secondo
   momento.
2. **Ogni intenzione di sviluppo futuro discussa con l'utente**, anche se non ancora implementata
   e anche se è solo un'idea abbozzata in chat, va annotata subito in
   [[06-Decisioni-e-Intenzioni-Future]] con data. Meglio una riga in più che perdere il contesto
   di una decisione.
3. **Se una nota risulta obsoleta o in contraddizione con il codice attuale**, va corretta subito
   quando ce se ne accorge, indipendentemente dal task in corso.
4. **In caso di dubbio se una modifica meriti un aggiornamento della doc, va aggiornata comunque.**
   Il bias di default è "aggiorna", non "salta".
5. **Non creare nuovi file `.md` sparsi nella repo** per descrivere architettura, feature o
   decisioni: tutto questo tipo di contenuto vive in `Documentation/` (questo vault). I `README.md`
   locali ai singoli moduli restano per istruzioni pratiche (setup, comandi, build) e possono
   linkare qui, ma non devono duplicare i contenuti architetturali.
6. **Mantieni il campo `updated:` nel frontmatter e la riga "Ultimo aggiornamento" in fondo alla
   nota** aggiornati alla data in cui la nota viene toccata.
7. **Usa i wikilink `[[NomeNota]]`** per collegare le note tra loro invece di ripetere contenuti:
   il vault deve restare navigabile e senza duplicazioni.

## Checklist rapida a fine task

- [ ] Ho introdotto o cambiato una funzionalità, un endpoint, un flusso o un componente? →
      aggiorna la nota di piattaforma/funzionalità corrispondente.
- [ ] Ho preso o discusso con l'utente una decisione architetturale, anche provvisoria? →
      aggiungi una voce datata in [[06-Decisioni-e-Intenzioni-Future]].
- [ ] Lo stato di avanzamento di un componente è cambiato (da "da fare" a "in corso", da "in
      corso" a "implementato")? → aggiorna [[05-Stato-Sviluppo-e-Roadmap]].
- [ ] Ho toccato build, deploy, variabili d'ambiente o infrastruttura? → aggiorna
      [[04-Infrastruttura-e-Deploy]].
- [ ] Ho aggiunto una dipendenza, un framework o cambiato uno stack? → aggiorna
      [[03-Stack-Tecnologico]].

## Cosa NON fare

- Non lasciare la documentazione "per dopo": in questo progetto la doc disallineata dal codice è
  considerata un difetto del lavoro, non un dettaglio rimandabile.
- Non riscrivere interi capitoli quando basta un aggiornamento puntuale: preferisci modifiche
  chirurgiche che preservano il lavoro di chi ha scritto la nota prima.
- Non lasciare doppioni: se un'informazione esiste già in un'altra nota, linkala invece di
  ricopiarla.

---
Ultimo aggiornamento: 2026-09-05
