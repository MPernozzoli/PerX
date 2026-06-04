import { useScrollReveal } from "@/hooks/use-scroll-reveal";

const steps = [
  {
    number: "01",
    title: "Un unico flusso, leggibile",
    description:
      "Ogni pratica ha uno stato chiaro, passaggi successivi definiti e attività aperte visibili. Sai sempre a che punto sei e cosa manca per andare avanti.",
  },
  {
    number: "02",
    title: "Informazioni dove servono",
    description:
      "Documenti, comunicazioni, appuntamenti e scadenze sono collegati alla pratica. Niente più ricerche tra cartelle, email e chat separate.",
  },
  {
    number: "03",
    title: "Il sistema lavora con te",
    description:
      "Urgenze, solleciti e scadenze vengono intercettati e organizzati. Aggiornamenti concreti partono in automatico verso assicurati, agenzie e liquidatori. Il lavoro avanza senza che tu debba rincorrere ogni cosa.",
  },
];

export const SolutionSection = () => {
  const { ref, isVisible } = useScrollReveal();

  return (
    <section id="soluzione" className="py-24 md:py-32 relative">
      {/* Decorative gradient line */}
      <div className="absolute left-1/2 top-0 w-px h-24 bg-gradient-to-b from-transparent to-primary/30" />

      <div ref={ref} className="container px-6">
        <div className={`max-w-4xl mx-auto text-center mb-16 transition-all duration-700 ${isVisible ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-8'}`}>
          <h2 className="text-4xl md:text-5xl font-bold mb-6">
            <span className="bg-gradient-hero bg-clip-text text-transparent">
              PerX rimette in ordine il flusso
            </span>
          </h2>
          <p className="text-lg text-muted-foreground max-w-3xl mx-auto">
            Una piattaforma operativa che ricollega ogni passaggio della pratica
            in un processo continuo — dalla presa in carico alla chiusura.
          </p>
        </div>

        <div className="max-w-4xl mx-auto relative">
          {/* Vertical connecting line */}
          <div className={`absolute left-8 top-8 bottom-8 w-px hidden md:block transition-all duration-1000 ${isVisible ? 'opacity-100' : 'opacity-0'}`}>
            <div className={`w-full bg-gradient-to-b from-primary/50 via-secondary/50 to-accent/50 ${isVisible ? 'animate-draw-line' : 'h-0'}`} style={{ height: isVisible ? '100%' : '0%', transition: 'height 1.5s ease-out' }} />
          </div>

          <div className="space-y-12">
            {steps.map((step, index) => (
              <div
                key={index}
                className={`flex items-start gap-6 group transition-all duration-600 ${
                  isVisible ? 'opacity-100 translate-x-0' : 'opacity-0 -translate-x-8'
                }`}
                style={{ transitionDelay: isVisible ? `${300 + index * 250}ms` : '0ms' }}
              >
                <div className="relative flex-shrink-0 w-16 h-16 rounded-2xl bg-gradient-hero flex items-center justify-center text-primary-foreground font-bold text-lg shadow-lg shadow-primary/20 group-hover:scale-110 group-hover:shadow-xl group-hover:shadow-primary/30 transition-all duration-300 z-10">
                  {step.number}
                </div>
                <div className="flex-1 pt-2 backdrop-blur-sm bg-card/30 rounded-2xl p-6 border border-transparent group-hover:border-primary/20 transition-all duration-300">
                  <h3 className="text-2xl font-semibold mb-2 text-foreground group-hover:text-primary transition-colors">
                    {step.title}
                  </h3>
                  <p className="text-muted-foreground text-lg">
                    {step.description}
                  </p>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
};
