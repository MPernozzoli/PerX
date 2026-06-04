import { useState, type ReactNode } from "react";

const services = [
  {
    icon: "bolt",
    title: "Fenomeno Elettrico",
    text: "Gestione specialistica dei danni da sovratensione, cortocircuito e alterazioni della rete.",
  },
  {
    icon: "property",
    title: "Property",
    text: "Accertamenti su fabbricati, contenuto, impianti e beni strumentali.",
  },
  {
    icon: "document",
    title: "Gestione documentale",
    text: "Acquisizione, verifica e organizzazione della documentazione di sinistro.",
  },
  {
    icon: "calculator",
    title: "Supporto liquidativo",
    text: "Analisi tecnica e supporto alla definizione puntuale del danno.",
  },
  {
    icon: "pin",
    title: "Coordinamento sopralluoghi",
    text: "Pianificazione delle attività sul territorio e gestione tempestiva degli accessi.",
  },
  {
    icon: "chart",
    title: "Reporting tecnico",
    text: "Relazioni chiare, complete e orientate alle decisioni.",
  },
  {
    icon: "laptop",
    title: "Gestione digitale del sinistro",
    text: "Processi ordinati, tracciabili e sempre accessibili.",
  },
];

const approach = [
  ["clock", "Tempi certi", "Processi strutturati per garantire rapidità di presa in carico e risposta."],
  ["message", "Comunicazione chiara", "Aggiornamenti puntuali con tutti gli attori coinvolti."],
  ["search-doc", "Tracciabilità completa", "Ogni attività è documentata lungo tutto il processo."],
  ["folder", "Gestione documentale", "Raccolta, controllo e archiviazione centralizzata."],
  ["team", "Coordinamento efficiente", "Attività peritali organizzate per priorità e territorio."],
  ["shield", "Qualità tecnica", "Competenza verticale e controlli puntuali sulle pratiche."],
];

const workflow = [
  ["inbox", "01", "Presa in carico", "e analisi iniziale"],
  ["calendar", "02", "Pianificazione", "e sopralluoghi"],
  ["search", "03", "Analisi tecnica", "e valutazione"],
  ["document", "04", "Relazione tecnica", "e proposta"],
  ["check", "05", "Chiusura", "e follow-up"],
];

const commitments = [
  ["clock", "Rapidità di presa in carico", "Attivazione tempestiva e gestione ordinata delle priorità."],
  ["search-doc", "Tracciabilità completa", "Ogni attività è verificabile in ogni momento."],
  ["database", "Gestione centralizzata", "Dati e documenti in un unico ambiente operativo."],
  ["bell", "Aggiornamenti continui", "Informazioni puntuali su avanzamento e scadenze."],
  ["sliders", "Workflow standardizzati", "Processi condivisi e controlli di qualità in ogni fase."],
];

function Icon({ name, className = "" }: { name: string; className?: string }) {
  const common = {
    className: `h-6 w-6 ${className}`,
    fill: "none",
    viewBox: "0 0 24 24",
    stroke: "currentColor",
    strokeWidth: 1.6,
    strokeLinecap: "round" as const,
    strokeLinejoin: "round" as const,
    "aria-hidden": true,
  };
  const paths: Record<string, ReactNode> = {
    arrow: <><path d="M5 12h14" /><path d="m13 6 6 6-6 6" /></>,
    bolt: <path d="m13 2-8 12h7l-1 8 8-12h-7l1-8Z" />,
    property: <><path d="M3 21h18" /><path d="M5 21V9l7-4 7 4v12" /><path d="M9 21v-7h6v7" /></>,
    document: <><path d="M6 2h9l4 4v16H6z" /><path d="M14 2v5h5" /><path d="M9 13h6M9 17h6" /></>,
    calculator: <><rect x="5" y="2" width="14" height="20" rx="1.5" /><path d="M8 6h8v4H8zM8 14h.01M12 14h.01M16 14h.01M8 18h.01M12 18h.01M16 18h.01" /></>,
    pin: <><path d="M20 10c0 5-8 12-8 12S4 15 4 10a8 8 0 1 1 16 0Z" /><circle cx="12" cy="10" r="2.5" /></>,
    chart: <><path d="M4 20V10M10 20V4M16 20v-7M22 20V2" /><path d="M2 20h22" /></>,
    laptop: <><rect x="4" y="4" width="16" height="12" rx="1.5" /><path d="M2 20h20M9 20h6" /></>,
    clock: <><circle cx="12" cy="12" r="9" /><path d="M12 7v6l4 2" /></>,
    message: <><path d="M4 5h16v11H9l-5 4z" /><path d="M8 10h.01M12 10h.01M16 10h.01" /></>,
    "search-doc": <><path d="M5 3h9l4 4v7" /><path d="M13 3v5h5" /><path d="M8 12h4M8 16h3" /><circle cx="17" cy="17" r="3" /><path d="m19.5 19.5 2 2" /></>,
    folder: <path d="M3 6h7l2 2h9v11H3z" />,
    team: <><circle cx="8" cy="8" r="3" /><circle cx="17" cy="7" r="2.5" /><path d="M2 20c0-4 2.5-6 6-6s6 2 6 6M15 13c3.5 0 6 2 6 6" /></>,
    shield: <><path d="M12 2 4 5v6c0 5 3.5 8.5 8 11 4.5-2.5 8-6 8-11V5z" /><path d="m8.5 12 2.2 2.2 4.8-5" /></>,
    inbox: <><path d="M4 4h16v15H4z" /><path d="m4 14 4-3 3 3h2l3-3 4 3" /></>,
    calendar: <><rect x="4" y="5" width="16" height="15" rx="1.5" /><path d="M8 3v4M16 3v4M4 10h16" /></>,
    search: <><circle cx="11" cy="11" r="7" /><path d="m16 16 5 5" /></>,
    check: <><circle cx="12" cy="12" r="9" /><path d="m8 12 2.5 2.5L16 9" /></>,
    database: <><ellipse cx="12" cy="5" rx="7" ry="3" /><path d="M5 5v7c0 1.7 3.1 3 7 3s7-1.3 7-3V5M5 12v7c0 1.7 3.1 3 7 3s7-1.3 7-3v-7" /></>,
    bell: <><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9" /><path d="M10 21h4" /></>,
    sliders: <><path d="M4 6h16M4 12h16M4 18h16" /><circle cx="9" cy="6" r="1.5" /><circle cx="15" cy="12" r="1.5" /><circle cx="11" cy="18" r="1.5" /></>,
    menu: <><path d="M4 7h16M4 12h16M4 17h16" /></>,
  };
  return <svg {...common}>{paths[name]}</svg>;
}

const SectionLabel = ({ children }: { children: ReactNode }) => (
  <p className="mb-5 text-[0.7rem] font-semibold uppercase tracking-[0.18em] text-blue-800">{children}</p>
);

const Index = () => {
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

  return (
    <div className="min-h-[100dvh] overflow-hidden bg-white text-slate-950">
      <header className="fixed inset-x-0 top-0 z-20 border-b border-slate-200/80 bg-white/95 backdrop-blur">
        <div className="mx-auto flex h-[74px] max-w-[1440px] items-center justify-between px-5 sm:px-8 lg:px-12">
          <a href="#" className="text-[1.45rem] font-semibold tracking-[0.18em] text-[#09275d]">
            RANDA <span className="ml-0.5 text-[0.58rem] font-medium tracking-[0.08em] text-slate-500">SRL</span>
          </a>
          <nav className="hidden items-center gap-9 text-sm font-medium text-slate-600 md:flex" aria-label="Navigazione principale">
            <a className="nav-link" href="#approccio">Approccio</a>
            <a className="nav-link" href="#servizi">Servizi</a>
            <a className="nav-link" href="#organizzazione">Organizzazione</a>
            <a className="nav-link" href="#contatti">Contatti</a>
          </nav>
          <a href="#contatti" className="hidden rounded-md bg-[#08275d] px-5 py-3 text-sm font-semibold text-white transition hover:bg-[#0c377e] active:translate-y-px md:inline-flex">
            Parla con il team
          </a>
          <button
            className="text-[#08275d] md:hidden"
            aria-label={mobileMenuOpen ? "Chiudi menu" : "Apri menu"}
            aria-expanded={mobileMenuOpen}
            onClick={() => setMobileMenuOpen((open) => !open)}
          >
            <Icon name="menu" />
          </button>
        </div>
        {mobileMenuOpen && (
          <nav className="border-t border-slate-200 bg-white px-5 py-5 md:hidden" aria-label="Navigazione mobile">
            <div className="grid gap-4 text-sm font-medium text-slate-700">
              {[
                ["Approccio", "#approccio"],
                ["Servizi", "#servizi"],
                ["Organizzazione", "#organizzazione"],
                ["Contatti", "#contatti"],
              ].map(([label, href]) => (
                <a key={href} href={href} onClick={() => setMobileMenuOpen(false)}>{label}</a>
              ))}
            </div>
          </nav>
        )}
      </header>

      <main>
        <section className="relative min-h-[680px] pt-[74px] lg:min-h-[720px]">
          <div className="mx-auto grid min-h-[606px] max-w-[1440px] lg:min-h-[646px] lg:grid-cols-[1.05fr_0.95fr]">
            <div className="relative z-10 flex items-center px-5 py-20 sm:px-8 lg:px-12 lg:py-24">
              <div className="max-w-[620px] animate-fade-up">
                <h1 className="max-w-[620px] text-[3rem] font-medium leading-[1.03] tracking-[-0.055em] text-slate-950 sm:text-[4rem] lg:text-[4.15rem] xl:text-[4.55rem]">
                  Gestione peritale, progettata per il presente.
                </h1>
                <div className="my-8 h-[2px] w-16 bg-[#0a3475]" />
                <p className="max-w-[540px] text-base leading-8 text-slate-600 sm:text-lg">
                  Randa SRL è una realtà peritale specializzata nella gestione property e Fenomeno Elettrico. Affianchiamo compagnie, network e operatori claims con competenza tecnica, organizzazione e rapidità operativa.
                </p>
                <a href="#contatti" className="group mt-10 inline-flex items-center gap-8 rounded-md bg-[#08275d] px-6 py-3.5 text-sm font-semibold text-white transition hover:bg-[#0c377e] active:translate-y-px">
                  Contattaci
                  <Icon name="arrow" className="h-4 w-4 transition-transform group-hover:translate-x-1" />
                </a>
              </div>
            </div>
            <div className="relative min-h-[440px] overflow-hidden lg:min-h-0">
              <img
                src="/images/randa-sopralluogo-fenomeno-elettrico.png"
                alt="Sopralluogo tecnico su un quadro elettrico"
                className="absolute inset-0 h-full w-full object-cover object-[65%_center]"
              />
              <div className="absolute inset-y-0 left-0 hidden w-28 bg-gradient-to-r from-white to-transparent lg:block" />
            </div>
          </div>
        </section>

        <section id="approccio" className="scroll-mt-20 border-y border-slate-200 bg-[#f7f9fc]">
          <div className="mx-auto grid max-w-[1440px] gap-12 px-5 py-20 sm:px-8 lg:grid-cols-[0.75fr_2.25fr] lg:px-12 lg:py-28">
            <div className="max-w-[310px]">
              <SectionLabel>Il nostro approccio</SectionLabel>
              <h2 className="text-3xl font-medium leading-tight tracking-[-0.04em] text-slate-950">Metodo, precisione e responsabilità.</h2>
              <p className="mt-7 text-sm leading-7 text-slate-600">
                Randa nasce dall’esperienza diretta sul campo e dalla necessità di rendere più ordinata, trasparente ed efficace la gestione del sinistro.
              </p>
            </div>
            <div className="grid md:grid-cols-3">
              {approach.map(([icon, title, text], index) => (
                <article key={title} className={`border-slate-200 py-7 md:px-8 ${index > 2 ? "border-t" : ""} ${index % 3 !== 0 ? "md:border-l" : ""}`}>
                  <Icon name={icon} className="mb-6 h-7 w-7 text-[#08275d]" />
                  <h3 className="text-base font-semibold text-slate-900">{title}</h3>
                  <p className="mt-3 text-sm leading-6 text-slate-600">{text}</p>
                </article>
              ))}
            </div>
          </div>
        </section>

        <section id="servizi" className="scroll-mt-20 bg-white">
          <div className="mx-auto max-w-[1440px] px-5 py-20 sm:px-8 lg:px-12 lg:py-28">
            <SectionLabel>I nostri servizi</SectionLabel>
            <h2 className="max-w-[520px] text-3xl font-medium leading-tight tracking-[-0.04em] text-slate-950 sm:text-4xl">
              Competenze complete per la gestione del sinistro.
            </h2>
            <div className="mt-14 grid md:grid-cols-2 lg:grid-cols-4">
              {services.map((service, index) => (
                <article key={service.title} className={`border-slate-200 py-8 md:px-8 ${index > 3 ? "lg:border-t" : ""} ${index % 4 !== 0 ? "lg:border-l" : ""} ${index > 0 ? "border-t md:border-t-0" : ""}`}>
                  <Icon name={service.icon} className="mb-7 h-7 w-7 text-[#08275d]" />
                  <h3 className="text-base font-semibold text-slate-900">{service.title}</h3>
                  <p className="mt-3 text-sm leading-6 text-slate-600">{service.text}</p>
                </article>
              ))}
            </div>
          </div>
        </section>

        <section id="organizzazione" className="scroll-mt-20 border-y border-slate-200 bg-[#f7f9fc]">
          <div className="mx-auto grid max-w-[1440px] gap-14 px-5 py-20 sm:px-8 lg:grid-cols-[0.8fr_2.2fr] lg:px-12 lg:py-28">
            <div className="max-w-[330px]">
              <SectionLabel>La nostra organizzazione</SectionLabel>
              <h2 className="text-3xl font-medium leading-tight tracking-[-0.04em] text-slate-950">Un processo solido, persone competenti, strumenti proprietari.</h2>
              <p className="mt-7 text-sm leading-7 text-slate-600">
                Ogni sinistro segue un percorso strutturato e condiviso, con ruoli chiari e controlli puntuali.
              </p>
              <div className="mt-8 border-t-2 border-[#0a3475] pt-5 text-xs leading-6 text-slate-600">
                Utilizziamo strumenti proprietari sviluppati internamente per ottimizzare tracciabilità, organizzazione e gestione operativa dei sinistri.
              </div>
            </div>
            <div className="relative flex items-center">
              <div className="absolute left-[8%] right-[8%] top-[43px] hidden h-px bg-slate-300 lg:block" />
              <div className="grid w-full gap-9 sm:grid-cols-2 lg:grid-cols-5">
                {workflow.map(([icon, number, title, text]) => (
                  <div key={number} className="relative text-center">
                    <div className="relative z-10 mx-auto flex h-[86px] w-[86px] items-center justify-center rounded-full bg-[#08275d] text-white shadow-[0_10px_25px_-16px_rgba(8,39,93,0.65)]">
                      <Icon name={icon} className="h-7 w-7" />
                    </div>
                    <p className="mt-5 font-mono text-xs text-slate-500">{number}</p>
                    <p className="mt-2 text-sm font-semibold leading-6 text-slate-900">{title}<br /><span className="font-normal text-slate-600">{text}</span></p>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </section>

        <section className="bg-white">
          <div className="mx-auto grid max-w-[1440px] gap-12 px-5 py-20 sm:px-8 lg:grid-cols-[0.8fr_2.2fr] lg:px-12 lg:py-24">
            <div className="max-w-[330px]">
              <SectionLabel>I nostri impegni</SectionLabel>
              <h2 className="text-3xl font-medium leading-tight tracking-[-0.04em] text-slate-950">Performance misurabili, valore per i nostri partner.</h2>
            </div>
            <div className="grid sm:grid-cols-2 lg:grid-cols-5">
              {commitments.map(([icon, title, text], index) => (
                <article key={title} className={`border-slate-200 py-6 lg:px-7 ${index > 0 ? "border-t sm:border-t-0 lg:border-l" : ""}`}>
                  <Icon name={icon} className="mb-6 h-7 w-7 text-[#08275d]" />
                  <h3 className="text-sm font-semibold leading-5 text-slate-900">{title}</h3>
                  <p className="mt-3 text-xs leading-5 text-slate-600">{text}</p>
                </article>
              ))}
            </div>
          </div>
        </section>
      </main>

      <footer id="contatti" className="scroll-mt-20 bg-[#06265a] text-white">
        <div className="mx-auto grid max-w-[1440px] gap-12 px-5 py-16 sm:px-8 md:grid-cols-[1.3fr_0.7fr_1fr] lg:px-12">
          <div>
            <p className="text-[1.45rem] font-semibold tracking-[0.18em]">RANDA <span className="text-[0.58rem] font-medium tracking-[0.08em] text-blue-200">SRL</span></p>
            <p className="mt-5 max-w-[360px] text-sm leading-7 text-blue-100/80">
              Realtà peritale specializzata nella gestione property e Fenomeno Elettrico. Competenza tecnica, organizzazione e rapidità al servizio dei nostri partner.
            </p>
          </div>
          <div>
            <p className="footer-label">Link</p>
            <div className="mt-5 grid gap-3 text-sm text-blue-100/80">
              <a href="#approccio">Approccio</a>
              <a href="#servizi">Servizi</a>
              <a href="#organizzazione">Organizzazione</a>
              <a href="#contatti">Contatti</a>
            </div>
          </div>
          <div>
            <p className="footer-label">Contatti</p>
            <div className="mt-5 grid gap-3 text-sm text-blue-100/80">
              <a href="mailto:info@randapro.it">info@randapro.it</a>
              <a href="https://www.randapro.it">www.randapro.it</a>
              <p>Italia</p>
            </div>
          </div>
        </div>
        <div className="mx-auto flex max-w-[1440px] flex-col gap-3 border-t border-white/15 px-5 py-5 text-xs text-blue-100/60 sm:flex-row sm:items-center sm:justify-between sm:px-8 lg:px-12">
          <p>© 2026 Randa SRL</p>
          <p>Privacy Policy · Cookie Policy</p>
        </div>
      </footer>
    </div>
  );
};

export default Index;
