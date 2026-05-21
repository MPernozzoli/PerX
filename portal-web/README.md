# PerX Assicurati Web Portal

Web app dedicata agli assicurati per consultare e gestire il proprio sinistro.

## Stack

- Next.js App Router
- TypeScript
- Integrazione con il backend FastAPI tramite `/api/v1/portal`

## Setup rapido

```bash
cd portal-web
cp .env.example .env.local
npm install
npm run dev
```

Di default l'app parte su `http://localhost:3001`.

In produzione il portale e pensato per essere servito da `assicurati.[dominio_tenant]`.
La logica applicativa resta condivisa; la personalizzazione tenant passa da CSS dedicato in
`public/tenant-themes/{themeId}.css`, dove `themeId` e derivato dal primo label del dominio tenant
(`assicurati.demo.it` carica `demo.css`).

## Variabili ambiente

- `NEXT_PUBLIC_PORTAL_API_BASE_URL`: base URL del backend portal
- `NEXT_PUBLIC_PORTAL_USE_MOCKS`: se `true`, usa dati demo e consente di navigare il portale anche senza backend attivo

## Configurazione tenant

Nel backend configura i domini portale del tenant tramite `portal_domains` nelle impostazioni tenant.
Inserire il dominio tenant senza sottodominio, per esempio `demo.it`; il portale pubblico rispondera
su `assicurati.demo.it`. Il backend usa l'host inviato dal front-end per limitare autenticazione,
magic link e sessioni al tenant configurato.

## Flussi già predisposti

- Richiesta accesso con riferimento sinistro / codice fiscale / fallback anagrafico
- Landing magic link `/access/[token]`
- Dashboard claim `/claim`
- Timeline pratica
- Contatto perito
- Upload intent documenti
- Invio documentale guidata
- Salvataggio IBAN con validazione base
- Chat assicurato -> instradamento backend
- Firma atto con challenge di conferma

## Stato

Questa app rappresenta l'architettura iniziale del portale. I canali outbound reali (e-mail automatica, SMS OTP, upload firmati storage) sono ancora da collegare.
