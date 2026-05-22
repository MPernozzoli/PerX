# PerX Unified Login

## Obiettivo

Creare un identity layer unico su `login.perx.it` per accedere con la stessa identita a:

- app PerX
- portale admin PerX
- CatDispatcher
- altri servizi interni futuri

Il login deve supportare il flusso operativo previsto per gli utenti interni:

1. invito iniziale inviato alla mail personale;
2. primo accesso e creazione credenziali sull'identita centrale;
3. provisioning/abilitazione della mail interna PerX;
4. accesso successivo a tutte le app tramite SSO, ruoli e permessi centralizzati.

## Stato attuale del repo

Il backend ha gia una base compatibile:

- `POST /api/v1/auth/login`
- `GET /api/v1/auth/me`
- tabella `users` con `email`, `personal_email`, `professional_email`, `idp_subject`, `tenant_id`, `is_platform_admin`
- ruoli applicativi tramite `roles`/`user_roles`
- supporto opzionale a Supabase Auth tramite `FF_CLOUD_AUTH_ENABLED`

CatDispatcher e il pannello admin usano ancora form email/password locali che chiamano direttamente `/auth/login`. Questo va bene come ponte, ma non e ancora SSO: ogni app gestisce token e login screen in modo proprio.

## Architettura target

### Componenti

- `login.perx.it`: identity portal centrale.
- PerX API: resource server e authority applicativa per tenant, ruoli, profili e mail interne.
- Provider auth: Supabase Auth o un IdP OIDC equivalente.
- Client app: `app.perx.it`, `admin.perx.it`, `catdispatcher.perx.it`, app nativa PerX.

### Protocollo

Usare OAuth 2.1 / OpenID Connect con Authorization Code + PKCE.

Ogni client deve avere:

- `client_id`
- redirect URI esplicite
- post logout redirect URI
- lista scope consentiti

Scope minimi:

- `openid`
- `profile`
- `email`
- `perx:app`
- `perx:admin`
- `perx:catdispatcher`

Claim applicativi nel token o risolti via `/auth/me`:

- `sub`
- `email`
- `personal_email`
- `professional_email`
- `tenant_id`
- `roles`
- `is_platform_admin`
- `email_verified`
- `professional_email_enabled`

## Flusso invito mail personale

1. Admin crea un utente PerX con `personal_email`, nome, tenant e ruoli iniziali.
2. Backend genera un invito monouso con scadenza e lo invia alla mail personale.
3. L'utente apre il link su `login.perx.it/invite/{token}`.
4. L'identity portal valida il token e crea/collega l'account nel provider auth.
5. L'utente imposta password o attiva magic link/passkey, a seconda della policy scelta.
6. Backend salva `idp_subject` su `users.idp_subject`.
7. Il primo login restituisce sessione SSO e profilo PerX.

Regola importante: la mail personale resta l'identita di bootstrap e recupero account. Non deve diventare automaticamente la mail operativa.

## Flusso abilitazione mail interna

1. Dopo il primo accesso, il backend calcola o riceve `professional_email`, per esempio `nome.cognome@perx.it`.
2. `ensure_professional_email` abilita l'indirizzo interno solo quando l'utente ha ruolo/contratto compatibile.
3. Il backend registra `professional_email` e alias in `email_aliases`.
4. Le app mostrano la mail interna come identita operativa, ma il login continua ad accettare la mail personale finche l'account non e completamente migrato.

Policy consigliata:

- login consentito con `personal_email` e `professional_email`;
- notifiche di sicurezza e recupero su `personal_email`;
- comunicazioni operative da/per `professional_email`;
- claim/assegnazioni interne devono usare `professional_email` quando presente.

## Flussi SSO per app web

### Accesso a CatDispatcher

1. Utente apre `catdispatcher.perx.it`.
2. Se non c'e sessione locale, redirect a:
   `https://login.perx.it/oauth/authorize?client_id=catdispatcher&redirect_uri=...&response_type=code&scope=openid profile email perx:catdispatcher&code_challenge=...`
3. Dopo login, `login.perx.it` torna a `/auth/callback`.
4. CatDispatcher scambia `code` per token.
5. CatDispatcher chiama `/api/v1/auth/me`.
6. Accesso consentito solo se `is_platform_admin` oppure ruolo in `admin`, `site_admin`, `cat_dispatcher`, `perito`.

### Accesso admin

Stesso flusso, ma scope `perx:admin` e autorizzazione server-side basata su `is_platform_admin` o ruolo admin tenant.

### Accesso app nativa

Usare browser di sistema con PKCE:

- iOS/macOS: `ASWebAuthenticationSession`
- redirect custom scheme o universal link
- token salvati in Keychain
- refresh token ruotato e revocabile

## Endpoint da introdurre

Nel backend PerX:

- `POST /api/v1/invitations`
  - crea invito utente, riservato admin;
  - payload: `personal_email`, `full_name`, `tenant_id`, `roles`, `expires_at`.
- `GET /api/v1/invitations/{token}`
  - valida invito e restituisce dati minimi per la pagina di setup.
- `POST /api/v1/invitations/{token}/accept`
  - collega `idp_subject`, marca invito accettato, abilita utente.
- `POST /api/v1/auth/refresh`
  - refresh token per client legacy.
- `POST /api/v1/auth/logout`
  - revoca sessione lato IdP, se supportato.
- `GET /api/v1/auth/authorize-context`
  - restituisce app, tenant e ruoli per il client corrente.

Nel portale `login.perx.it`:

- `/login`
- `/invite/[token]`
- `/oauth/authorize`
- `/oauth/callback`
- `/logout`
- `/account/security`

## Modello dati aggiuntivo

Tabella `user_invitations`:

- `id`
- `tenant_id`
- `user_id`
- `personal_email`
- `token_hash`
- `status`: `pending`, `accepted`, `expired`, `revoked`
- `expires_at`
- `accepted_at`
- `created_by_user_id`
- `metadata_json`
- `created_at`
- `updated_at`

Estensioni consigliate a `users`:

- `email_verified_at`
- `professional_email_enabled_at`
- `last_auth_provider`
- `auth_locked_until`

## Piano di migrazione

### Fase 1 - consolidamento backend

- mantenere `/auth/login` per compatibilita;
- aggiungere inviti e accettazione inviti;
- collegare sempre gli utenti tramite `idp_subject`;
- accettare login via `personal_email`, `professional_email` e `email`.

### Fase 2 - login portal

- creare `login.perx.it` come app dedicata;
- implementare schermata invito;
- configurare provider auth e redirect URI per ogni client.

### Fase 3 - migrazione client web

- sostituire form locali in CatDispatcher/admin con redirect SSO;
- spostare token da localStorage a cookie/sessione ove possibile;
- mantenere fallback dev su `/auth/login` solo in ambiente locale.

### Fase 4 - app nativa

- introdurre `ASWebAuthenticationSession`;
- salvare access/refresh token in Keychain;
- usare `/auth/me` come sorgente unica del profilo utente.

### Fase 5 - hardening

- refresh token rotation;
- revoca sessioni;
- audit log su inviti, login, cambio mail interna, cambio ruoli;
- rate limit su inviti e login;
- MFA per admin e ruoli sensibili.

## Decisioni aperte

- Provider definitivo: Supabase Auth, Auth0/Okta, Cognito o IdP custom.
- Metodo primo accesso: password, magic link, OTP, passkey.
- Dominio mail interna: `@perx.it` o dominio tenant-specific.
- Se `login.perx.it` deve essere solo una UI sopra Supabase Auth o anche un authorization server custom.
- Dove ospitare le sessioni web: cookie HttpOnly centralizzati o token per-app.

## Raccomandazione pratica

Per partire velocemente, usare Supabase Auth come IdP e PerX API come authority applicativa.

Il backend PerX resta responsabile di:

- inviti;
- tenant;
- ruoli;
- mail personale/interna;
- autorizzazione alle app.

Supabase resta responsabile di:

- password/magic link;
- verifica email;
- refresh token;
- reset password;
- MFA quando verra attivata.

Questo evita di costruire un sistema password custom e mantiene una via chiara verso SSO completo.
