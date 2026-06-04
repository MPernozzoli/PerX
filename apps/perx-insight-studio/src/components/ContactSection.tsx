import { useState } from "react";
import { Button } from "@perx/ui/components/ui/button";
import { Input } from "@perx/ui/components/ui/input";
import { Textarea } from "@perx/ui/components/ui/textarea";
import { Label } from "@perx/ui/components/ui/label";
import { Checkbox } from "@perx/ui/components/ui/checkbox";
import { useToast } from "@/hooks/use-toast";
import { supabase } from "@/integrations/supabase/client";
import { z } from "zod";
import { useScrollReveal } from "@/hooks/use-scroll-reveal";

const contactSchema = z.object({
  name: z.string().trim().min(1, "Il nome è obbligatorio").max(100),
  email: z.string().trim().email("Email non valida").max(255),
  company: z.string().trim().max(200).optional(),
  message: z.string().trim().min(1, "Il messaggio è obbligatorio").max(1000),
  subscribeToNewsletter: z.boolean().default(false),
});

export const ContactSection = () => {
  const { toast } = useToast();
  const { ref, isVisible } = useScrollReveal();
  const [formData, setFormData] = useState({
    name: "",
    email: "",
    company: "",
    message: "",
    subscribeToNewsletter: false,
  });
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [isSubmitting, setIsSubmitting] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrors({});
    setIsSubmitting(true);

    try {
      const validatedData = contactSchema.parse(formData);
      const submissionId = crypto.randomUUID();
      
      if (validatedData.subscribeToNewsletter) {
        await supabase
          .from("newsletter_subscribers")
          .insert([{ 
            email: validatedData.email, 
            name: validatedData.name,
            company: validatedData.company || null
          }]);
      }

      await supabase.functions.invoke('send-transactional-email', {
        body: {
          templateName: 'contact-confirmation',
          recipientEmail: validatedData.email,
          idempotencyKey: `contact-confirm-${submissionId}`,
          templateData: { 
            name: validatedData.name, 
            company: validatedData.company,
            message: validatedData.message 
          },
        },
      });

      await supabase.functions.invoke('send-transactional-email', {
        body: {
          templateName: 'contact-notification',
          recipientEmail: 'info@perx.it',
          idempotencyKey: `contact-notify-${submissionId}`,
          templateData: { 
            name: validatedData.name,
            email: validatedData.email,
            company: validatedData.company,
            message: validatedData.message 
          },
        },
      });
      
      toast({
        title: "Richiesta inviata!",
        description: "Ti contatteremo presto per una presentazione di PerX.",
      });
      
      setFormData({ name: "", email: "", company: "", message: "", subscribeToNewsletter: false });
    } catch (error) {
      if (error instanceof z.ZodError) {
        const fieldErrors: Record<string, string> = {};
        error.errors.forEach((err) => {
          if (err.path[0]) {
            fieldErrors[err.path[0] as string] = err.message;
          }
        });
        setErrors(fieldErrors);
        toast({
          title: "Errore di validazione",
          description: "Controlla i campi evidenziati",
          variant: "destructive",
        });
      } else {
        console.error("Error sending email:", error);
        toast({
          title: "Errore nell'invio",
          description: "Si è verificato un problema. Riprova più tardi.",
          variant: "destructive",
        });
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => {
    const { name, value } = e.target;
    setFormData(prev => ({ ...prev, [name]: value }));
    if (errors[name]) {
      setErrors(prev => ({ ...prev, [name]: "" }));
    }
  };

  return (
    <section id="contact" className="py-24 md:py-32 relative overflow-hidden">
      <div className="absolute inset-0 bg-gradient-card opacity-50" />
      <div className="absolute top-20 right-20 w-72 h-72 bg-primary/8 rounded-full blur-3xl animate-glow-pulse" />
      
      <div ref={ref} className="container relative z-10 px-6">
        <div className="max-w-2xl mx-auto">
          <div className={`text-center mb-12 transition-all duration-700 ${isVisible ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-8'}`}>
            <h2 className="text-4xl md:text-5xl font-bold mb-4">
              Richiedi una presentazione
            </h2>
            <p className="text-lg text-muted-foreground">
              Raccontaci come lavora il tuo studio. Ti mostreremo come PerX può semplificare il flusso delle tue pratiche.
            </p>
          </div>

          <div className={`backdrop-blur-xl bg-card/50 border border-border rounded-2xl p-8 md:p-10 shadow-2xl transition-all duration-700 delay-200 ${isVisible ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-12'}`}>
            <form onSubmit={handleSubmit} className="space-y-6">
              <div className="space-y-2">
                <Label htmlFor="name">Nome *</Label>
                <Input
                  id="name"
                  name="name"
                  value={formData.name}
                  onChange={handleChange}
                  className={`bg-input border-border ${errors.name ? 'border-destructive' : ''}`}
                  placeholder="Il tuo nome"
                  required
                />
                {errors.name && <p className="text-sm text-destructive">{errors.name}</p>}
              </div>

              <div className="space-y-2">
                <Label htmlFor="email">Email *</Label>
                <Input
                  id="email"
                  name="email"
                  type="email"
                  value={formData.email}
                  onChange={handleChange}
                  className={`bg-input border-border ${errors.email ? 'border-destructive' : ''}`}
                  placeholder="la.tua@email.it"
                  required
                />
                {errors.email && <p className="text-sm text-destructive">{errors.email}</p>}
              </div>

              <div className="space-y-2">
                <Label htmlFor="company">Studio / Azienda</Label>
                <Input
                  id="company"
                  name="company"
                  value={formData.company}
                  onChange={handleChange}
                  className="bg-input border-border"
                  placeholder="Nome dello studio (opzionale)"
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="message">Come lavori oggi? *</Label>
                <Textarea
                  id="message"
                  name="message"
                  value={formData.message}
                  onChange={handleChange}
                  className={`bg-input border-border min-h-32 ${errors.message ? 'border-destructive' : ''}`}
                  placeholder="Raccontaci brevemente come gestisci le pratiche oggi e cosa vorresti migliorare..."
                  required
                />
                {errors.message && <p className="text-sm text-destructive">{errors.message}</p>}
              </div>

              <div className="flex items-start space-x-3 p-4 bg-primary/5 border border-primary/20 rounded-lg">
                <Checkbox
                  id="subscribeToNewsletter"
                  checked={formData.subscribeToNewsletter}
                  onCheckedChange={(checked) => 
                    setFormData(prev => ({ ...prev, subscribeToNewsletter: checked as boolean }))
                  }
                  className="mt-1"
                />
                <div className="flex-1">
                  <Label 
                    htmlFor="subscribeToNewsletter" 
                    className="text-sm font-medium cursor-pointer"
                  >
                    Voglio ricevere aggiornamenti su PerX
                  </Label>
                  <p className="text-xs text-muted-foreground mt-1">
                    Ti terremo informato su novità e disponibilità della piattaforma
                  </p>
                </div>
              </div>

              <Button
                type="submit" 
                className="w-full bg-gradient-hero hover:opacity-90 transition-all duration-300 text-lg py-6 hover:scale-[1.02] hover:shadow-lg hover:shadow-primary/20"
                disabled={isSubmitting}
              >
                {isSubmitting ? "Invio in corso..." : "Richiedi una presentazione"}
              </Button>

              <p className="text-xs text-muted-foreground text-center">
                I tuoi dati saranno trattati nel rispetto del GDPR. 
                Inviando questo modulo acconsenti al trattamento dei dati personali per finalità di contatto.
              </p>
            </form>
          </div>
        </div>
      </div>
    </section>
  );
};
