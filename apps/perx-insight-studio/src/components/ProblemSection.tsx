import { FileSearch, MessageSquareOff, MapPinOff, Clock } from "lucide-react";
import { useScrollReveal } from "@/hooks/use-scroll-reveal";

const problems = [
  {
    icon: FileSearch,
    title: "Documenti sparsi",
    description:
      "Foto su WhatsApp, perizie in allegato mail, atti su portali diversi. Ogni pratica diventa una caccia al documento giusto, nel posto giusto, al momento giusto.",
  },
  {
    icon: MessageSquareOff,
    title: "Comunicazioni frammentate",
    description:
      "Email personali, thread inoltrati, messaggi su canali diversi. Le informazioni ci sono, ma ricostruire chi ha detto cosa — e quando — richiede tempo che non hai.",
  },
  {
    icon: MapPinOff,
    title: "Sopralluoghi da coordinare",
    description:
      "Conferme telefoniche, disponibilità da incrociare, spostamenti da ottimizzare. Organizzare gli appuntamenti sul territorio resta uno dei punti più faticosi della giornata.",
  },
  {
    icon: Clock,
    title: "Follow-up manuali",
    description:
      "Solleciti da ricordare, scadenze da controllare, passaggi che dipendono da altri. Senza un flusso chiaro, il rischio è sempre lo stesso: qualcosa resta indietro.",
  },
];

export const ProblemSection = () => {
  const { ref, isVisible } = useScrollReveal();

  return (
    <section id="problema" className="py-24 md:py-32 relative overflow-hidden">
      <div className="absolute inset-0 bg-gradient-card opacity-50" />
      
      {/* Decorative elements */}
      <div className="absolute top-10 right-10 w-72 h-72 bg-destructive/5 rounded-full blur-3xl animate-glow-pulse" />
      <div className="absolute bottom-10 left-10 w-64 h-64 bg-primary/5 rounded-full blur-3xl animate-glow-pulse" style={{ animationDelay: "1.5s" }} />

      <div ref={ref} className="container relative z-10 px-6">
        <div className={`max-w-4xl mx-auto text-center mb-16 transition-all duration-700 ${isVisible ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-8'}`}>
          <h2 className="text-4xl md:text-5xl font-bold mb-6">
            Il lavoro peritale è fatto di troppe variabili
          </h2>
          <p className="text-lg text-muted-foreground max-w-3xl mx-auto">
            Ogni pratica attraversa decine di passaggi, coinvolge più persone e
            genera un volume di informazioni difficile da governare. Il risultato?
            Tempo perso a rincorrere, invece che a lavorare.
          </p>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-6 max-w-5xl mx-auto">
          {problems.map((problem, index) => (
            <div
              key={index}
              className={`group backdrop-blur-xl bg-card/50 border border-border rounded-2xl p-8 hover:border-destructive/30 transition-all duration-500 hover:-translate-y-1 hover:shadow-xl hover:shadow-destructive/5 ${
                isVisible ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-12'
              }`}
              style={{ transitionDelay: isVisible ? `${200 + index * 150}ms` : '0ms' }}
            >
              <div className="flex items-start gap-4">
                <div className="p-3 rounded-xl bg-destructive/20 group-hover:bg-destructive/30 group-hover:scale-110 transition-all duration-300">
                  <problem.icon className="w-6 h-6 text-destructive" />
                </div>
                <div className="flex-1">
                  <h3 className="text-xl font-semibold mb-2 text-foreground">
                    {problem.title}
                  </h3>
                  <p className="text-muted-foreground">{problem.description}</p>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
};
