# Mapping Modello Dati: CoreData → Postgres

## Tabella Sinistro (CoreData) → claims (Postgres)

| Campo CoreData | Tipo | Campo Postgres | Tipo | Note |
|----------------|------|----------------|------|------|
| riferimento | String | external_ref | String | Chiave esterna principale |
| stato | String | stato_corrente | String | ID stato (es. "SV001") |
| numeroSinistroCompagnia | String | numero_sinistro | String | |
| nomeCompagnia | String | compagnia | String | |
| agenzia | String | agenzia | String | |
| codiceAgenzia | String | codice_agenzia | String | |
| emailAgenzia | String | email_agenzia | String | |
| telefonoAgenzia | String | telefono_agenzia | String | |
| nomeAssicurato | String | nome_assicurato | String | |
| emailAssicurato | String | email_assicurato | String | |
| telefonoAssicurato | String | telefono_assicurato | String | |
| indirizzoAssicurato | String | indirizzo_assicurato | String | |
| nomeContraente | String | nome_contraente | String | |
| emailContraente | String | email_contraente | String | |
| telefonoContraente | String | telefono_contraente | String | |
| indirizzoContraente | String | indirizzo_contraente | String | |
| nomeDanneggiato | String | nome_danneggiato | String | |
| emailDanneggiato | String | email_danneggiato | String | |
| telefonoDanneggiato | String | telefono_danneggiato | String | |
| indirizzoDanneggiato | String | indirizzo_danneggiato | String | |
| dataSinistro | Date | data_sinistro | DateTime | |
| dataDenuncia | Date | data_denuncia | DateTime | |
| dataIncarico | Date | data_incarico | DateTime | |
| dataAperturaGestione | Date | data_apertura_gestione | DateTime | |
| dataAssegnazione | Date | data_assegnazione | DateTime | |
| dataInvioAtto | Date | data_invio_atto | DateTime | |
| dataRitornoAtto | Date | data_ritorno_atto | DateTime | |
| dataChiusura | Date | closed_at | DateTime | |
| dataRevoca | Date | data_revoca | DateTime | |
| dataSopralluogo | Date | data_sopralluogo | DateTime | |
| richiesta | NSDecimalNumber | richiesta | Numeric(12,2) | |
| liquidato | NSDecimalNumber | liquidato | Numeric(12,2) | |
| dannoAccertato | NSDecimalNumber | danno_accertato | Numeric(12,2) | |
| dannoAccertatoNetto | NSDecimalNumber | danno_accertato_netto | Numeric(12,2) | |
| stimaDanno | NSDecimalNumber | stima_danno | Numeric(12,2) | |
| numeroPolizza | String | numero_polizza | String | |
| tipoPolizza | String | tipo_polizza | String | |
| divisioneCompagnia | String | divisione_compagnia | String | |
| iban | Bool | iban | Boolean | |
| sinistroCollegato | Bool | sinistro_collegato | Boolean | |
| idSinistroCollegato | String | id_sinistro_collegato | String | |
| sopralluogo | Bool | sopralluogo | Boolean | |
| giustificativi | Bool | giustificativi | Boolean | |
| foto | Bool | foto | Boolean | |
| oltreDieciBeni | Bool | oltre_dieci_beni | Boolean | |
| concordata | Bool | concordata | Boolean | |
| negativa | Bool | negativa | Boolean | |
| ubicazioneValidata | Bool | ubicazione_validata | Boolean | |
| ubicazioneNote | String | ubicazione_note | String | |
| fulminazione | String | fulminazione | String | |
| gruppo | String | gruppo | String | |
| area | String | area | String | |
| complessita | String | complessita | String | |
| definizione | String | definizione | String | |
| propensionePerito | String | propensione_perito | String | |
| cartella | String | cartella | String | Legacy, da rimuovere |
| ownerEmail | String | owner_email | String | Legacy assignment, usare claim_assignments |
| dataCreazione | Date | created_at | DateTime | Auto-generato |
| - | - | updated_at | DateTime | Auto-generato |
| - | - | version | Integer | Per optimistic locking |
| - | - | priority | Integer | Calcolata dinamicamente |
| - | - | tenant_id | String | Multi-tenant |
| - | - | id | String (UUID) | Primary key cloud |

## Relazioni CoreData → Postgres

### Sinistro → Perizia
- **CoreData**: `sinistro.perizia` (1:1)
- **Postgres**: Non mappato inizialmente (fase 1). In futuro: tabella `perizie` con FK a `claims.id`

### Sinistro → Coassicurazioni
- **CoreData**: `sinistro.coassicurazioni` (1:N)
- **Postgres**: Non mappato inizialmente. In futuro: tabella `coassicurazioni` con FK a `claims.id`

### Sinistro → Tags
- **CoreData**: `sinistro.tags` (N:M via `Tag`)
- **Postgres**: Non mappato inizialmente. In futuro: tabella `tags` e `claim_tags` (junction)

### Sinistro → EmailThreads
- **CoreData**: `sinistro.emailThreads` (1:N via `SinistroEmailThread`)
- **Postgres**: `email_claim_links` (N:M) collega `emails` a `claims`

### Sinistro → DiarioEntries
- **CoreData**: `sinistro.diarioEntries` (Transformable, array di `DiarioEntry`)
- **Postgres**: `claim_events` con `event_type="diario_entry"` e `data_json` contenente i dettagli

### Sinistro → Owner (Assignment)
- **CoreData**: `sinistro.ownerEmail` (String)
- **Postgres**: `claim_assignments` con `assignee_user_id` e storico completo

## Entità Non Migrate Inizialmente

Queste entità CoreData non sono migrate nella Fase 1-2, ma possono essere aggiunte in futuro:

1. **Perizia** + relazioni (Partite, Garanzie, Beni, VociCosto)
2. **Coassicurazione**
3. **Tag** (sistema di tagging)
4. **PerxiaAnalisi** + PerxiaBene (analisi IA)
5. **RelazioneTemplate**
6. **TriggerState** (monitoring/automazioni avanzate)

## Gap Identificati

1. **Stati personalizzati**: CoreData supporta stati custom (SP001, SP002, ecc.) via `StatoManager.customStates`. Postgres supporta qualsiasi stringa in `stato_corrente`, ma serve validazione lato backend.

2. **Diario entries**: In CoreData sono oggetti `DiarioEntry` serializzati. In Postgres diventano `claim_events` con tipo specifico.

3. **Collegamenti sinistri**: CoreData ha `collegamenti` (NSSet). Postgres può usare `id_sinistro_collegato` (1:1) o tabella junction per N:N.

4. **Email signature**: CoreData ha `emailSignature` (NSAttributedString). Postgres può usare `metadata_json` o campo Text.

5. **Task giornaliere**: CoreData ha `DailyTask` in UserDefaults. Postgres ha `case_tasks` persistenti e assegnabili.

## Strategia di Migrazione

1. **Fase 1**: Migrare solo `Sinistro` essenziale (campi principali, stati, date, finanziari)
2. **Fase 2**: Aggiungere `claim_assignments`, `claim_states`, `claim_events`
3. **Fase 3**: Migrare `emails` e `email_claim_links`
4. **Fase 4**: Aggiungere `case_tasks` e automazioni
5. **Fase 5**: Migrare entità complesse (Perizia, Coassicurazioni, Tags)

