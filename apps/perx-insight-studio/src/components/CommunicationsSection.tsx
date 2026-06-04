import { Mail, Link, MessageCircle } from "lucide-react";
import { useScrollReveal } from "@/hooks/use-scroll-reveal";

const commsItems = [
  {
    icon: Mail,
    title: "Email integrate",
    description:
      "Le email in entrata e in uscita vengono associate automaticamente alla pratica. Basta cercare tra caselle diverse e inoltri manuali.",
  },
  {
    icon: Link,
    title: "Ogni messaggio ha un contesto",
    description:
      "Non importa da dove arriva la comunicazione: è sempre collegata alla pratica giusta, leggibile da chi ci sta lavorando.",
  },
  {
    icon: MessageCircle,
    title: "Messaggistica con l'assicurato",
    description:
      "Contatti più lineari tra assicurato e team, senza passare da canali esterni. Tutto tracciato, tutto nel fascicolo.",
  },
];

export const CommunicationsSection = () => {
  const { ref, isVisible } = useScrollReveal();

  return (
    <section id="comunicazioni" className="py-24 md:py-32 relative overflow-hidden">
      {/* Decorative */}
      <div className="absolute bottom-0 right-0 w-96 h-96 bg-primary/5 rounded-full blur-3xl" />

      <div ref={ref} className="container px-6 relative z-10">
        <div className="max-w-5xl mx-auto">
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-16 items-center">
            <div className={`transition-all duration-700 ${isVisible ? 'opacity-100 translate-x-0' : 'opacity-0 -translate-x-8'}`}>
              <div className="inline-flex px-4 py-1.5 rounded-full bg-primary/20 text-primary text-sm font-medium mb-6">
                Comunicazioni
              </div>
              <h2 className="text-4xl md:text-5xl font-bold mb-6">
                Le comunicazioni, finalmente collegate alla pratica
              </h2>
              <p className="text-lg text-muted-foreground mb-8">
                Nel lavoro peritale le informazioni arrivano da ovunque: email
                personali, caselle condivise, inoltri, risposte a thread
                sbagliati. PerX centralizza le comunicazioni e le collega alla
                pratica di riferimento — così ogni messaggio ha un contesto e
                niente resta disperso.
              </p>
              {/* Visual accent */}
              <div className="hidden lg:flex items-center gap-3">
                <div className="w-12 h-1 bg-gradient-hero rounded-full" />
                <span className="text-sm text-muted-foreground">Tutto tracciato, tutto nel fascicolo</span>
              </div>
            </div>

            <div className="space-y-5">
              {commsItems.map((item, index) => (
                <div
                  key={index}
                  className={`group backdrop-blur-xl bg-card/50 border border-border rounded-2xl p-6 hover:border-primary/30 transition-all duration-500 hover:-translate-y-1 hover:shadow-lg hover:shadow-primary/5 ${
                    isVisible ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-8'
                  }`}
                  style={{ transitionDelay: isVisible ? `${300 + index * 150}ms` : '0ms' }}
                >
                  <div className="flex items-start gap-4">
                    <div className="p-3 rounded-xl bg-primary/20 group-hover:bg-primary/30 group-hover:scale-110 transition-all duration-300">
                      <item.icon className="w-6 h-6 text-primary" />
                    </div>
                    <div>
                      <h3 className="text-lg font-semibold mb-1 text-foreground">
                        {item.title}
                      </h3>
                      <p className="text-muted-foreground text-sm">
                        {item.description}
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
