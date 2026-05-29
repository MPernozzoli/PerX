import "https://deno.land/x/xhr@0.1.0/mod.ts";
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.57.4';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabaseSchema = Deno.env.get('SUPABASE_DB_SCHEMA') || 'bignami';
    const supabase = createClient(supabaseUrl, supabaseServiceKey, {
      db: { schema: supabaseSchema },
    });

    const { searchText, redirectUrl } = await req.json();

    if (!searchText) {
      return new Response(
        JSON.stringify({ error: 'searchText is required' }),
        { 
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      );
    }

    console.log('Searching for policy:', searchText);

    // Parse the search text to extract components
    // Format example: "CATTOLICA - ACTIVE CASA&PERSONA Mod. ACTIVE C&P 2 Ed. 04/2021"
    const parts = searchText.split(' - ');
    let companyName = '';
    let policyInfo = '';
    
    if (parts.length >= 2) {
      companyName = parts[0].trim();
      policyInfo = parts.slice(1).join(' - ').trim();
    } else {
      policyInfo = searchText.trim();
    }

    // Extract edition/year from policy info (Ed. XX/XXXX format)
    const editionMatch = policyInfo.match(/Ed\.\s*(\d{2}\/\d{4})/);
    let editionYear = null;
    if (editionMatch) {
      const yearMatch = editionMatch[1].match(/\d{4}/);
      if (yearMatch) {
        editionYear = parseInt(yearMatch[0]);
      }
    }

    // Build query
    let query = supabase
      .from('policies')
      .select(`
        *,
        companies!inner(*),
        policy_editions!inner(*)
      `);

    // Search by company name if provided
    if (companyName) {
      query = query.or(`companies.name.ilike.%${companyName}%,companies.aliases.cs.{${companyName.toLowerCase()}}`);
    }

    // Search by policy name in the remaining text
    const policyNamePart = policyInfo.replace(/Ed\.\s*\d{2}\/\d{4}/, '').trim();
    if (policyNamePart) {
      query = query.ilike('name', `%${policyNamePart}%`);
    }

    // Filter by edition year if found
    if (editionYear) {
      query = query.eq('policy_editions.year', editionYear);
    }

    // Only published editions
    query = query.eq('policy_editions.status', 'published');

    const { data: policies, error } = await query.limit(1);

    if (error) {
      console.error('Database error:', error);
      return new Response(
        JSON.stringify({ error: 'Database error' }),
        { 
          status: 500,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      );
    }

    if (!policies || policies.length === 0) {
      console.log('No policy found for:', searchText);
      return new Response(
        JSON.stringify({ error: 'Policy not found' }),
        { 
          status: 404,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        }
      );
    }

    const policy = policies[0];
    const edition = policy.policy_editions[0];
    
    // Construct the URL
    const baseUrl = redirectUrl || `https://${req.headers.get('host')}`;
    const policyUrl = `${baseUrl}/policy/${policy.id}/edition/${edition.id}`;

    console.log('Found policy:', policy.name, 'Edition:', edition.year, 'URL:', policyUrl);

    // Return the URL or redirect directly
    if (req.url.includes('redirect=true')) {
      return new Response(null, {
        status: 302,
        headers: {
          ...corsHeaders,
          'Location': policyUrl
        }
      });
    }

    return new Response(
      JSON.stringify({ 
        policyUrl,
        policy: {
          id: policy.id,
          name: policy.name,
          company: policy.companies.name,
          edition: {
            id: edition.id,
            year: edition.year,
            label: edition.edition_label
          }
        }
      }),
      { 
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    );

  } catch (error) {
    console.error('Error in find-policy function:', error);
    return new Response(
      JSON.stringify({ error: error.message }),
      { 
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      }
    );
  }
});
