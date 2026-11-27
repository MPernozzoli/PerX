import { Link } from "react-router-dom";
import { praticaDemo } from "@/content/pratica-demo";

export const StoryHero = () => {
  return (
    <header className="border-b border-perx-line pb-12 pt-12 md:pb-16 md:pt-16">
      <p className="mb-3 font-display text-xs font-semibold tracking-[0.18em] text-perx-coral uppercase">
        Come funziona
      </p>

      <h1 className="max-w-3xl font-display text-3xl font-semibold tracking-tight text-perx-ink md:text-5xl md:leading-[1.08]">
        Una pratica, dall&apos;incarico alla stima.
      </h1>

      <p className="mt-5 max-w-2xl text-lg leading-relaxed text-perx-steel">
        Seguiamo {praticaDemo.riferimento}: {praticaDemo.garanzia.toLowerCase()} a{" "}
        {praticaDemo.assicurato.comune}. Dati inventati, schermate delle app
        reali.
      </p>

      <dl className="mt-8 grid max-w-3xl grid-cols-2 gap-x-8 gap-y-5 border-y border-perx-line py-6 text-sm sm:grid-cols-4">
        <div>
          <dt className="text-perx-steel">Riferimento</dt>
          <dd className="mt-1 font-mono text-[0.95rem] text-perx-ink">
            {praticaDemo.riferimento}
          </dd>
        </div>
        <div>
          <dt className="text-perx-steel">Garanzia</dt>
          <dd className="mt-1 text-perx-ink">{praticaDemo.garanzia}</dd>
        </div>
        <div>
          <dt className="text-perx-steel">Assicurato</dt>
          <dd className="mt-1 text-perx-ink">{praticaDemo.assicurato.nome}</dd>
        </div>
        <div>
          <dt className="text-perx-steel">Comune</dt>
          <dd className="mt-1 text-perx-ink">
            {praticaDemo.assicurato.comune} ({praticaDemo.assicurato.provincia})
          </dd>
        </div>
      </dl>

      <div className="mt-8 flex flex-wrap items-center gap-5 text-sm">
        <a
          href="#elenco"
          className="font-display font-semibold text-perx-coral underline-offset-4 hover:underline"
        >
          Parti dall&apos;elenco
        </a>
        <Link to="/" className="text-perx-steel hover:text-perx-ink">
          Torna alla home
        </Link>
      </div>
    </header>
  );
};
