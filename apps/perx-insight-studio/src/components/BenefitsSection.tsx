import { UserCheck, Building2, Landmark, Users } from "lucide-react";
import { useScrollReveal } from "@/hooks/use-scroll-reveal";

const roles = [
  {
    icon: UserCheck,
    title: "Perito",
    color: "primary",
    benefits: [
      "Visibilità immediata su stato, urgenze e priorità delle pratiche",
      "Meno tempo a rincorrere documenti, risposte e firme",
      "Supporto alla lettura della documentazione e alla preparazione del lavoro",
      "Più continuità nella gestione quotidiana, meno interruzioni",
    ],
  },
  {
    icon: Building2,
    title: "Studio e back office",
    color: "secondary",
    benefits: [
      "Schedulazione intelligente: le urgenze emergono, nessun sinistro resta indietro",
      "Meno lavoro ripetitivo su solleciti, richieste e aggiornamenti",
      "Migliore distribuzione del carico nel team",
      "Meno dispersione tra strumenti e canali diversi",
    ],
  },
  {
    icon: Landmark,
    title: "Compagnia e liquidatore",
    color: "accent",
    benefits: [
      "Aggiornamenti automatici e concreti sullo stato della pratica",
      "Processo più tracciabile dall'incarico alla chiusura",
      "Tempi della pratica più governabili e prevedibili",
      "Comunicazioni strutturate, senza inseguimenti",
    ],
  },
  {
    icon: Users,
    title: "Assicurato",
    color: "primary",
    benefits: [
      "Esperienza chiara e guidata, dall'inizio alla firma",
      "Firma digitale OTP e inserimento IBAN direttamente dal portale",
      "Aggiornamenti puntuali: sa sempre a che punto è la pratica",
      "Meno attese, meno incertezza, meno telefonate",
    ],
  },
];

export const BenefitsSection = () => {
  const { ref, isVisible } = useScrollReveal();

  return (
    <section id="vantaggi" className="py-24 md:py-32 relative overflow-hidden">
      {/* Decorative */}
      <div className="absolute top-10 right-20 w-64 h-64 bg-primary/5 rounded-full blur-3xl animate-glow-pulse" />
      <div className="absolute bottom-10 left-20 w-72 h-72 bg-secondary/5 rounded-full blur-3xl animate-glow-pulse" style={{ animationDelay: "1s" }} />

      <div ref={ref} className="container px-6 relative z-10">
        <div className={`text-center mb-16 transition-all duration-700 ${isVisible ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-8'}`}>
          <h2 className="text-4xl md:text-5xl font-bold mb-6">
            Per chi è PerX
          </h2>
          <p className="text-lg text-muted-foreground max-w-3xl mx-auto">
            Ogni ruolo coinvolto nel ciclo della pratica lavora meglio quando il
            flusso è chiaro, le informazioni sono accessibili e i passaggi
            avanzano senza inseguimenti.
          </p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 max-w-6xl mx-auto">
          {roles.map((role, index) => (
            <div
              key={index}
              className={`backdrop-blur-xl bg-card/50 border border-border rounded-2xl p-6 hover:border-primary/30 transition-all duration-500 hover:-translate-y-2 hover:shadow-xl hover:shadow-primary/5 ${
                isVisible ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-12'
              }`}
              style={{ transitionDelay: isVisible ? `${200 + index * 120}ms` : '0ms' }}
            >
              <div className="mb-4">
                <div className="inline-flex p-3 rounded-xl bg-gradient-hero group-hover:scale-110 transition-transform duration-300">
                  <role.icon className="w-6 h-6 text-primary-foreground" />
                </div>
              </div>
              <h3 className="text-xl font-bold mb-4 text-foreground">
                {role.title}
              </h3>
              <ul className="space-y-3">
                {role.benefits.map((benefit, i) => (
                  <li
                    key={i}
                    className="text-sm text-muted-foreground flex items-start gap-2"
                  >
                    <span className="text-primary mt-1 flex-shrink-0">•</span>
                    <span>{benefit}</span>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
};
