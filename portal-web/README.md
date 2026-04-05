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

## Variabili ambiente

- `NEXT_PUBLIC_PORTAL_API_BASE_URL`: base URL del backend portal
- `NEXT_PUBLIC_PORTAL_USE_MOCKS`: se `true`, usa dati demo e consente di navigare il portale anche senza backend attivo

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
