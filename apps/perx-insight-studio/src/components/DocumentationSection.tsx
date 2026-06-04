import { FolderOpen, CreditCard, FileSignature, ShieldCheck } from "lucide-react";
import { useScrollReveal } from "@/hooks/use-scroll-reveal";

const items = [
  {
    icon: FolderOpen,
    title: "Fascicolo pratica ordinato",
    description:
      "Tutta la documentazione della pratica — foto, video, atti, comunicazioni — raccolta in un unico fascicolo strutturato. Maggiore tracciabilità, meno tempo a cercare.",
  },
  {
    icon: CreditCard,
    title: "Coordinate bancarie verificate in tempo reale",
    description:
      "L'assicurato inserisce personalmente le proprie coordinate bancarie sul portale e vengono validate in diretta. Niente più rincorse, niente errori di trascrizione, niente ritardi sulla liquidazione.",
  },
  {
    icon: FileSignature,
    title: "Firma digitale OTP direttamente dal portale",
    description:
      "L'atto arriva direttamente sul portale dell'assicurato, che lo può firmare digitalmente tramite OTP. Niente più \"non ho la stampante\", \"me lo sono dimenticato\", \"devo scansionarlo\". Un passaggio che prima richiedeva giorni, chiuso in minuti.",
  },
  {
    icon: ShieldCheck,
    title: "Privacy e protezione dei dati",
    description:
      "I dati degli assicurati e delle pratiche sono trattati con la massima attenzione alla riservatezza. Ogni accesso è controllato, ogni operazione è tracciata. La protezione delle informazioni non è un'opzione, è parte del processo.",
  },
];

export const DocumentationSection = () => {
  const { ref, isVisible } = useScrollReveal();

  return (
    <section id="documenti" className="py-24 md:py-32 relative overflow-hidden">
      <div className="absolute inset-0 bg-gradient-card opacity-30" />
      <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[500px] h-[500px] bg-accent/5 rounded-full blur-3xl animate-glow-pulse" />

      <div ref={ref} className="container relative z-10 px-6">
        <div className={`text-center mb-16 transition-all duration-700 ${isVisible ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-8'}`}>
          <div className="inline-flex px-4 py-1.5 rounded-full bg-accent/20 text-accent text-sm font-medium mb-6">
            Chiusura pratica
          </div>
          <h2 className="text-4xl md:text-5xl font-bold mb-6">
            Dal fascicolo alla firma, senza colli di bottiglia
          </h2>
          <p className="text-lg text-muted-foreground max-w-3xl mx-auto">
            Coordinate bancarie, documenti, firma dell'atto: ogni passaggio che
            porta alla chiusura della pratica avviene nel flusso — senza
            inseguimenti, senza attese evitabili.
          </p>
        </div>

        {/* Bento-like layout: 2 large on top, 2 below */}
        <div className="max-w-5xl mx-auto grid grid-cols-1 md:grid-cols-2 gap-6">
          {items.map((item, index) => (
            <div
              key={index}
              className={`group backdrop-blur-xl bg-card/50 border border-border rounded-2xl p-8 hover:border-accent/50 transition-all duration-500 hover:-translate-y-1 hover:shadow-xl hover:shadow-accent/5 ${
                isVisible ? 'opacity-100 scale-100' : 'opacity-0 scale-95'
              }`}
              style={{ transitionDelay: isVisible ? `${200 + index * 120}ms` : '0ms' }}
            >
              <div className="flex items-start gap-4">
                <div className="p-3 rounded-xl bg-accent/20 group-hover:bg-accent/30 group-hover:scale-110 transition-all duration-300">
                  <item.icon className="w-6 h-6 text-accent" />
                </div>
                <div className="flex-1">
                  <h3 className="text-xl font-semibold mb-2 text-foreground">
                    {item.title}
                  </h3>
                  <p className="text-muted-foreground">{item.description}</p>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
};
