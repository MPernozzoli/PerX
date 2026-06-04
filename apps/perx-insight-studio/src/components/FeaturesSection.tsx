import { Eye, FileText, CalendarCheck, MessageSquare, Radar, Send } from "lucide-react";
import { Card } from "@perx/ui/components/ui/card";
import { useScrollReveal } from "@/hooks/use-scroll-reveal";

const features = [
  {
    icon: Eye,
    title: "Stato pratica sempre visibile",
    description:
      "Ogni pratica ha un avanzamento chiaro, con passaggi successivi, attività aperte e visibilità sul ciclo del sinistro. Sai sempre dove sei e cosa manca.",
    accent: false,
  },
  {
    icon: Radar,
    title: "Organizzazione proattiva delle pratiche",
    description:
      "Il sistema monitora l'urgenza di ogni sinistro, intercetta solleciti e scadenze, e organizza la schedulazione del lavoro. I sinistri urgenti vengono gestiti subito — quelli senza sollecito non restano dimenticati.",
    accent: true,
  },
  {
    icon: Send,
    title: "Aggiornamenti automatici a tutti gli attori",
    description:
      "Assicurati, agenzie e liquidatori ricevono aggiornamenti concreti e puntuali: a che punto è la pratica, cosa sta succedendo e perché. Niente più telefonate per chiedere novità.",
    accent: false,
  },
  {
    icon: FileText,
    title: "Raccolta documentale guidata",
    description:
      "Foto, video e documenti vengono richiesti in modo strutturato. L'assicurato sa cosa caricare, il team riceve materiale completo — meno richieste ripetute, meno invii sparsi.",
    accent: false,
  },
  {
    icon: CalendarCheck,
    title: "Sopralluoghi organizzati",
    description:
      "Conferma del luogo, scelta delle disponibilità, coordinamento degli appuntamenti. L'organizzazione sul territorio diventa un passaggio fluido, non un'attività separata.",
    accent: true,
  },
  {
    icon: MessageSquare,
    title: "Messaggistica collegata alla pratica",
    description:
      "Ogni comunicazione tra assicurato e team ha un contesto. Niente più messaggi persi tra canali diversi: tutto è tracciato e collegato al fascicolo.",
    accent: false,
  },
];

export const FeaturesSection = () => {
  const { ref, isVisible } = useScrollReveal();

  return (
    <section id="funzionalita" className="py-24 md:py-32 relative overflow-hidden">
      {/* Decorative */}
      <div className="absolute top-1/3 -right-32 w-96 h-96 bg-primary/5 rounded-full blur-3xl animate-glow-pulse" />
      <div className="absolute bottom-1/4 -left-32 w-80 h-80 bg-secondary/5 rounded-full blur-3xl animate-glow-pulse" style={{ animationDelay: "2s" }} />

      <div ref={ref} className="container px-6 relative z-10">
        <div className={`text-center mb-16 transition-all duration-700 ${isVisible ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-8'}`}>
          <h2 className="text-4xl md:text-5xl font-bold mb-4">
            Come migliora il lavoro quotidiano
          </h2>
          <p className="text-lg text-muted-foreground max-w-3xl mx-auto">
            Ogni funzionalità di PerX è pensata per ridurre un problema concreto: meno tempo perso, meno passaggi manuali, più continuità operativa.
          </p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 max-w-6xl mx-auto">
          {features.map((feature, index) => (
            <Card
              key={index}
              className={`group backdrop-blur-xl border-border transition-all duration-500 p-8 hover:-translate-y-2 hover:shadow-2xl ${
                feature.accent 
                  ? 'bg-gradient-to-br from-primary/10 to-secondary/10 border-primary/20 hover:border-primary/40 hover:shadow-primary/10' 
                  : 'bg-card/50 hover:border-primary/50 hover:shadow-primary/10'
              } ${
                isVisible ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-12'
              }`}
              style={{ transitionDelay: isVisible ? `${150 + index * 100}ms` : '0ms' }}
            >
              <div className="mb-4">
                <div className={`inline-flex p-3 rounded-xl group-hover:scale-110 transition-all duration-300 ${
                  feature.accent ? 'bg-gradient-hero shadow-lg shadow-primary/20' : 'bg-gradient-hero'
                }`}>
                  <feature.icon className="w-6 h-6 text-primary-foreground" />
                </div>
              </div>
              <h3 className="text-xl font-semibold mb-2 text-foreground group-hover:text-primary transition-colors">
                {feature.title}
              </h3>
              <p className="text-muted-foreground">{feature.description}</p>
            </Card>
          ))}
        </div>
      </div>
    </section>
  );
};
