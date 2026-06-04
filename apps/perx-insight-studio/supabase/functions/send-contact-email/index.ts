import { serve } from "https://deno.land/std@0.190.0/http/server.ts";
import { Resend } from "https://esm.sh/resend@4.0.0";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

const resend = new Resend(Deno.env.get("RESEND_API_KEY"));
const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const supabase = createClient(supabaseUrl, supabaseServiceKey);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface ContactEmailRequest {
  name: string;
  email: string;
  company?: string;
  message: string;
  subscribeToNewsletter?: boolean;
}

const handler = async (req: Request): Promise<Response> => {
  // Handle CORS preflight requests
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { name, email, company, message, subscribeToNewsletter }: ContactEmailRequest = await req.json();

    console.log("Received contact request from:", email);

    // Save to newsletter if user subscribed
    if (subscribeToNewsletter) {
      const { error: dbError } = await supabase
        .from("newsletter_subscribers")
        .insert([{ 
          email, 
          name,
          company: company || null
        }])
        .select();
      
      if (dbError) {
        // Log but don't fail if duplicate email or other db error
        console.log("Newsletter subscription note:", dbError.message);
      } else {
        console.log("Successfully added to newsletter:", email);
      }
    }

    // Send confirmation email to the user
    const userEmailResponse = await resend.emails.send({
      from: "PerX <info@perx.it>",
      to: [email],
      subject: "Grazie per il tuo interesse in PerX",
      html: `
        <!DOCTYPE html>
        <html>
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
          </head>
          <body style="margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; background-color: #0f1219;">
            <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #0f1219; padding: 40px 20px;">
              <tr>
                <td align="center">
                  <!-- Main container -->
                  <table width="600" cellpadding="0" cellspacing="0" style="max-width: 600px; background: linear-gradient(135deg, #1a1f3a 0%, #2a1539 100%); border-radius: 24px; overflow: hidden; box-shadow: 0 20px 60px rgba(0,0,0,0.5);">
                    
                    <!-- Gradient header -->
                    <tr>
                      <td style="background: linear-gradient(135deg, #ff69b4 0%, #9747d8 50%, #ff9933 100%); padding: 0; height: 6px;"></td>
                    </tr>
                    
                    <!-- Logo/Brand section -->
                    <tr>
                      <td style="padding: 40px 40px 30px 40px; text-align: center; background: linear-gradient(180deg, rgba(255,105,180,0.08) 0%, transparent 100%);">
                        <h1 style="margin: 0; color: #ffffff; font-size: 42px; font-weight: 800; letter-spacing: -1px; text-shadow: 0 4px 20px rgba(255,105,180,0.4);">PerX</h1>
                        <div style="margin-top: 8px; height: 3px; width: 60px; background: linear-gradient(90deg, #ff69b4, #9747d8); margin-left: auto; margin-right: auto; border-radius: 3px;"></div>
                      </td>
                    </tr>
                    
                    <!-- Main content -->
                    <tr>
                      <td style="padding: 0 40px 40px 40px; color: #fafafa;">
                        <h2 style="margin: 0 0 24px 0; color: #ffffff; font-size: 26px; font-weight: 700; line-height: 1.3;">
                          Ciao ${name}! 👋
                        </h2>
                        
                        <p style="margin: 0 0 20px 0; color: #e5e7eb; font-size: 16px; line-height: 1.7;">
                          Grazie per averci contattato e per l'interesse dimostrato verso <strong style="background: linear-gradient(90deg, #ff69b4, #9747d8); -webkit-background-clip: text; -webkit-text-fill-color: transparent; background-clip: text; font-weight: 700;">PerX</strong>.
                        </p>
                        
                        <p style="margin: 0 0 32px 0; color: #d1d5db; font-size: 16px; line-height: 1.7;">
                          Abbiamo ricevuto la tua richiesta e ti contatteremo al più presto per fornirti tutte le informazioni di cui hai bisogno.
                        </p>
                        
                        ${company ? `
                        <div style="background: linear-gradient(135deg, rgba(255,105,180,0.15) 0%, rgba(151,71,216,0.15) 100%); border-left: 4px solid #ff69b4; padding: 20px 24px; margin: 0 0 24px 0; border-radius: 12px; backdrop-filter: blur(10px);">
                          <p style="margin: 0; color: #ffffff; font-size: 15px; line-height: 1.6;">
                            <strong style="color: #ff69b4; font-weight: 600;">Studio/Azienda:</strong><br/>
                            <span style="font-size: 16px; font-weight: 500; margin-top: 4px; display: inline-block;">${company}</span>
                          </p>
                        </div>
                        ` : ''}
                        
                        <!-- Message box -->
                        <div style="background: linear-gradient(135deg, rgba(151,71,216,0.2) 0%, rgba(255,105,180,0.1) 100%); border-radius: 16px; padding: 24px; margin: 0 0 32px 0; border: 1px solid rgba(151,71,216,0.3); box-shadow: inset 0 2px 10px rgba(0,0,0,0.2);">
                          <p style="margin: 0 0 12px 0; color: #c4b5fd; font-size: 13px; font-weight: 700; text-transform: uppercase; letter-spacing: 1.5px;">
                            📩 Il tuo messaggio
                          </p>
                          <p style="margin: 0; color: #f3f4f6; font-size: 15px; line-height: 1.7; font-style: italic;">
                            "${message}"
                          </p>
                        </div>
                        
                        <!-- Signature -->
                        <div style="padding-top: 24px; border-top: 1px solid rgba(255,255,255,0.1);">
                          <p style="margin: 0 0 8px 0; color: #9ca3af; font-size: 15px;">
                            A presto,
                          </p>
                          <p style="margin: 0; font-size: 18px; font-weight: 700;">
                            <span style="background: linear-gradient(90deg, #ff69b4 0%, #9747d8 50%, #ff9933 100%); -webkit-background-clip: text; -webkit-text-fill-color: transparent; background-clip: text;">
                              Il Team PerX
                            </span>
                          </p>
                          <p style="margin: 4px 0 0 0; color: #6b7280; font-size: 14px; font-weight: 500;">
                            PynkStudio
                          </p>
                        </div>
                      </td>
                    </tr>
                    
                    <!-- Footer -->
                    <tr>
                      <td style="background: rgba(0,0,0,0.3); padding: 28px 40px; text-align: center; border-top: 1px solid rgba(255,255,255,0.08);">
                        <p style="margin: 0 0 8px 0; color: #6b7280; font-size: 13px; line-height: 1.6;">
                          © 2025 PerX by PynkStudio
                        </p>
                        <p style="margin: 0; color: #4b5563; font-size: 12px;">
                          Tutti i diritti riservati
                        </p>
                      </td>
                    </tr>
                    
                  </table>
                </td>
              </tr>
            </table>
          </body>
        </html>
      `,
    });

    console.log("User confirmation email sent:", userEmailResponse);

    // Send notification email to PerX team
    const teamEmailResponse = await resend.emails.send({
      from: "PerX Contact Form <info@perx.it>",
      to: ["info@perx.it"],
      subject: `Nuova richiesta informazioni PerX da ${name}`,
      html: `
        <h2>Nuova richiesta di contatto da PerX.it</h2>
        <p><strong>Nome:</strong> ${name}</p>
        <p><strong>Email:</strong> ${email}</p>
        ${company ? `<p><strong>Studio/Azienda:</strong> ${company}</p>` : ''}
        <p><strong>Messaggio:</strong></p>
        <p style="background: #f5f5f5; padding: 15px; border-radius: 8px;">${message}</p>
      `,
    });

    console.log("Team notification email sent:", teamEmailResponse);

    return new Response(
      JSON.stringify({ 
        success: true,
        userEmail: userEmailResponse,
        teamEmail: teamEmailResponse 
      }),
      {
        status: 200,
        headers: {
          "Content-Type": "application/json",
          ...corsHeaders,
        },
      }
    );
  } catch (error: any) {
    console.error("Error in send-contact-email function:", error);
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        status: 500,
        headers: { "Content-Type": "application/json", ...corsHeaders },
      }
    );
  }
};

serve(handler);
