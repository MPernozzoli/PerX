import { Link } from "react-router-dom";

const CookiePolicy = () => {
  return (
    <div className="min-h-screen bg-background">
      <div className="container mx-auto max-w-3xl py-10 px-4">
        <Link to="/" className="text-sm text-muted-foreground hover:text-foreground mb-6 inline-block">
          ← Torna alla mappa
        </Link>
        <h1 className="text-2xl font-semibold mb-8">Cookie Policy</h1>

        <article className="prose prose-sm dark:prose-invert max-w-none space-y-6 text-muted-foreground">
          <section>
            <h2 className="text-lg font-medium text-foreground">Utilizzo dei cookie</h2>
            <p>CatDispatcher utilizza solo cookie tecnici di sessione, indispensabili per:</p>
            <ul className="list-disc pl-6 space-y-1 mt-2">
              <li>la gestione dell'autenticazione;</li>
              <li>il corretto funzionamento delle funzionalità riservate.</li>
            </ul>
            <p className="mt-4">Non vengono utilizzati:</p>
            <ul className="list-disc pl-6 space-y-1 mt-2">
              <li>cookie di profilazione;</li>
              <li>cookie analitici;</li>
              <li>strumenti di tracciamento di terze parti.</li>
            </ul>
            <p className="mt-4">Per tali motivi non è richiesto il consenso dell'utente, ai sensi della normativa vigente.</p>
          </section>
        </article>
      </div>
    </div>
  );
};

export default CookiePolicy;
