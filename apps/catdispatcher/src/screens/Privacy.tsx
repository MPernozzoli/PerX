import { Link } from "react-router-dom";

const Privacy = () => {
  return (
    <div className="min-h-screen bg-background">
      <div className="container mx-auto max-w-3xl py-10 px-4">
        <Link to="/" className="text-sm text-muted-foreground hover:text-foreground mb-6 inline-block">
          ← Torna alla mappa
        </Link>
        <h1 className="text-2xl font-semibold mb-2">Privacy Policy</h1>
        <p className="text-sm text-muted-foreground mb-8">Ultimo aggiornamento: 02/02/2026</p>

        <article className="prose prose-sm dark:prose-invert max-w-none space-y-6 text-muted-foreground">
          <section>
            <h2 className="text-lg font-medium text-foreground">1. Titolare del trattamento</h2>
            <p>Il titolare del trattamento è ACT s.r.l., con sede in via Rogoredo 21/B, 20138 Milano, contattabile all'indirizzo email info@actsrl.it.</p>
          </section>

          <section>
            <h2 className="text-lg font-medium text-foreground">2. Ambito di applicazione</h2>
            <p>La presente informativa riguarda l'utilizzo della piattaforma CatDispatcher, applicativo ad accesso riservato destinato esclusivamente ai dipendenti e collaboratori autorizzati dello studio.</p>
          </section>

          <section>
            <h2 className="text-lg font-medium text-foreground">3. Tipologie di dati trattati</h2>
            <p>Il sistema tratta esclusivamente dati personali minimi, limitati a quanto necessario per il corretto funzionamento del servizio:</p>
            <h3 className="text-base font-medium text-foreground mt-4">3.1 Dati di autenticazione e profilo</h3>
            <ul className="list-disc pl-6 space-y-1 mt-2">
              <li>indirizzo email aziendale;</li>
              <li>ruolo assegnato all'utente (utente / amministratore).</li>
            </ul>
            <p className="mt-2">L'autenticazione avviene tramite Google Workspace; CatDispatcher non gestisce né conserva password.</p>
            <h3 className="text-base font-medium text-foreground mt-4">3.2 Dati organizzativi</h3>
            <ul className="list-disc pl-6 space-y-1 mt-2">
              <li>elenco dei tecnici/collaboratori;</li>
              <li>associazione tra tecnico e comuni di competenza operativa.</li>
            </ul>
            <p className="mt-2">Tali informazioni sono utilizzate esclusivamente per finalità organizzative interne.</p>
            <h3 className="text-base font-medium text-foreground mt-4">3.3 Dati trattati temporaneamente tramite estensione browser o barra di ricerca</h3>
            <p className="mt-2">L'estensione Chrome associata a CatDispatcher:</p>
            <ul className="list-disc pl-6 space-y-1 mt-2">
              <li>legge l'indirizzo del sinistro visualizzato nel gestionale dello studio;</li>
              <li>converte l'indirizzo in coordinate geografiche;</li>
              <li>identifica il tecnico (CAT) territorialmente competente.</li>
            </ul>
            <p className="mt-2">Il portale WEB:</p>
            <ul className="list-disc pl-6 space-y-1 mt-2">
              <li>consente all'utente di inserire un indirizzo o parte di esso;</li>
              <li>converte l'indirizzo in coordinate geografiche;</li>
              <li>identifica il tecnico (CAT) territorialmente competente.</li>
            </ul>
            <p className="mt-2">Gli indirizzi non vengono memorizzati, né associati ad alcun identificativo di sinistro o persona. Il dato viene trattato esclusivamente in modalità transitoria (in-memory) e cancellato al termine della singola elaborazione.</p>
          </section>

          <section>
            <h2 className="text-lg font-medium text-foreground">4. Finalità del trattamento</h2>
            <p>I dati sono trattati esclusivamente per:</p>
            <ul className="list-disc pl-6 space-y-1 mt-2">
              <li>consentire l'accesso autenticato alla piattaforma;</li>
              <li>gestire i ruoli utente;</li>
              <li>assegnare correttamente la competenza territoriale ai tecnici;</li>
              <li>supportare le attività operative interne dello studio.</li>
            </ul>
            <p className="mt-2">Non vengono svolte attività di: profilazione; marketing; tracciamento comportamentale; analisi statistiche di terze parti.</p>
          </section>

          <section>
            <h2 className="text-lg font-medium text-foreground">5. Base giuridica del trattamento</h2>
            <p>Il trattamento è effettuato ai sensi dell'art. 6, par. 1, lett. b) e f) del GDPR, in quanto: necessario all'esecuzione del rapporto di lavoro o collaborazione; fondato sul legittimo interesse del titolare a organizzare le attività operative interne.</p>
          </section>

          <section>
            <h2 className="text-lg font-medium text-foreground">6. Modalità del trattamento</h2>
            <p>Il trattamento avviene mediante strumenti informatici, con misure tecniche e organizzative adeguate a garantire la sicurezza, l'integrità e la riservatezza dei dati.</p>
          </section>

          <section>
            <h2 className="text-lg font-medium text-foreground">7. Conservazione dei dati</h2>
            <ul className="list-disc pl-6 space-y-1 mt-2">
              <li>I dati di account e ruolo sono conservati per la durata del rapporto di lavoro o collaborazione;</li>
              <li>I dati relativi agli indirizzi dei sinistri non vengono conservati.</li>
            </ul>
          </section>

          <section>
            <h2 className="text-lg font-medium text-foreground">8. Destinatari dei dati</h2>
            <p>I dati possono essere trattati da: personale autorizzato dello studio; fornitori tecnologici coinvolti nell'erogazione del servizio, nominati ove necessario quali responsabili del trattamento. I dati non vengono diffusi né ceduti a terzi per finalità commerciali.</p>
          </section>

          <section>
            <h2 className="text-lg font-medium text-foreground">9. Diritti dell'interessato</h2>
            <p>Gli interessati possono esercitare i diritti previsti dagli artt. 15–22 del GDPR (accesso, rettifica, cancellazione, limitazione, opposizione) contattando il titolare ai recapiti indicati.</p>
          </section>

          <section>
            <h2 className="text-lg font-medium text-foreground">10. Cookie</h2>
            <p>La piattaforma utilizza esclusivamente cookie tecnici, necessari al funzionamento del sistema e alla gestione delle sessioni di autenticazione. Non vengono utilizzati cookie di profilazione o di terze parti.</p>
          </section>
        </article>
      </div>
    </div>
  );
};

export default Privacy;
