import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { getDocument } from "https://esm.sh/pdfjs-serverless";

const openAIApiKey = Deno.env.get('OPENAI_API_KEY');

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const AI_PROMPT = `Ruolo e obiettivo
Sei un estrattore di condizioni di polizza per il ramo Property. Ricevi il testo integrale (OCR) del PDF di una polizza e devi:
1. Individuare e riportare fedelmente (copiando testualmente) le Definizioni delle Partite (es. Fabbricato, Contenuto, Impianti, Macchinari, Elettronica…) e delle Garanzie (es. Fenomeno Elettrico, Acqua Condotta, Fenomeni Atmosferici, Furto, Incendio, RC, Cristalli).
2. Raccogliere Esclusioni comuni e Esclusioni specifiche.
3. Identificare Value Type (Primo Rischio Assoluto / Valore Intero), Deroga alla proporzionale, Determinazione del danno (A Nuovo, Con Supplemento, Massimo il Doppio/Triplo, a Stato d'Uso), Franchigia e Massimale per ogni Garanzia.
4. Evidenziare Note/condizioni particolari (franchigie dinamiche, limiti su singoli beni, ecc.).
5. Produrre un JSON di output che Bignami Online possa usare per creare Partite e Garanzie, oltre a eventuali limiti comuni e aggiornamenti di coverage.

Regole indispensabili
• Fedeltà testuale: per Definizioni ed Esclusioni riporta verbatim (stessa punteggiatura, maiuscole/minuscole). Non parafrasare.
• Cita sempre la posizione: per ogni definizione/valore indicare page_reference (es. "p. 7") ed eventualmente article_number (es. "Art. 12").
• Niente dati personali: ignora elementi sulla vita privata non rilevanti.
• Se un valore NON è nel PDF (Franchigia/Massimale), imposta "Su frontespizio" (flag logico come richiesto sotto). Non inventare numeri.
• Sinonimi → codici: mappa i nomi garanzia al relativo gruppo:
  - Fenomeno Elettrico → FE
  - Acqua Condotta → AC
  - Fenomeni Atmosferici → FA
  - Furto → FUR
  - Incendio → INC
  - Responsabilità Civile → RC
  - Cristalli → CR
• Partite (PartyType): mappa i nomi a questi identificatori (se compaiono nel PDF):
  - "Fabbricato" → fabbricato (emoji suggerita: 🏠)
  - "Contenuto" → contenuto (📦)
  - "Impianti/Impianti fissi/Elettrici" → impianti (⚡)
  - "Macchinari/Apparecchiature di produzione" → macchinari (🔧)
  - "Elettronica/Apparecchiature elettroniche" → elettronica (💻)
• Value Type ammessi:
  - valore_intero
  - primo_rischio_assoluto
  - primo_rischio_assoluto_fino_a (in tal caso valorizza anche primo_rischio_value, es. "€ 50.000,00").
• Determinazione del danno: elenco di stringhe tra:
  - A Nuovo, Con Supplemento, Massimo il Doppio, Massimo il Triplo, a Stato d'Uso (usa le voci presenti nel PDF).
• Formati:
  - Euro come € 1.500,00 (spazio dopo simbolo, punto per separare le migliaia e SEMPRE ",00").
  - Percentuali come 10%.
  - Quando una franchigia/massimale è assente → on_frontespizio = true e value = "Su frontespizio".
• Liste in array; testi compatibili con HTML base (il frontend supporta RichTextDisplay).

Restituisci esclusivamente un JSON con queste chiavi top-level (nessun testo fuori JSON):
{
  "coverage_updates": {
    "overview_text": "<breve inquadramento garanzie della polizza (max 400 battute, non obbligatorio se non presente)>",
    "definitions": ["<eventuale definizione generale, se presente, con tag <p>...>"],
    "common_exclusions": ["<esclusione comune verbatim>"],
    "common_interpretations": ["<eventuale>"],
    "common_notes": ["<eventuale>"],
    "value_type": "valore_intero | primo_rischio_assoluto | primo_rischio_assoluto_fino_a",
    "primo_rischio_value": "<es. € 50.000 o null>"
  },
  "common_limits_to_create": [
    {
      "label": "<etichetta limite comune>",
      "scope": "<ambito di applicazione>",
      "value": "<€ X / Y% / testuale / 'Su frontespizio'>",
      "on_frontespizio": true | false,
      "page_reference": "p. X",
      "article_number": "Art. Y"
    }
  ],
  "sections_to_create": [
    {
      "party": "fabbricato | contenuto | impianti | macchinari | elettronica",
      "exact_name": "<es. 'Fabbricato'>",
      "emoji": "🏠 | 📦 | ⚡ | 🔧 | 💻",
      "definition": "<testo verbatim in HTML semplice>",
      "definition_page_reference": "p. X",
      "definition_article_number": "Art. Y o stringa vuota se non presente",
      "exclusions": ["<esclusione comune alla partita - verbatim>"],
      "value_type": "valore_intero | primo_rischio_assoluto | primo_rischio_assoluto_fino_a",
      "primo_rischio_value": "<se PR fino a ...>",
      "deroga_percentage": 10,
      "determinazione": ["A Nuovo", "Con Supplemento", "Massimo il Doppio", "Massimo il Triplo", "a Stato d'Uso"],
      "notes": ["<eventuali note specifiche della partita>"]
    }
  ],
  "guarantees_to_create": [
    {
      "guarantee_name": "<es. 'Fenomeno Elettrico'>",
      "guarantee_group": "FE | AC | FA | FUR | INC | RC | CR",
      "exact_name": "<nome esatto dal PDF se diverso>",
      "description": "<definizione/ambito della garanzia in HTML semplice, se presente>",
      "value_type": "valore_intero | primo_rischio_assoluto | primo_rischio_assoluto_fino_a",
      "primo_rischio_value": "<se PR fino a ...>",
      "common_exclusions": ["<esclusioni comuni della garanzia - verbatim>"],
      "available_parties_refs": ["Fabbricato", "Contenuto", "Impianti", "..."],
      "order_index": 0,
      "maximum_value": "<'Su frontespizio' | '€ X' | 'Y% (min € A, max € B) - note'>",
      "maximum_applies_to": "<per sinistro | per anno | per evento | altro>",
      "maximum_page_reference": "p. X",
      "maximum_article_number": "Art. Y o ''",
      "deductible_value": "<'Su frontespizio' | '€ X' | 'Y% (min/max ...)' >",
      "deductible_applies_to": "<per sinistro | per evento | altro>",
      "deductible_page_reference": "p. X",
      "deductible_article_number": "Art. Y o ''",
      "guarantee_exclusions": ["<esclusioni specifiche della garanzia - verbatim>"],
      "exclusions_applies_to": "<tutte le partite | solo contenuto | solo elettronica | ...>",
      "exclusions_page_reference": "p. X",
      "exclusions_article_number": "Art. Y o ''"
    }
  ],
  "special_notes": ["<franchigie dinamiche, condizioni/deroghe particolari, limiti su singoli beni, rimandi ad allegati>"],
  "unresolved": {
    "frontespizio_flags_set": [
      {"field": "guarantees_to_create[i].maximum_value", "reason": "valore non presente nel PDF"}
    ],
    "ambiguous_text": [
      {"quote": "<testo ambiguo>", "pages": ["p. X","p. Y"], "why_ambiguous": "<spiega in 1 riga>"}
    ],
    "missing_fields": [
      {"path": "sections_to_create[0].deroga_percentage", "reason": "non indicata in polizza"}
    ]
  }
}`;

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { pdfUrl, chunkIndex, totalChunks } = await req.json();

    if (!pdfUrl) {
      return new Response(
        JSON.stringify({ error: 'URL del PDF è richiesto' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log('Processing PDF chunk:', chunkIndex, 'of', totalChunks);

    // Download the PDF
    const pdfResponse = await fetch(pdfUrl);
    if (!pdfResponse.ok) {
      throw new Error(`Failed to download PDF: ${pdfResponse.statusText}`);
    }

    const pdfBuffer = await pdfResponse.arrayBuffer();
    console.log('PDF downloaded, size:', pdfBuffer.byteLength);

    // Extract text from PDF using pdfjs-serverless
    const document = await getDocument({
      data: new Uint8Array(pdfBuffer),
      useSystemFonts: false,
    }).promise;

    // Process specific chunk
    const CHUNK_SIZE = 15;
    const startPage = (chunkIndex * CHUNK_SIZE) + 1;
    const endPage = Math.min(startPage + CHUNK_SIZE - 1, document.numPages);
    
    if (startPage > document.numPages) {
      return new Response(
        JSON.stringify({ 
          success: true, 
          chunk_index: chunkIndex,
          data: null,
          completed: true
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }
    
    let chunkText = '';
    for (let i = startPage; i <= endPage; i++) {
      const page = await document.getPage(i);
      const textContent = await page.getTextContent();
      const pageText = textContent.items.map((item: any) => item.str).join(' ');
      chunkText += `\n--- Pagina ${i} ---\n${pageText}\n`;
    }
    
    console.log(`Processing chunk ${chunkIndex + 1} (pages ${startPage}-${endPage}, ${chunkText.length} chars)`);
    
    // Use targeted prompt for this chunk
    const chunkPrompt = `Sei un estrattore di condizioni di polizza per il ramo Property. Analizza SOLO questo frammento del PDF (pagine ${startPage}-${endPage}) ed estrai:

1. Definizioni delle Partite e delle Garanzie (testo verbatim)
2. Esclusioni comuni e specifiche (testo verbatim)  
3. Valori di Franchigia e Massimale se presenti
4. Value Type se specificato
5. Note particolari

Restituisci SOLO un JSON con questa struttura:
{
  "chunk_info": {
    "start_page": ${startPage},
    "end_page": ${endPage}
  },
  "definitions": [{"type": "partita|garanzia", "name": "nome", "text": "definizione verbatim", "page": "p. X"}],
  "exclusions": [{"text": "esclusione verbatim", "page": "p. X", "scope": "comune|specifica"}],
  "values": [{"type": "massimale|franchigia", "value": "valore", "guarantee": "garanzia", "page": "p. X"}],
  "notes": [{"text": "nota", "page": "p. X"}],
  "value_types": [{"guarantee": "garanzia", "type": "valore_intero|primo_rischio_assoluto", "page": "p. X"}]
}`;

    const response = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openAIApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: [
          {
            role: 'system',
            content: chunkPrompt
          },
          {
            role: 'user',
            content: chunkText
          }
        ],
        max_tokens: 2000,
        temperature: 0.1
      }),
    });

    if (!response.ok) {
      const error = await response.json();
      console.error(`OpenAI API error for chunk ${chunkIndex + 1}:`, error);
      throw new Error(`Errore OpenAI per chunk ${chunkIndex + 1}: ${error.error?.message || 'Errore sconosciuto'}`);
    }

    const data = await response.json();
    const aiContent = data.choices[0].message.content;
    
    let chunkResult;
    try {
      const jsonMatch = aiContent.match(/```(?:json)?\s*(.*?)\s*```/s);
      const jsonString = jsonMatch ? jsonMatch[1] : aiContent;
      chunkResult = JSON.parse(jsonString);
      console.log(`Chunk ${chunkIndex + 1} processed successfully`);
    } catch (parseError) {
      console.error(`Failed to parse chunk ${chunkIndex + 1} response:`, parseError);
      throw new Error(`Errore nel parsing del chunk ${chunkIndex + 1}`);
    }

    return new Response(
      JSON.stringify({ 
        success: true,
        chunk_index: chunkIndex,
        total_chunks: Math.ceil(document.numPages / CHUNK_SIZE),
        data: chunkResult,
        completed: chunkIndex >= Math.ceil(document.numPages / CHUNK_SIZE) - 1
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );

  } catch (error) {
    console.error('Error in AI extract policy function:', error);
    return new Response(
      JSON.stringify({ 
        success: false, 
        error: error.message || 'Errore durante l\'analisi del PDF'
      }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});