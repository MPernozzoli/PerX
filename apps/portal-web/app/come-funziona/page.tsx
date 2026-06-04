import { PortalShell } from "@/components/portal-shell";

const PROCESS_STEPS = [
  {
    title: "Apertura pratica",
    description:
      "Registriamo il sinistro e raccogliamo i primi dati utili per impostare la gestione."
  },
  {
    title: "Documentazione",
    description:
      "Se servono foto o documenti, li puoi caricare direttamente dal portale con procedura guidata."
  },
  {
    title: "Analisi o sopralluogo",
    description:
      "Valutiamo la pratica e, se necessario, organizziamo il sopralluogo con le finestre disponibili."
  },
  {
    title: "Atto e coordinate bancarie",
    description:
      "Quando la pratica arriva a definizione, trovi atto, importi e puoi completare IBAN e firma."
  },
  {
    title: "Liquidazione",
    description:
      "Il portale resta disponibile fino alla chiusura, con stato aggiornato e storico documenti."
  }
];

export default function HowItWorksPage() {
  return (
    <PortalShell>
      <section className="overview-panel">
        <div className="overview-panel__hero">
          <span className="overview-pill">Guida rapida</span>
          <h1>Come funziona il portale assicurato</h1>
          <p>
            Qui trovi i passaggi principali della gestione sinistro e il significato delle azioni
            che ti possono essere richieste nel corso della pratica.
          </p>
        </div>

        <div className="process-grid">
          {PROCESS_STEPS.map((step, index) => (
            <article key={step.title} className="process-card">
              <span className="process-card__index">{index + 1}</span>
              <h2>{step.title}</h2>
              <p>{step.description}</p>
            </article>
          ))}
        </div>

        <div className="tips-panel">
          <h2>Consigli utili</h2>
          <ul className="plain-list">
            <li>
              <strong>Controlla spesso la panoramica.</strong>
              <span>Mostra sia le azioni richieste sia i sinistri senza attività pendenti.</span>
            </li>
            <li>
              <strong>Carica tutto in un solo passaggio quando possibile.</strong>
              <span>Riduce richieste integrative e velocizza la revisione.</span>
            </li>
            <li>
              <strong>Per il sopralluogo scegli più finestre.</strong>
              <span>Aumenta la probabilità di assegnazione rapida del CAT di zona.</span>
            </li>
          </ul>
        </div>
      </section>
    </PortalShell>
  );
}
