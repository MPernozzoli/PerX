import { Link } from "react-router-dom";
import { SiteHeader } from "@/components/SiteHeader";
import { ContactSection } from "@/components/ContactSection";
import { Footer } from "@/components/Footer";

const Index = () => {
  return (
    <div className="min-h-screen bg-perx-paper text-perx-ink">
      <section className="relative min-h-[100svh] overflow-hidden bg-hero-grain text-white">
        <SiteHeader tone="ink" />

        <div className="relative mx-auto flex min-h-[calc(100svh-5.5rem)] max-w-6xl flex-col justify-end px-6 pb-16 pt-10 md:px-10 md:pb-20 md:pt-16">
          <p className="mb-6 max-w-md font-display text-sm font-medium tracking-[0.18em] text-white/55 uppercase">
            Piattaforma operativa per studi peritali
          </p>

          <h1 className="font-display text-[clamp(3.25rem,12vw,7.5rem)] font-semibold leading-[0.92] tracking-[-0.04em]">
            PerX
          </h1>

          <p className="mt-6 max-w-xl font-display text-2xl font-medium leading-snug tracking-tight text-white/90 md:text-3xl">
            Il lavoro peritale, in un solo posto.
          </p>

          <p className="mt-4 max-w-lg text-base leading-relaxed text-white/60 md:text-lg">
            Sinistri, documenti, CAT, assicurato e condizioni di polizza collegati
            alla stessa pratica — senza rincorse tra strumenti.
          </p>

          <div className="mt-10 flex flex-wrap items-center gap-4">
            <Link
              to="/come-funziona"
              className="inline-flex items-center rounded-md bg-[var(--coral)] px-5 py-3 text-sm font-semibold text-white transition hover:bg-[var(--coral-deep)]"
            >
              Come funziona
            </Link>
            <a
              href="#contatto"
              className="inline-flex items-center rounded-md border border-white/25 px-5 py-3 text-sm font-semibold text-white transition hover:border-white/50 hover:bg-white/5"
            >
              Scrivici
            </a>
          </div>
        </div>
      </section>

      <section className="border-y border-perx-line bg-perx-chalk">
        <div className="mx-auto grid max-w-6xl gap-0 px-6 md:grid-cols-4 md:px-10">
          {[
            {
              title: "Studio",
              text: "Elenco, dettaglio, stima e monitoraggio del carico.",
            },
            {
              title: "Assicurato",
              text: "Portale per documenti, sopralluogo e aggiornamenti.",
            },
            {
              title: "CAT",
              text: "Dispatch sul territorio e app Lite in giornata.",
            },
            {
              title: "Polizze",
              text: "Bignami online: franchigie e massimali a portata.",
            },
          ].map((item, index) => (
            <div
              key={item.title}
              className={`border-perx-line py-10 md:border-r md:px-6 md:first:pl-0 md:last:border-r-0 md:last:pr-0 ${
                index > 0 ? "border-t md:border-t-0" : ""
              }`}
            >
              <p className="font-display text-xs font-semibold tracking-[0.16em] text-perx-coral uppercase">
                {String(index + 1).padStart(2, "0")}
              </p>
              <h2 className="mt-3 font-display text-xl font-semibold tracking-tight">
                {item.title}
              </h2>
              <p className="mt-2 text-sm leading-relaxed text-perx-steel">{item.text}</p>
            </div>
          ))}
        </div>
      </section>

      <section className="mx-auto max-w-6xl px-6 py-20 md:px-10 md:py-28">
        <div className="max-w-2xl">
          <h2 className="font-display text-3xl font-semibold tracking-tight md:text-4xl">
            Una pratica, tutte le fasi.
          </h2>
          <p className="mt-4 text-lg leading-relaxed text-perx-steel">
            Seguiamo un sinistro inventato dall&apos;incarico alla stima: le
            schermate vere dello studio, del portale, del dispatcher e di PerX
            Lite.
          </p>
          <Link
            to="/come-funziona"
            className="mt-8 inline-flex font-display text-sm font-semibold text-perx-coral underline-offset-4 hover:underline"
          >
            Apri il percorso →
          </Link>
        </div>
      </section>

      <ContactSection />
      <Footer />
    </div>
  );
};

export default Index;
