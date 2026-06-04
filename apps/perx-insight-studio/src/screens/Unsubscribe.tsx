import { useEffect, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";

type Status = "loading" | "valid" | "already" | "invalid" | "success" | "error";

const Unsubscribe = () => {
  const [searchParams] = useSearchParams();
  const token = searchParams.get("token");
  const [status, setStatus] = useState<Status>("loading");

  useEffect(() => {
    if (!token) {
      setStatus("invalid");
      return;
    }

    const validate = async () => {
      try {
        const res = await fetch(
          `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/handle-email-unsubscribe?token=${token}`,
          { headers: { apikey: process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? "" } }
        );
        const data = await res.json();
        if (!res.ok) {
          setStatus("invalid");
        } else if (data.valid === false && data.reason === "already_unsubscribed") {
          setStatus("already");
        } else if (data.valid) {
          setStatus("valid");
        } else {
          setStatus("invalid");
        }
      } catch {
        setStatus("error");
      }
    };

    validate();
  }, [token]);

  const handleUnsubscribe = async () => {
    try {
      const { error } = await supabase.functions.invoke("handle-email-unsubscribe", {
        body: { token },
      });
      if (error) throw error;
      setStatus("success");
    } catch {
      setStatus("error");
    }
  };

  return (
    <div className="min-h-screen bg-background flex items-center justify-center p-6">
      <div className="max-w-md w-full text-center space-y-6">
        <h1 className="text-3xl font-bold bg-gradient-to-r from-primary to-secondary bg-clip-text text-transparent">
          PerX
        </h1>

        {status === "loading" && (
          <p className="text-muted-foreground">Verifica in corso...</p>
        )}

        {status === "valid" && (
          <div className="space-y-4">
            <p className="text-foreground">
              Vuoi cancellare la tua iscrizione alle email di PerX?
            </p>
            <button
              onClick={handleUnsubscribe}
              className="px-6 py-3 rounded-lg bg-destructive text-destructive-foreground font-medium hover:opacity-90 transition"
            >
              Conferma cancellazione
            </button>
          </div>
        )}

        {status === "success" && (
          <p className="text-foreground">
            ✅ La tua iscrizione è stata cancellata con successo. Non riceverai più email da PerX.
          </p>
        )}

        {status === "already" && (
          <p className="text-muted-foreground">
            La tua iscrizione è già stata cancellata in precedenza.
          </p>
        )}

        {status === "invalid" && (
          <p className="text-destructive">
            Link non valido o scaduto.
          </p>
        )}

        {status === "error" && (
          <p className="text-destructive">
            Si è verificato un errore. Riprova più tardi.
          </p>
        )}
      </div>
    </div>
  );
};

export default Unsubscribe;
