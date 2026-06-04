import { useState } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

export interface AIExtractedData {
  coverage_updates: {
    overview_text?: string;
    definitions?: string[];
    common_exclusions?: string[];
    common_interpretations?: string[];
    common_notes?: string[];
    value_type?: 'valore_intero' | 'primo_rischio_assoluto' | 'primo_rischio_assoluto_fino_a';
    primo_rischio_value?: string;
  };
  common_limits_to_create: Array<{
    label: string;
    scope: string;
    value: string;
    on_frontespizio: boolean;
    page_reference?: string;
    article_number?: string;
  }>;
  sections_to_create: Array<{
    party: 'fabbricato' | 'contenuto' | 'impianti' | 'macchinari' | 'elettronica';
    exact_name: string;
    emoji: string;
    definition: string;
    definition_page_reference?: string;
    definition_article_number?: string;
    exclusions?: string[];
    value_type?: 'valore_intero' | 'primo_rischio_assoluto' | 'primo_rischio_assoluto_fino_a';
    primo_rischio_value?: string;
    deroga_percentage?: number;
    determinazione?: string[];
    notes?: string[];
  }>;
  guarantees_to_create: Array<{
    guarantee_name: string;
    guarantee_group: 'FE' | 'AC' | 'FA' | 'FUR' | 'INC' | 'RC' | 'CR';
    exact_name?: string;
    description?: string;
    value_type?: 'valore_intero' | 'primo_rischio_assoluto' | 'primo_rischio_assoluto_fino_a';
    primo_rischio_value?: string;
    common_exclusions?: string[];
    available_parties_refs?: string[];
    order_index: number;
    maximum_value?: string;
    maximum_applies_to?: string;
    maximum_page_reference?: string;
    maximum_article_number?: string;
    deductible_value?: string;
    deductible_applies_to?: string;
    deductible_page_reference?: string;
    deductible_article_number?: string;
    guarantee_exclusions?: string[];
    exclusions_applies_to?: string;
    exclusions_page_reference?: string;
    exclusions_article_number?: string;
  }>;
  special_notes?: string[];
  unresolved?: {
    frontespizio_flags_set?: Array<{field: string; reason: string}>;
    ambiguous_text?: Array<{quote: string; pages: string[]; why_ambiguous: string}>;
    missing_fields?: Array<{path: string; reason: string}>;
  };
}

export interface AIExtractedChunk {
  chunk_info: {
    start_page: number;
    end_page: number;
  };
  definitions?: Array<{
    type: 'partita' | 'garanzia';
    name: string;
    text: string;
    page: string;
  }>;
  exclusions?: Array<{
    text: string;
    page: string;
    scope: 'comune' | 'specifica';
  }>;
  values?: Array<{
    type: 'massimale' | 'franchigia';
    value: string;
    guarantee: string;
    page: string;
  }>;
  notes?: Array<{
    text: string;
    page: string;
  }>;
  value_types?: Array<{
    guarantee: string;
    type: 'valore_intero' | 'primo_rischio_assoluto';
    page: string;
  }>;
}

export interface AIChunkResult {
  success: boolean;
  chunk_index: number;
  total_chunks: number;
  data?: AIExtractedChunk;
  completed: boolean;
  error?: string;
}

export interface AIProgressCallback {
  (progress: {
    current: number;
    total: number;
    chunk?: AIExtractedChunk;
    completed: boolean;
  }): void;
}

export interface AIExtractResult {
  success: boolean;
  data?: AIExtractedData;
  error?: string;
  raw_response?: string;
}

export const useAIExtractPolicy = () => {
  const [extracting, setExtracting] = useState(false);
  const [progress, setProgress] = useState({ current: 0, total: 0 });
  const [partialData, setPartialData] = useState<AIExtractedData | null>(null);
  const [currentChunk, setCurrentChunk] = useState<string>('');

  const extractFromPDFWithProgress = async (
    pdfUrl: string, 
    onProgress?: AIProgressCallback
  ): Promise<AIExtractResult> => {
    if (!pdfUrl) {
      toast.error('URL del PDF non disponibile');
      return { success: false, error: 'URL del PDF non disponibile' };
    }

    setExtracting(true);
    setProgress({ current: 0, total: 0 });
    setPartialData(null);
    setCurrentChunk('Inizializzazione...');

    try {
      console.log('Starting progressive AI extract for PDF:', pdfUrl);

      // First call to get total chunks
      const { data: firstChunk, error: firstError } = await supabase.functions.invoke('ai-extract-policy', {
        body: { pdfUrl, chunkIndex: 0 }
      });

      if (firstError) {
        console.error('Supabase function error:', firstError);
        throw firstError;
      }

      if (!firstChunk?.success) {
        throw new Error(firstChunk?.error || 'Errore durante l\'estrazione del primo chunk');
      }

      const totalChunks = firstChunk.total_chunks;
      setProgress({ current: 1, total: totalChunks });
      setCurrentChunk(`Elaborando chunk 1/${totalChunks}`);
      onProgress?.({ current: 1, total: totalChunks, chunk: firstChunk.data, completed: false });

      const allChunks: AIExtractedChunk[] = [firstChunk.data];

      // Process remaining chunks
      for (let i = 1; i < totalChunks; i++) {
        console.log(`Processing chunk ${i + 1}/${totalChunks}`);
        
        const { data: chunkData, error: chunkError } = await supabase.functions.invoke('ai-extract-policy', {
          body: { pdfUrl, chunkIndex: i }
        });

        if (chunkError) {
          console.error(`Errore chunk ${i + 1}:`, chunkError);
          continue; // Skip this chunk but continue
        }

        if (chunkData?.success && chunkData.data) {
          allChunks.push(chunkData.data);
          setProgress({ current: i + 1, total: totalChunks });
          setCurrentChunk(`Elaborando chunk ${i + 1}/${totalChunks}`);
          onProgress?.({ 
            current: i + 1, 
            total: totalChunks, 
            chunk: chunkData.data, 
            completed: i === totalChunks - 1 
          });
        }
      }

      // Initialize aggregated result
      const aggregatedResult: AIExtractedData = {
        coverage_updates: {
          overview_text: "Analisi aggregata da PDF multi-chunk",
          definitions: [],
          common_exclusions: [],
          common_interpretations: [],
          common_notes: [],
          value_type: "valore_intero",
          primo_rischio_value: null
        },
        common_limits_to_create: [],
        sections_to_create: [],
        guarantees_to_create: [],
        special_notes: [],
        unresolved: {
          frontespizio_flags_set: [],
          ambiguous_text: [],
          missing_fields: []
        }
      };

      // Process and aggregate all chunks progressively
      allChunks.forEach((chunk, index) => {
        setCurrentChunk(`Aggregando chunk ${index + 1}/${allChunks.length}`);
        
        if (chunk.definitions) {
          chunk.definitions.forEach(def => {
            aggregatedResult.coverage_updates.definitions.push(`<p>${def.text} (${def.page})</p>`);
            
            // Create sections from definitions
            if (def.type === 'partita') {
              aggregatedResult.sections_to_create.push({
                party: 'fabbricato',
                exact_name: def.name,
                emoji: '🏠',
                definition: `<p>${def.text}</p>`,
                definition_page_reference: def.page,
                value_type: 'valore_intero',
                deroga_percentage: 10,
                determinazione: ['A Nuovo'],
                notes: []
              });
            }
            
            // Create guarantees from definitions
            if (def.type === 'garanzia') {
              const guaranteeGroup = def.name.toLowerCase().includes('incendio') ? 'INC' :
                                   def.name.toLowerCase().includes('furto') ? 'FUR' :
                                   def.name.toLowerCase().includes('cristalli') ? 'CR' :
                                   def.name.toLowerCase().includes('acqua') ? 'AC' :
                                   def.name.toLowerCase().includes('elettrico') ? 'FE' :
                                   def.name.toLowerCase().includes('atmosfer') ? 'FA' :
                                   def.name.toLowerCase().includes('responsabilità') ? 'RC' : 'INC';
                                   
              aggregatedResult.guarantees_to_create.push({
                guarantee_name: def.name,
                guarantee_group: guaranteeGroup as any,
                description: `<p>${def.text}</p>`,
                order_index: aggregatedResult.guarantees_to_create.length,
                maximum_value: 'Su frontespizio',
                maximum_applies_to: 'per sinistro',
                deductible_value: 'Su frontespizio',
                deductible_applies_to: 'per sinistro',
                available_parties_refs: [],
                common_exclusions: [],
                guarantee_exclusions: []
              });
            }
          });
        }
        
        if (chunk.exclusions) {
          chunk.exclusions.forEach(exc => {
            aggregatedResult.coverage_updates.common_exclusions.push(`${exc.text} (${exc.page})`);
          });
        }
        
        if (chunk.values) {
          chunk.values.forEach(val => {
            if (val.type === 'massimale' || val.type === 'franchigia') {
              aggregatedResult.common_limits_to_create.push({
                label: `${val.type === 'massimale' ? 'Massimale' : 'Franchigia'} ${val.guarantee}`,
                scope: val.guarantee,
                value: val.value,
                on_frontespizio: val.value.toLowerCase().includes('frontespizio'),
                page_reference: val.page
              });
            }
          });
        }
        
        if (chunk.notes) {
          chunk.notes.forEach(note => {
            aggregatedResult.special_notes.push(`${note.text} (${note.page})`);
          });
        }
        
        // Update partial data after each chunk
        setPartialData({...aggregatedResult});
      });

      console.log('AI extraction completed successfully with', allChunks.length, 'chunks');
      onProgress?.({ current: totalChunks, total: totalChunks, completed: true });

      return {
        success: true,
        data: aggregatedResult
      };

    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Errore durante l\'estrazione dei dati';
      console.error('AI extraction error:', error);
      toast.error(errorMessage);
      return {
        success: false,
        error: errorMessage
      };
    } finally {
      setExtracting(false);
      setCurrentChunk('');
    }
  };

  const extractFromPDF = async (pdfUrl: string): Promise<AIExtractResult> => {
    return extractFromPDFWithProgress(pdfUrl);
  };

  return {
    extractFromPDF,
    extractFromPDFWithProgress,
    extracting,
    progress,
    partialData,
    currentChunk
  };
};