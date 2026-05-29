import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.57.4';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const openAIApiKey = Deno.env.get('OPENAI_API_KEY')!;

    const supabaseSchema = Deno.env.get('SUPABASE_DB_SCHEMA') || 'bignami';
    const supabase = createClient(supabaseUrl, supabaseServiceKey, {
      db: { schema: supabaseSchema },
    });

    const { importId } = await req.json();

    console.log('Processing import:', importId);

    // Get import record
    const { data: importRecord, error: importError } = await supabase
      .from('bulk_imports')
      .select('*')
      .eq('id', importId)
      .single();

    if (importError || !importRecord) {
      throw new Error('Import record not found');
    }

    // Update status to processing
    await supabase
      .from('bulk_imports')
      .update({ status: 'processing' })
      .eq('id', importId);

    // Download the Excel file
    console.log('Downloading file from:', importRecord.file_url);
    const fileResponse = await fetch(importRecord.file_url);
    
    if (!fileResponse.ok) {
      throw new Error(`Failed to download file: ${fileResponse.statusText}`);
    }

    const fileBuffer = await fileResponse.arrayBuffer();
    const fileBase64 = btoa(String.fromCharCode(...new Uint8Array(fileBuffer)));

    // Use OpenAI to analyze the Excel file
    console.log('Analyzing Excel file with OpenAI...');
    const analysisResponse = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openAIApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'gpt-4o',
        messages: [
          {
            role: 'system',
            content: `Sei un esperto nell'analisi di file Excel contenenti dati di polizze assicurative.
            Analizza il file Excel e estrai le seguenti informazioni per ogni polizza:
            - Nome della compagnia
            - Nome della polizza
            - Tipo di polizza
            - Descrizione
            - Anno/edizione
            - Sezioni/coperture disponibili
            - Garanzie e limiti
            
            Restituisci una struttura JSON con:
            {
              "companies": [
                {
                  "name": "Nome Compagnia",
                  "code": "CODICE_COMPAGNIA",
                  "policies": [
                    {
                      "name": "Nome Polizza",
                      "type": "Tipo",
                      "description": "Descrizione",
                      "year": 2024,
                      "sections": [...],
                      "coverages": [...]
                    }
                  ]
                }
              ],
              "summary": {
                "total_companies": 0,
                "total_policies": 0,
                "analysis_notes": "Note sull'analisi"
              }
            }`
          },
          {
            role: 'user',
            content: `Analizza questo file Excel contenente polizze assicurative e fornismi la struttura dati estratta. 
            Il file è in base64: data:application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;base64,${fileBase64.slice(0, 100000)}`
          }
        ],
        max_tokens: 4000,
        temperature: 0.1
      }),
    });

    const analysisData = await analysisResponse.json();
    
    if (!analysisData.choices?.[0]?.message?.content) {
      throw new Error('Failed to get AI analysis');
    }

    let aiAnalysis;
    try {
      aiAnalysis = JSON.parse(analysisData.choices[0].message.content);
    } catch (parseError) {
      // If JSON parsing fails, store the raw response
      aiAnalysis = {
        raw_response: analysisData.choices[0].message.content,
        error: 'Failed to parse AI response as JSON'
      };
    }

    console.log('AI Analysis completed:', aiAnalysis);

    // Store analysis and update import record
    await supabase
      .from('bulk_imports')
      .update({
        status: 'completed',
        ai_analysis: aiAnalysis,
        processed_at: new Date().toISOString(),
        imported_policies_count: aiAnalysis.summary?.total_policies || 0
      })
      .eq('id', importId);

    // TODO: Here you would implement the actual import of policies into the database
    // based on the AI analysis. For now, we just store the analysis.

    console.log('Import processing completed successfully');

    return new Response(
      JSON.stringify({ 
        success: true, 
        analysis: aiAnalysis,
        message: 'Import processed successfully'
      }),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200 
      }
    );

  } catch (error) {
    console.error('Error processing import:', error);

    // Update import record with error
    if (req.body) {
      try {
        const { importId } = await req.json();
        const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
        const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
        const supabaseSchema = Deno.env.get('SUPABASE_DB_SCHEMA') || 'bignami';
        const supabase = createClient(supabaseUrl, supabaseServiceKey, {
          db: { schema: supabaseSchema },
        });

        await supabase
          .from('bulk_imports')
          .update({
            status: 'failed',
            error_message: error.message,
            processed_at: new Date().toISOString()
          })
          .eq('id', importId);
      } catch (updateError) {
        console.error('Failed to update import record with error:', updateError);
      }
    }

    return new Response(
      JSON.stringify({ 
        success: false, 
        error: error.message 
      }),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500 
      }
    );
  }
});
