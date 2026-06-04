import { User, Upload, Bell, FileSignature } from "lucide-react";
import { useScrollReveal } from "@/hooks/use-scroll-reveal";

const portalFeatures = [
  {
    icon: User,
    title: "Stato pratica sempre visibile",
    description:
      "L'assicurato vede a che punto è la pratica, quali passaggi sono stati completati e cosa succede dopo. Meno telefonate per chiedere aggiornamenti.",
  },
  {
    icon: Upload,
    title: "Caricamento guidato",
    description:
      "Foto, video e documenti vengono richiesti in modo chiaro, con indicazioni su cosa serve e dove caricarlo. Meno invii incompleti, meno richieste ripetute.",
  },
  {
    icon: Bell,
    title: "Notifiche e aggiornamenti concreti",
    description:
      "Ogni novità sulla pratica arriva in modo chiaro e specifico: cosa è cambiato, cosa sta succedendo e perché. L'assicurato sa quando intervenire senza dover chiamare.",
  },
  {
    icon: FileSignature,
    title: "IBAN, firma OTP e chiusura pratica",
    description:
      "L'assicurato inserisce le coordinate bancarie con validazione in tempo reale e firma l'atto digitalmente tramite OTP — tutto dal portale, senza stampare, scansionare o rimandare.",
  },
];

export const PortalSection = () => {
  const { ref, isVisible } = useScrollReveal();

  return (
    <section id="portale" className="py-24 md:py-32 relative overflow-hidden">
      <div className="absolute inset-0 bg-gradient-card opacity-50" />
      <div className="absolute top-20 left-1/4 w-80 h-80 bg-secondary/8 rounded-full blur-3xl animate-glow-pulse" style={{ animationDelay: "0.5s" }} />

      <div ref={ref} className="container relative z-10 px-6">
        <div className="max-w-5xl mx-auto">
          <div className="grid grid-cols-1 lg:grid-cols-5 gap-12 items-start">
            {/* Left: title block */}
            <div className={`lg:col-span-2 lg:sticky lg:top-32 transition-all duration-700 ${isVisible ? 'opacity-100 translate-x-0' : 'opacity-0 -translate-x-8'}`}>
              <div className="inline-flex px-4 py-1.5 rounded-full bg-secondary/20 text-secondary text-sm font-medium mb-6">
                Per l'assicurato
              </div>
              <h2 className="text-4xl md:text-5xl font-bold mb-6">
                Un portale dedicato per l'assicurato
              </h2>
              <p className="text-lg text-muted-foreground">
                Invece di rincorrere l'assicurato per documenti, firme e
                conferme, PerX gli offre uno spazio chiaro dove seguire la pratica
                e fare la sua parte — nei tempi giusti, senza ambiguità.
              </p>
            </div>

            {/* Right: cards */}
            <div className="lg:col-span-3 space-y-5">
              {portalFeatures.map((feature, index) => (
                <div
                  key={index}
                  className={`group backdrop-blur-xl bg-card/50 border border-border rounded-2xl p-7 hover:border-secondary/50 transition-all duration-500 hover:-translate-y-1 hover:shadow-lg hover:shadow-secondary/5 ${
                    isVisible ? 'opacity-100 translate-x-0' : 'opacity-0 translate-x-8'
                  }`}
                  style={{ transitionDelay: isVisible ? `${200 + index * 150}ms` : '0ms' }}
                >
                  <div className="flex items-start gap-4">
                    <div className="p-3 rounded-xl bg-secondary/20 group-hover:bg-secondary/30 group-hover:scale-110 transition-all duration-300">
                      <feature.icon className="w-6 h-6 text-secondary" />
                    </div>
                    <div className="flex-1">
                      <h3 className="text-xl font-semibold mb-2 text-foreground">
                        {feature.title}
                      </h3>
                      <p className="text-muted-foreground">
                        {feature.description}
                      </p>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </section>
  );
};
