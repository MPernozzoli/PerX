import { useState } from "react";
import { Button } from "@perx/ui/components/ui/button";
import { Input } from "@perx/ui/components/ui/input";
import { Textarea } from "@perx/ui/components/ui/textarea";
import { Label } from "@perx/ui/components/ui/label";
import { Checkbox } from "@perx/ui/components/ui/checkbox";
import { useToast } from "@/hooks/use-toast";
import { supabase } from "@/integrations/supabase/client";
import { z } from "zod";

const contactSchema = z.object({
  name: z.string().trim().min(1, "Il nome è obbligatorio").max(100),
  email: z.string().trim().email("Email non valida").max(255),
  company: z.string().trim().max(200).optional(),
  message: z.string().trim().min(1, "Il messaggio è obbligatorio").max(1000),
  subscribeToNewsletter: z.boolean().default(false),
});

export const ContactSection = () => {
  const { toast } = useToast();
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
      if (!supabase) {
        throw new Error("Supabase non configurato");
      }
      const submissionId = crypto.randomUUID();

      if (validatedData.subscribeToNewsletter) {
        await supabase.from("newsletter_subscribers").insert([
          {
            email: validatedData.email,
            name: validatedData.name,
            company: validatedData.company || null,
          },
        ]);
      }

      await supabase.functions.invoke("send-transactional-email", {
        body: {
          templateName: "contact-confirmation",
          recipientEmail: validatedData.email,
          idempotencyKey: `contact-confirm-${submissionId}`,
          templateData: {
            name: validatedData.name,
            company: validatedData.company,
            message: validatedData.message,
          },
        },
      });

      await supabase.functions.invoke("send-transactional-email", {
        body: {
          templateName: "contact-notification",
          recipientEmail: "info@perx.it",
          idempotencyKey: `contact-notify-${submissionId}`,
          templateData: {
            name: validatedData.name,
            email: validatedData.email,
            company: validatedData.company,
            message: validatedData.message,
          },
        },
      });

      toast({
        title: "Richiesta inviata",
        description: "Ti rispondiamo a breve a info@perx.it.",
      });

      setFormData({
        name: "",
        email: "",
        company: "",
        message: "",
        subscribeToNewsletter: false,
      });
    } catch (error) {
      if (error instanceof z.ZodError) {
        const fieldErrors: Record<string, string> = {};
        error.issues.forEach((err) => {
          if (err.path[0]) {
            fieldErrors[err.path[0] as string] = err.message;
          }
        });
        setErrors(fieldErrors);
        toast({
          title: "Controlla i campi",
          description: "Alcuni dati non sono validi.",
          variant: "destructive",
        });
      } else {
        console.error("Error sending email:", error);
        toast({
          title: "Invio non riuscito",
          description: "Riprova più tardi oppure scrivi a info@perx.it.",
          variant: "destructive",
        });
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleChange = (
    e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>,
  ) => {
    const { name, value } = e.target;
    setFormData((prev) => ({ ...prev, [name]: value }));
    if (errors[name]) {
      setErrors((prev) => ({ ...prev, [name]: "" }));
    }
  };

  return (
    <section
      id="contatto"
      className="border-t border-perx-line bg-[var(--ink)] text-white"
    >
      <div className="mx-auto grid max-w-6xl gap-12 px-6 py-16 md:grid-cols-[1fr_1.1fr] md:gap-20 md:px-10 md:py-24">
        <div>
          <p className="font-display text-xs font-semibold tracking-[0.18em] text-[var(--coral)] uppercase">
            Contatto
          </p>
          <h2 className="mt-3 font-display text-3xl font-semibold tracking-tight md:text-4xl">
            Parliamo del tuo studio.
          </h2>
          <p className="mt-4 text-base leading-relaxed text-white/60">
            Raccontaci volume, compagnie e come gestisci le pratiche oggi.
            Rispondiamo da info@perx.it.
          </p>
        </div>

        <form onSubmit={handleSubmit} className="space-y-5">
          <div className="space-y-2">
            <Label htmlFor="name" className="text-white/80">
              Nome *
            </Label>
            <Input
              id="name"
              name="name"
              value={formData.name}
              onChange={handleChange}
              className={`border-white/15 bg-white/5 text-white placeholder:text-white/35 ${
                errors.name ? "border-destructive" : ""
              }`}
              placeholder="Nome e cognome"
              required
            />
            {errors.name && <p className="text-sm text-red-300">{errors.name}</p>}
          </div>

          <div className="space-y-2">
            <Label htmlFor="email" className="text-white/80">
              Email *
            </Label>
            <Input
              id="email"
              name="email"
              type="email"
              value={formData.email}
              onChange={handleChange}
              className={`border-white/15 bg-white/5 text-white placeholder:text-white/35 ${
                errors.email ? "border-destructive" : ""
              }`}
              placeholder="nome@studio.it"
              required
            />
            {errors.email && (
              <p className="text-sm text-red-300">{errors.email}</p>
            )}
          </div>

          <div className="space-y-2">
            <Label htmlFor="company" className="text-white/80">
              Studio
            </Label>
            <Input
              id="company"
              name="company"
              value={formData.company}
              onChange={handleChange}
              className="border-white/15 bg-white/5 text-white placeholder:text-white/35"
              placeholder="Nome dello studio"
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="message" className="text-white/80">
              Messaggio *
            </Label>
            <Textarea
              id="message"
              name="message"
              value={formData.message}
              onChange={handleChange}
              className={`min-h-28 border-white/15 bg-white/5 text-white placeholder:text-white/35 ${
                errors.message ? "border-destructive" : ""
              }`}
              placeholder="Volume pratiche, compagnie, cosa vorresti vedere…"
              required
            />
            {errors.message && (
              <p className="text-sm text-red-300">{errors.message}</p>
            )}
          </div>

          <div className="flex items-start gap-3">
            <Checkbox
              id="subscribeToNewsletter"
              checked={formData.subscribeToNewsletter}
              onCheckedChange={(checked) =>
                setFormData((prev) => ({
                  ...prev,
                  subscribeToNewsletter: checked as boolean,
                }))
              }
              className="mt-1 border-white/30 data-[state=checked]:bg-[var(--coral)] data-[state=checked]:border-[var(--coral)]"
            />
            <Label
              htmlFor="subscribeToNewsletter"
              className="text-sm font-normal text-white/60"
            >
              Aggiornamenti su PerX (opzionale)
            </Label>
          </div>

          <Button
            type="submit"
            className="bg-[var(--coral)] text-white hover:bg-[var(--coral-deep)]"
            disabled={isSubmitting}
          >
            {isSubmitting ? "Invio…" : "Invia"}
          </Button>

          <p className="text-xs text-white/40">
            I dati sono trattati per rispondere alla richiesta, nel rispetto del
            GDPR.
          </p>
        </form>
      </div>
    </section>
  );
};
