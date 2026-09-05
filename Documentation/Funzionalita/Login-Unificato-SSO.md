---
tags: [perx, funzionalita, auth, sso, pianificato]
updated: 2026-09-05
---

# Login unificato / SSO

> **Stato: pianificato, non implementato.** Questa nota descrive un piano di migrazione discusso
> e documentato, non funzionalità già disponibile. Vedi [[05-Stato-Sviluppo-e-Roadmap]] per lo
> stato reale corrente.

## Obiettivo

Creare un identity layer unico su **`login.perx.it`** per accedere con la stessa identità a: app
PerX, portale admin PerX, [[CatDispatcher]] e altri servizi interni futuri.

Flusso operativo previsto per gli utenti interni:
1. Invito iniziale inviato alla mail personale.
2. Primo accesso e creazione credenziali sull'identità centrale.
3. Provisioning/abilitazione della mail interna PerX.
4. Accesso successivo a tutte le app tramite SSO, ruoli e permessi centralizzati.

## Stato attuale del backend (base già esistente)

- `POST /api/v1/auth/login`, `GET /api/v1/auth/me`.
- Tabella `users` con `email`, `personal_email`, `professional_email`, `idp_subject`,
  `tenant_id`, `is_platform_admin`.
- Ruoli applicativi via `roles`/`user_roles`.
- Supporto opzionale a Supabase Auth tramite `FF_CLOUD_AUTH_ENABLED`.
- CatDispatcher e pannello admin usano ancora **form email/password locali** che chiamano
  direttamente `/auth/login`: funziona come ponte, ma non è ancora SSO — ogni app gestisce token e
  login screen per conto proprio.

## Architettura target

- **`login.perx.it`**: identity portal centrale.
- **PerX API**: resource server e authority applicativa per tenant, ruoli, profili, mail interne.
- **Provider auth**: Supabase Auth o un IdP OIDC equivalente (raccomandazione: Supabase Auth).
- **Client**: `app.perx.it`, `admin.perx.it`, `catdispatcher.perx.it`, app nativa PerX.
- Protocollo: **OAuth 2.1 / OpenID Connect**, Authorization Code + PKCE. Ogni client ha
  `client_id`, redirect URI esplicite, post-logout redirect URI, scope consentiti (minimi:
  `openid`, `profile`, `email`, `perx:app`, `perx:admin`, `perx:catdispatcher`).
- Claim applicativi: `sub`, `email`, `personal_email`, `professional_email`, `tenant_id`, `roles`,
  `is_platform_admin`, `email_verified`, `professional_email_enabled`.

## Flusso invito mail personale

1. Admin crea utente con `personal_email`, nome, tenant, ruoli iniziali.
2. Backend genera invito monouso con scadenza, inviato alla mail personale.
3. Utente apre `login.perx.it/invite/{token}`.
4. L'identity portal valida il token e crea/collega l'account nel provider auth.
5. L'utente imposta password o attiva magic link/passkey.
6. Backend salva `idp_subject` su `users.idp_subject`.
7. Primo login → sessione SSO + profilo PerX.

Regola: la mail personale resta identità di bootstrap/recupero, non diventa automaticamente la
mail operativa.

## Flusso abilitazione mail interna

1. Dopo il primo accesso, il backend calcola/riceve `professional_email` (es.
   `nome.cognome@perx.it`).
2. `ensure_professional_email` abilita l'indirizzo interno solo con ruolo/contratto compatibile.
3. Il backend registra `professional_email` e alias in `email_aliases`.
4. Le app mostrano la mail interna come identità operativa; il login accetta anche la personale
   finché l'account non è completamente migrato.

Policy consigliata: login con entrambe le mail; notifiche sicurezza/recupero su personale;
comunicazioni operative su professionale; claim/assegnazioni interne devono usare la
professionale quando presente.

## Flussi SSO per app web (target)

- **CatDispatcher**: redirect a `login.perx.it/oauth/authorize?client_id=catdispatcher&...` →
  callback → scambio `code` per token → `GET /api/v1/auth/me` → accesso consentito solo se
  `is_platform_admin` o ruolo in `admin`, `site_admin`, `cat_dispatcher`, `perito`.
- **Admin**: stesso flusso, scope `perx:admin`, autorizzazione su `is_platform_admin`/ruolo admin
  tenant.
- **App nativa**: `ASWebAuthenticationSession` (iOS/macOS), redirect custom scheme o universal
  link, token in Keychain, refresh token ruotato e revocabile.

## Endpoint da introdurre (backend)

`POST /api/v1/invitations`, `GET /api/v1/invitations/{token}`,
`POST /api/v1/invitations/{token}/accept`, `POST /api/v1/auth/refresh`,
`POST /api/v1/auth/logout`, `GET /api/v1/auth/authorize-context`.

## Endpoint da introdurre (`login.perx.it`)

`/login`, `/invite/[token]`, `/oauth/authorize`, `/oauth/callback`, `/logout`,
`/account/security`.

## Modello dati aggiuntivo

Tabella `user_invitations`: `id`, `tenant_id`, `user_id`, `personal_email`, `token_hash`,
`status` (`pending`/`accepted`/`expired`/`revoked`), `expires_at`, `accepted_at`,
`created_by_user_id`, `metadata_json`, `created_at`, `updated_at`.

Estensioni consigliate a `users`: `email_verified_at`, `professional_email_enabled_at`,
`last_auth_provider`, `auth_locked_until`.

## Piano di migrazione (5 fasi, nessuna avviata in modo strutturato)

1. **Consolidamento backend**: mantenere `/auth/login` per compatibilità; aggiungere inviti e
   accettazione; collegare sempre gli utenti via `idp_subject`; accettare login via
   `personal_email`, `professional_email`, `email`.
2. **Login portal**: creare `login.perx.it`; schermata invito; provider auth e redirect URI per
   client.
3. **Migrazione client web**: sostituire form locali in CatDispatcher/admin con redirect SSO;
   spostare token da localStorage a cookie/sessione dove possibile; fallback dev su `/auth/login`
   solo in locale.
4. **App nativa**: `ASWebAuthenticationSession`; token in Keychain; `/auth/me` come sorgente unica
   del profilo.
5. **Hardening**: refresh token rotation; revoca sessioni; audit log su inviti/login/cambio
   mail/ruoli; rate limit su inviti e login; MFA per admin e ruoli sensibili.

## Decisioni ancora aperte

- Provider definitivo (Supabase Auth vs Auth0/Okta/Cognito vs IdP custom).
- Metodo primo accesso (password, magic link, OTP, passkey).
- Dominio mail interna (`@perx.it` o tenant-specific).
- Se `login.perx.it` è solo UI sopra Supabase Auth o anche authorization server custom.
- Dove ospitare le sessioni web (cookie HttpOnly centralizzati o token per-app).

## Raccomandazione pratica

Supabase Auth come IdP, PerX API come authority applicativa. Il backend PerX resta responsabile di
inviti, tenant, ruoli, mail personale/interna, autorizzazione alle app. Supabase resta
responsabile di password/magic link, verifica email, refresh token, reset password, MFA quando
verrà attivata. Evita di costruire un sistema password custom e mantiene una via chiara verso SSO
completo.

---
Ultimo aggiornamento: 2026-09-05
