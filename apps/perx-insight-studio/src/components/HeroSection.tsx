import { Button } from "@perx/ui/components/ui/button";
import { ChevronDown } from "lucide-react";
import perxLogo from "@/assets/perx-logo.png";

export const HeroSection = () => {
  const scrollToContact = () => {
    document.getElementById("contact")?.scrollIntoView({ behavior: "smooth" });
  };

  return (
    <section className="relative min-h-screen flex items-center justify-center overflow-hidden">
      {/* Animated background gradients */}
      <div className="absolute inset-0 bg-background">
        <div className="absolute top-20 left-10 w-96 h-96 bg-primary/20 rounded-full blur-3xl animate-float" />
        <div className="absolute bottom-20 right-10 w-96 h-96 bg-secondary/20 rounded-full blur-3xl animate-float" style={{ animationDelay: "1s" }} />
        <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[600px] h-[600px] bg-accent/10 rounded-full blur-3xl" />
      </div>

      <div className="container relative z-10 px-6 py-20 flex flex-col items-center text-center">
        <div className="mb-8 animate-fade-in-up">
          <img src={perxLogo.src} alt="PerX Logo" className="w-48 h-48 md:w-64 md:h-64 mx-auto drop-shadow-2xl" />
        </div>

        <p className="text-sm font-medium tracking-widest uppercase text-primary mb-6 animate-fade-in-up" style={{ animationDelay: "0.05s" }}>
          La piattaforma operativa per studi peritali
        </p>

        <h1 className="text-5xl md:text-7xl font-bold mb-6 animate-fade-in-up" style={{ animationDelay: "0.1s" }}>
          <span className="text-foreground">Meno rincorse.</span>
          <br />
          <span className="text-foreground">Più controllo.</span>
          <br />
          <span className="bg-gradient-hero bg-clip-text text-transparent">
            Il lavoro peritale,
            <br />
            finalmente in ordine.
          </span>
        </h1>

        <p className="text-xl md:text-2xl text-muted-foreground max-w-3xl mb-12 animate-fade-in-up" style={{ animationDelay: "0.2s" }}>
          PerX ricompone il flusso della pratica in un unico processo leggibile: documenti, comunicazioni, appuntamenti e scadenze — tutto dove serve, quando serve.
        </p>

        <Button 
          size="lg" 
          onClick={scrollToContact}
          className="text-lg px-8 py-6 bg-gradient-hero hover:opacity-90 transition-all duration-300 animate-fade-in-up shadow-2xl hover:shadow-primary/50 hover:scale-105"
          style={{ animationDelay: "0.3s" }}
        >
          Scopri come funziona
        </Button>

        <button 
          onClick={() => document.getElementById("problema")?.scrollIntoView({ behavior: "smooth" })}
          className="absolute bottom-10 left-1/2 -translate-x-1/2 animate-bounce cursor-pointer hover:scale-110 transition-transform"
          aria-label="Scroll down"
        >
          <ChevronDown className="w-8 h-8 text-muted-foreground" />
        </button>
      </div>
    </section>
  );
};
