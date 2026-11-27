/**
 * Unica pratica inventata per lo storytelling della landing.
 * Tutti i numeri e i nomi devono coincidere tra le catture delle app.
 * Non usare dati da sinistri reali.
 */

const euro = new Intl.NumberFormat("it-IT", {
  style: "currency",
  currency: "EUR",
  maximumFractionDigits: 0,
});

export function formatEuro(value: number): string {
  return euro.format(value);
}

export const praticaDemo = {
  riferimento: "PX-2026-0847",
  garanzia: "Danni da acqua",
  descrizioneEvento:
    "Rottura di un tubo di alimentazione del lavabo in bagno. Acqua infiltrata nel parquet del corridoio e nella cucina adiacente.",
  dataEvento: "12 novembre 2026",
  dataIncarico: "14 novembre 2026",
  statoInterno: "In gestione",
  macrostatoAssicurato: "Sopralluogo in programma",
  compagnia: "NordAssicura S.p.A.",
  agenzia: "Agenzia di Padova Centro",
  polizza: {
    prodotto: "Casa Completa",
    numero: "NA-CASA-441902",
    edizione: "Ed. 01/2025",
    franchigiaEuro: 250,
    massimaleEuro: 50_000,
    sommaAssicurataContenutoEuro: 80_000,
  },
  assicurato: {
    nome: "Marco Bellini",
    indirizzo: "Via dei Colli 18",
    comune: "Padova",
    cap: "35121",
    provincia: "PD",
  },
  perito: {
    nome: "Elena Conti",
    ruolo: "Perito property",
  },
  cat: {
    nome: "Tecnici Veneto Est",
    tecnico: "Luca Ferretti",
    comunePresidio: "Padova",
  },
  importi: {
    richiestoEuro: 4_820,
    accertatoEuro: 3_950,
    liquidabileEuro: 3_700,
  },
  appuntamento: {
    data: "19 novembre 2026",
    fascia: "10:00 – 12:00",
    ordineNellaRoute: 2,
    fermateTotali: 4,
  },
} as const;

export type FrameKind = "mac" | "phone" | "browser";

export type StoryCapture = {
  id: string;
  /** Nome file previsto in src/assets/story/ (senza path) */
  filename: string;
  frame: FrameKind;
  /** App da cui catturare */
  app: string;
  /** Vista / schermata esatta */
  vista: string;
  /** Cosa deve leggersi nella cattura */
  deveLeggersi: string[];
  /** Inquadratura consigliata */
  inquadratura: string;
};

export type StoryChapter = {
  id: string;
  navLabel: string;
  title: string;
  actor: string;
  context: string;
  captures: StoryCapture[];
};

export const storyChapters: StoryChapter[] = [
  {
    id: "elenco",
    navLabel: "Elenco sinistri",
    title: "La pratica entra in elenco",
    actor: "Studio — app PerX",
    context: `${praticaDemo.riferimento} compare tra le pratiche aperte, con stato e attività da fare.`,
    captures: [
      {
        id: "elenco-sinistri",
        filename: "01-elenco-sinistri.png",
        frame: "mac",
        app: "PerX (macOS)",
        vista: "SinistriView — tab elenco",
        deveLeggersi: [
          praticaDemo.riferimento,
          praticaDemo.assicurato.nome,
          praticaDemo.statoInterno,
          praticaDemo.compagnia,
          "almeno un'attività aperta sulla riga",
        ],
        inquadratura:
          "Finestra intera dell'elenco, riga della pratica evidenziata al centro, senza menu di sistema né notifiche.",
      },
    ],
  },
  {
    id: "dettaglio",
    navLabel: "Dettaglio",
    title: "Chi c'è sulla pratica",
    actor: "Studio — app PerX",
    context: `Compagnia, polizza, assicurato e date: ${praticaDemo.assicurato.nome}, ${praticaDemo.assicurato.indirizzo}, ${praticaDemo.assicurato.comune}.`,
    captures: [
      {
        id: "dettaglio-sinistro",
        filename: "02-dettaglio-sinistro.png",
        frame: "mac",
        app: "PerX (macOS)",
        vista: "SinistroDetailContentView — tab Dettagli",
        deveLeggersi: [
          praticaDemo.compagnia,
          praticaDemo.agenzia,
          praticaDemo.polizza.numero,
          praticaDemo.assicurato.nome,
          praticaDemo.dataEvento,
          praticaDemo.dataIncarico,
          praticaDemo.statoInterno,
        ],
        inquadratura:
          "Area dettaglio a tutto il pannello, sezioni Compagnia, Stato, Polizza/Attori e Date leggibili senza scroll.",
      },
    ],
  },
  {
    id: "bignami",
    navLabel: "Bignami",
    title: "Le condizioni della polizza",
    actor: "Studio — Bignami Online",
    context: `Garanzia ${praticaDemo.garanzia}: franchigia ${formatEuro(praticaDemo.polizza.franchigiaEuro)}, massimale ${formatEuro(praticaDemo.polizza.massimaleEuro)}.`,
    captures: [
      {
        id: "bignami-polizza",
        filename: "03-bignami-polizza.png",
        frame: "browser",
        app: "Bignami Online",
        vista: "PolicyDetail — garanzia danni da acqua",
        deveLeggersi: [
          praticaDemo.polizza.prodotto,
          praticaDemo.polizza.edizione,
          praticaDemo.garanzia,
          `franchigia ${praticaDemo.polizza.franchigiaEuro}`,
          `massimale ${praticaDemo.polizza.massimaleEuro}`,
        ],
        inquadratura:
          "Browser a larghezza desktop, scheda polizza aperta sulla garanzia rilevante; sidebar ridotta se presente.",
      },
    ],
  },
  {
    id: "operazioni",
    navLabel: "Studio e Team",
    title: "Chi la lavora",
    actor: "Studio — monitor operativo",
    context: `${praticaDemo.perito.nome} ha la pratica in carico. Studio e Team mostrano il carico reale.`,
    captures: [
      {
        id: "monitor-studio",
        filename: "04-monitor-studio.png",
        frame: "mac",
        app: "PerX (macOS)",
        vista: "StudioMonitorView",
        deveLeggersi: [
          "KPI Perizie Attive",
          praticaDemo.compagnia,
          "conteggi coerenti con la demo",
        ],
        inquadratura: "Finestra monitor Studio a piena larghezza, riga compagnia visibile.",
      },
      {
        id: "monitor-team",
        filename: "05-monitor-team.png",
        frame: "mac",
        app: "PerX (macOS)",
        vista: "TeamMonitorView",
        deveLeggersi: [
          praticaDemo.perito.nome,
          "carico / obiettivo del perito",
        ],
        inquadratura: "Stessa finestra operativa, vista Team con la riga di Elena Conti.",
      },
    ],
  },
  {
    id: "dispatcher",
    navLabel: "CAT Dispatcher",
    title: "Il territorio",
    actor: "Studio — Cat Dispatcher",
    context: `Comune di ${praticaDemo.assicurato.comune}: il CAT individuato è ${praticaDemo.cat.nome}.`,
    captures: [
      {
        id: "cat-dispatcher-mappa",
        filename: "06-cat-dispatcher-mappa.png",
        frame: "browser",
        app: "Cat Dispatcher",
        vista: "Index — mappa territoriale",
        deveLeggersi: [
          praticaDemo.assicurato.comune,
          praticaDemo.cat.nome,
          "popup o evidenziazione del comune",
        ],
        inquadratura:
          "Mappa centrata su Padova, comune selezionato con popup CAT; niente toast di caricamento.",
      },
    ],
  },
  {
    id: "portale",
    navLabel: "Portale assicurato",
    title: "L'assicurato sceglie la finestra",
    actor: "Assicurato — portale",
    context: `Macrostato «${praticaDemo.macrostatoAssicurato}». ${praticaDemo.assicurato.nome} conferma la fascia ${praticaDemo.appuntamento.fascia} del ${praticaDemo.appuntamento.data}.`,
    captures: [
      {
        id: "portale-sopralluogo",
        filename: "07-portale-sopralluogo.png",
        frame: "browser",
        app: "Portale assicurati",
        vista: "Dashboard o schermata sopralluogo (quella più leggibile in cattura)",
        deveLeggersi: [
          praticaDemo.macrostatoAssicurato,
          praticaDemo.riferimento,
          praticaDemo.appuntamento.fascia,
          "nessun codice SVxxx",
        ],
        inquadratura:
          "Browser desktop, area claim senza chrome di login; preferire la scelta finestre se più chiara della sola dashboard.",
      },
    ],
  },
  {
    id: "lite",
    navLabel: "PerX Lite",
    title: "Il CAT in giornata",
    actor: `CAT — ${praticaDemo.cat.tecnico}`,
    context: `Route del ${praticaDemo.appuntamento.data}: fermata ${praticaDemo.appuntamento.ordineNellaRoute} di ${praticaDemo.appuntamento.fermateTotali}, ${praticaDemo.assicurato.indirizzo}.`,
    captures: [
      {
        id: "lite-route",
        filename: "08-lite-route-cat.png",
        frame: "phone",
        app: "PerX Lite (iPhone)",
        vista: "CATNavigatorView / CATRoutesView — fermata attiva",
        deveLeggersi: [
          praticaDemo.assicurato.indirizzo,
          praticaDemo.assicurato.comune,
          `fermata ${praticaDemo.appuntamento.ordineNellaRoute}`,
          praticaDemo.appuntamento.fascia,
        ],
        inquadratura:
          "Schermo intero iPhone, mappa in alto e card fermata attiva; status bar pulita, nessun banner chiamata.",
      },
    ],
  },
  {
    id: "stima",
    navLabel: "Stima",
    title: "Richiesto, accertato, liquidabile",
    actor: "Studio — elaborato calcoli",
    context: `Richiesto ${formatEuro(praticaDemo.importi.richiestoEuro)} → accertato ${formatEuro(praticaDemo.importi.accertatoEuro)} → liquidabile ${formatEuro(praticaDemo.importi.liquidabileEuro)} (franchigia ${formatEuro(praticaDemo.polizza.franchigiaEuro)} dal bignami).`,
    captures: [
      {
        id: "elaborato-calcoli",
        filename: "09-elaborato-calcoli.png",
        frame: "mac",
        app: "PerX (macOS)",
        vista: "PeriziaView → tab Elaborato Calcoli",
        deveLeggersi: [
          `richiesto ${praticaDemo.importi.richiestoEuro}`,
          `accertato ${praticaDemo.importi.accertatoEuro}`,
          `liquidabile ${praticaDemo.importi.liquidabileEuro}`,
          `franchigia ${praticaDemo.polizza.franchigiaEuro}`,
        ],
        inquadratura:
          "Tab Elaborato Calcoli attiva, KPI o riepilogo importi a vista; tab bar Perizia visibile in alto.",
      },
    ],
  },
];

export const captureBriefs = storyChapters.flatMap((chapter) =>
  chapter.captures.map((capture) => ({
    chapterId: chapter.id,
    ...capture,
  })),
);
