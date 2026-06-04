import { useState, useRef, useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { toast } from 'sonner';
import { FileSpreadsheet, Download, ArrowLeft, Check, AlertTriangle, Link2, Search, ChevronsUpDown } from 'lucide-react';
import { getProvinceName, getProvinceCode } from '@/lib/textUtils';
import { Progress } from '@/components/ui/progress';
import Papa from 'papaparse';
import { Card } from '@/components/ui/card';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from '@/components/ui/dialog';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Popover, PopoverContent, PopoverTrigger } from '@/components/ui/popover';
import { Command, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from '@/components/ui/command';

interface CSVRow {
  [key: string]: string | undefined;
}

interface ParsedRow {
  raw: CSVRow;
  mapped: {
    quartiere?: string;
    comune?: string;
    provincia?: string;
    cat1?: string;
    cat2?: string;
    cat3?: string;
    note?: string;
    intervention_type?: string;
  };
  errors: string[];
}

type ColumnMapping = {
  [key: string]: 'quartiere' | 'comune' | 'provincia' | 'cat1' | 'cat2' | 'cat3' | 'note' | 'intervention_type' | 'ignore';
};

// Tipi di intervento disponibili
const INTERVENTION_TYPES = [
  { value: 'sopralluogo', label: 'Sopralluogo' },
  { value: 'rfs', label: 'RFS' },
  { value: 'both', label: 'Entrambi' },
] as const;

type InterventionType = 'sopralluogo' | 'rfs' | 'both';

interface CATFromDB {
  id: string;
  name: string;
}

interface CommuneFromDB {
  id: string;
  comune: string;
  provincia: string;
  provincia_nome: string | null;
}

// Chiavi localStorage per salvare le mappature
const CAT_MAPPING_STORAGE_KEY = 'cat_import_name_mappings';
const COMMUNE_MAPPING_STORAGE_KEY = 'cat_import_commune_mappings';

// Normalizza il nome per il confronto (rimuove accenti, punteggiatura, spazi extra)
const normalizeName = (name: string): string => {
  return name
    .toLowerCase()
    .trim()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '') // Rimuove accenti
    .replace(/\s+/g, ' ')
    .replace(/[^\w\s]/g, '');
};

// Verifica se un valore CAT indica "Non Disponibile" (N/D, ND, n.d., ecc.)
const isNoCatValue = (value: string | undefined): boolean => {
  if (!value) return false;
  const normalized = value.trim().toLowerCase().replace(/[.\-\/\\]/g, '');
  return normalized === 'nd' || normalized === 'na' || normalized === 'nessuno';
};

// Carica le mappature CAT salvate
const loadSavedCatMappings = (): Record<string, string> => {
  try {
    const saved = localStorage.getItem(CAT_MAPPING_STORAGE_KEY);
    return saved ? JSON.parse(saved) : {};
  } catch {
    return {};
  }
};

// Salva una mappatura CAT
const saveCatMappingToStorage = (csvName: string, catId: string) => {
  const mappings = loadSavedCatMappings();
  mappings[normalizeName(csvName)] = catId;
  localStorage.setItem(CAT_MAPPING_STORAGE_KEY, JSON.stringify(mappings));
};

// Carica le mappature comuni salvate
const loadSavedCommuneMappings = (): Record<string, string> => {
  try {
    const saved = localStorage.getItem(COMMUNE_MAPPING_STORAGE_KEY);
    return saved ? JSON.parse(saved) : {};
  } catch {
    return {};
  }
};

// Salva una mappatura comune (chiave: "nomeCsv|provincia" -> communeId)
const saveCommuneMappingToStorage = (csvName: string, provincia: string, communeId: string) => {
  const mappings = loadSavedCommuneMappings();
  const key = `${normalizeName(csvName)}|${provincia.toLowerCase()}`;
  mappings[key] = communeId;
  localStorage.setItem(COMMUNE_MAPPING_STORAGE_KEY, JSON.stringify(mappings));
};

const CATImport = () => {
  const [file, setFile] = useState<File | null>(null);
  const [isProcessing, setIsProcessing] = useState(false);
  const [progress, setProgress] = useState(0);
  const [currentRow, setCurrentRow] = useState('');
  const [stats, setStats] = useState({ processed: 0, success: 0, errors: 0 });
  const fileInputRef = useRef<HTMLInputElement>(null);
  
  // New states for preview
  const [showPreview, setShowPreview] = useState(false);
  const [parsedData, setParsedData] = useState<ParsedRow[]>([]);
  const [columnMapping, setColumnMapping] = useState<ColumnMapping>({});
  const [availableColumns, setAvailableColumns] = useState<string[]>([]);

  // CAT dal database e mappature
  const [allCats, setAllCats] = useState<CATFromDB[]>([]);
  const [showCatMappingDialog, setShowCatMappingDialog] = useState(false);
  const [unmappedCatNames, setUnmappedCatNames] = useState<string[]>([]);
  const [catNameMappings, setCatNameMappings] = useState<Record<string, string>>({});

  // Comuni dal database e mappature
  const [allCommunes, setAllCommunes] = useState<CommuneFromDB[]>([]);
  const [showCommuneMappingDialog, setShowCommuneMappingDialog] = useState(false);
  const [unmappedCommunes, setUnmappedCommunes] = useState<{ comune: string; provincia: string }[]>([]);
  const [communeMappings, setCommuneMappings] = useState<Record<string, string>>({});

  // Filtri di ricerca per le modali di mappatura
  const [catSearchFilter, setCatSearchFilter] = useState('');
  const [communeSearchFilter, setCommuneSearchFilter] = useState('');

  // Tipo di intervento globale (quando non c'è colonna nel CSV)
  const [globalInterventionType, setGlobalInterventionType] = useState<InterventionType>('both');
  const [showInterventionTypeDialog, setShowInterventionTypeDialog] = useState(false);

  // Stato per tracciare quale combobox è aperto
  const [openCommuneCombobox, setOpenCommuneCombobox] = useState<string | null>(null);
  const [openCatCombobox, setOpenCatCombobox] = useState<string | null>(null);

  // Carica tutti i CAT e Comuni dal database all'avvio
  useEffect(() => {
    const loadData = async () => {
      // Carica CAT
      const { data: catsData, error: catsError } = await supabase
        .from('cats')
        .select('id, name')
        .order('name');
      
      if (!catsError && catsData) {
        setAllCats(catsData);
      }

      // Carica Comuni - in batch per superare il limite di 1000
      let allCommunesData: CommuneFromDB[] = [];
      let from = 0;
      const batchSize = 1000;
      let hasMore = true;
      
      while (hasMore) {
        const { data: batchData, error: batchError } = await supabase
          .from('communes')
          .select('id, comune, provincia, provincia_nome')
          .order('comune')
          .range(from, from + batchSize - 1);
        
        if (batchError) {
          console.error('[CATImport] Errore caricamento comuni batch:', batchError);
          break;
        }
        
        if (batchData && batchData.length > 0) {
          allCommunesData = [...allCommunesData, ...batchData];
          from += batchSize;
          hasMore = batchData.length === batchSize;
        } else {
          hasMore = false;
        }
      }
      
      if (allCommunesData.length > 0) {
        setAllCommunes(allCommunesData);
        // Debug dettagliato
        const toCommunesCount = allCommunesData.filter(c => c.provincia === 'TO').length;
        const torinoCommunesCount = allCommunesData.filter(c => c.provincia === 'Torino').length;
        console.log(`[CATImport] Caricati ${allCommunesData.length} comuni in batch`);
        console.log(`[CATImport] Comuni con provincia='TO': ${toCommunesCount}, provincia='Torino': ${torinoCommunesCount}`);
      }
    };
    loadData();
  }, []);

  // Cerca un CAT per nome, usando mappature salvate e match flessibile
  const findCatByName = (csvName: string, sessionMappings: Record<string, string>): CATFromDB | null => {
    if (!csvName) return null;
    
    const normalizedInput = normalizeName(csvName);
    const savedMappings = loadSavedCatMappings();
    
    // 1. Prima controlla le mappature della sessione corrente (chiavi sono nomi originali)
    if (sessionMappings[csvName]) {
      const cat = allCats.find(c => c.id === sessionMappings[csvName]);
      if (cat) return cat;
    }
    
    // 2. Poi controlla le mappature salvate in localStorage (chiavi normalizzate)
    if (savedMappings[normalizedInput]) {
      const cat = allCats.find(c => c.id === savedMappings[normalizedInput]);
      if (cat) return cat;
    }
    
    // 3. Match esatto case-insensitive
    const exactMatch = allCats.find(c => 
      normalizeName(c.name) === normalizedInput
    );
    if (exactMatch) return exactMatch;
    
    // 4. Match parziale - il nome CSV è contenuto nel nome CAT o viceversa
    const partialMatch = allCats.find(c => {
      const normalizedCat = normalizeName(c.name);
      return normalizedCat.includes(normalizedInput) || normalizedInput.includes(normalizedCat);
    });
    if (partialMatch) return partialMatch;
    
    return null;
  };

  // Pre-verifica tutti i nomi CAT nel CSV e identifica quelli non mappabili
  const preCheckCatNames = async (): Promise<{ unmapped: string[], mapped: Record<string, string> }> => {
    if (!file) return { unmapped: [], mapped: {} };
    
    const text = await file.text();
    const results = Papa.parse<CSVRow>(text, { header: true, skipEmptyLines: true });
    
    const allCatNames = new Set<string>();
    const mapped: Record<string, string> = {};
    const unmapped: string[] = [];
    
    // Raccogli tutti i nomi CAT unici (escludendo N/D)
    results.data.forEach(row => {
      Object.keys(columnMapping).forEach(col => {
        const target = columnMapping[col];
        const value = row[col]?.trim();
        if ((target === 'cat1' || target === 'cat2' || target === 'cat3') && value && !isNoCatValue(value)) {
          allCatNames.add(value);
        }
      });
    });
    
    // Verifica quali sono mappabili
    allCatNames.forEach(name => {
      const cat = findCatByName(name, catNameMappings);
      if (cat) {
        mapped[normalizeName(name)] = cat.id;
      } else {
        unmapped.push(name);
      }
    });
    
    return { unmapped, mapped };
  };

  // Verifica se la provincia del comune matcha quella cercata (supporta sigle e nomi completi)
  // Usa PROVINCE_MAP per convertire tra sigle e nomi
  const matchesProvincia = (commune: CommuneFromDB, searchProvincia: string, _strict: boolean = true): boolean => {
    if (!searchProvincia) return false;
    
    const searchUpper = searchProvincia.toUpperCase().trim();
    
    // Determina se la ricerca è una sigla o un nome completo
    const isSearchCode = searchUpper.length <= 3;
    
    // Converti la ricerca in entrambi i formati (sigla e nome, tutto lowercase per confronto)
    const searchAsCode = isSearchCode ? searchUpper : getProvinceCode(searchProvincia);
    const searchAsName = isSearchCode ? getProvinceName(searchUpper)?.toLowerCase() : searchProvincia.toLowerCase().trim();
    
    // Controlla il campo provincia del comune
    if (commune.provincia) {
      const dbProv = commune.provincia.trim();
      const dbProvUpper = dbProv.toUpperCase();
      const isDbCode = dbProvUpper.length <= 3;
      
      // Converti il DB in entrambi i formati
      const dbAsCode = isDbCode ? dbProvUpper : getProvinceCode(dbProv);
      const dbAsName = isDbCode ? getProvinceName(dbProvUpper)?.toLowerCase() : dbProv.toLowerCase();
      
      // Match su sigla
      if (searchAsCode && dbAsCode && searchAsCode === dbAsCode) {
        return true;
      }
      
      // Match su nome (case insensitive)
      if (searchAsName && dbAsName && searchAsName === dbAsName) {
        return true;
      }
    }
    
    // Controlla anche provincia_nome
    if (commune.provincia_nome) {
      const dbProvNome = commune.provincia_nome.toLowerCase().trim();
      const dbProvNomeCode = getProvinceCode(commune.provincia_nome);
      
      // Match nome con nome
      if (searchAsName && dbProvNome === searchAsName) {
        return true;
      }
      
      // Match sigla con sigla derivata dal nome
      if (searchAsCode && dbProvNomeCode && searchAsCode === dbProvNomeCode) {
        return true;
      }
    }
    
    return false;
  };
  
  // Debug: log al primo render per vedere i dati
  useEffect(() => {
    if (allCommunes.length > 0) {
      const toCommunes = allCommunes.filter(c => matchesProvincia(c, 'TO', false));
      console.log('Debug province matching:', {
        totaleCommuni: allCommunes.length,
        comuniPerTO: toCommunes.length,
        primiComuniTO: toCommunes.slice(0, 5).map(c => ({ 
          comune: c.comune, 
          provincia: c.provincia, 
          provincia_nome: c.provincia_nome 
        })),
        primiComuniDB: allCommunes.slice(0, 5).map(c => ({ 
          comune: c.comune, 
          provincia: c.provincia, 
          provincia_nome: c.provincia_nome 
        }))
      });
    }
  }, [allCommunes]);

  // Cerca un comune per nome, usando mappature salvate e match flessibile
  const findCommuneByName = (
    csvComune: string, 
    csvProvincia: string, 
    sessionMappings: Record<string, string>
  ): CommuneFromDB | null => {
    if (!csvComune || !csvProvincia) return null;
    
    const normalizedComune = normalizeName(csvComune);
    const normalizedProvincia = csvProvincia.toLowerCase().trim();
    const savedMappings = loadSavedCommuneMappings();
    const mappingKey = `${csvComune}|${csvProvincia}`;
    const savedKey = `${normalizedComune}|${normalizedProvincia}`;
    
    // Filtra comuni della stessa provincia (matching STRICT per auto-match)
    const communesInProvincia = allCommunes.filter(c => matchesProvincia(c, csvProvincia, true));
    
    // 1. Prima controlla le mappature della sessione corrente
    if (sessionMappings[mappingKey]) {
      const commune = allCommunes.find(c => c.id === sessionMappings[mappingKey]);
      if (commune) return commune;
    }
    
    // 2. Poi controlla le mappature salvate in localStorage
    if (savedMappings[savedKey]) {
      const commune = allCommunes.find(c => c.id === savedMappings[savedKey]);
      if (commune) return commune;
    }
    
    // 3. Match esatto case-insensitive (normalizzato)
    const exactMatch = communesInProvincia.find(c => 
      normalizeName(c.comune) === normalizedComune
    );
    if (exactMatch) return exactMatch;
    
    // 4. Match senza accenti e caratteri speciali
    const noAccentMatch = communesInProvincia.find(c => {
      const normalizedDbName = normalizeName(c.comune);
      return normalizedDbName === normalizedComune;
    });
    if (noAccentMatch) return noAccentMatch;
    
    return null;
  };

  // Pre-verifica tutti i comuni nel CSV e identifica quelli non trovati
  const preCheckCommunes = async (): Promise<{ 
    unmapped: { comune: string; provincia: string }[], 
    mapped: Record<string, string> 
  }> => {
    if (!file) return { unmapped: [], mapped: {} };
    
    const text = await file.text();
    const results = Papa.parse<CSVRow>(text, { header: true, skipEmptyLines: true });
    
    const allCommuneKeys = new Set<string>();
    const mapped: Record<string, string> = {};
    const unmapped: { comune: string; provincia: string }[] = [];
    
    // Raccogli tutti i comuni unici
    results.data.forEach(row => {
      let comune = '';
      let provincia = '';
      
      Object.keys(columnMapping).forEach(col => {
        const target = columnMapping[col];
        const value = row[col]?.trim();
        if (target === 'comune' && value) comune = value;
        if (target === 'provincia' && value) provincia = value;
      });
      
      if (comune && provincia) {
        allCommuneKeys.add(`${comune}|${provincia}`);
      }
    });
    
    // Verifica quali sono mappabili
    allCommuneKeys.forEach(key => {
      const [comune, provincia] = key.split('|');
      const found = findCommuneByName(comune, provincia, communeMappings);
      if (found) {
        mapped[key] = found.id;
      } else {
        unmapped.push({ comune, provincia });
      }
    });
    
    return { unmapped, mapped };
  };

  // Auto-detect column mapping
  const autoDetectMapping = (columns: string[]): ColumnMapping => {
    const mapping: ColumnMapping = {};
    
    columns.forEach(col => {
      const lower = col.toLowerCase().trim();
      
      if (lower.includes('comune') || lower === 'city' || lower === 'città') {
        mapping[col] = 'comune';
      } else if (lower.includes('provincia') || lower === 'province' || lower === 'prov') {
        mapping[col] = 'provincia';
      } else if (lower.includes('quartiere') || lower === 'district' || lower === 'neighborhood') {
        mapping[col] = 'quartiere';
      } else if (lower.includes('cat') && (lower.includes('1') || lower.includes('primo') || lower.includes('first'))) {
        mapping[col] = 'cat1';
      } else if (lower.includes('cat') && (lower.includes('2') || lower.includes('secondo') || lower.includes('second'))) {
        mapping[col] = 'cat2';
      } else if (lower.includes('cat') && (lower.includes('3') || lower.includes('terzo') || lower.includes('third'))) {
        mapping[col] = 'cat3';
      } else if (lower.includes('cat') && lower.includes('name')) {
        mapping[col] = 'cat1'; // Default CAT name to cat1
      } else if (lower.includes('note') || lower === 'notes' || lower === 'commenti') {
        mapping[col] = 'note';
      } else if (lower.includes('intervento') || lower.includes('intervention') || lower === 'tipo' || lower === 'type') {
        mapping[col] = 'intervention_type';
      } else {
        mapping[col] = 'ignore';
      }
    });
    
    return mapping;
  };

  // Verifica se c'è una colonna mappata a intervention_type
  const hasInterventionTypeColumn = (): boolean => {
    return Object.values(columnMapping).includes('intervention_type');
  };

  // Normalizza il valore intervention_type dal CSV
  const normalizeInterventionType = (value: string): InterventionType => {
    const lower = value.toLowerCase().trim();
    if (lower === 'sopralluogo' || lower === 'sopr' || lower === 's') {
      return 'sopralluogo';
    } else if (lower === 'rfs' || lower === 'r') {
      return 'rfs';
    } else if (lower === 'both' || lower === 'entrambi' || lower === 'b' || lower === 'e') {
      return 'both';
    }
    return 'both'; // Default
  };

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const selectedFile = e.target.files?.[0];
    if (selectedFile) {
      if (!selectedFile.name.endsWith('.csv')) {
        toast.error('Formato file non valido. Usa .csv');
        return;
      }
      setFile(selectedFile);
      parseFilePreview(selectedFile);
    }
  };

  const parseFilePreview = async (file: File) => {
    const text = await file.text();
    
    Papa.parse<CSVRow>(text, {
      header: true,
      skipEmptyLines: true,
      complete: (results) => {
        const columns = results.meta.fields || [];
        setAvailableColumns(columns);
        
        const detectedMapping = autoDetectMapping(columns);
        setColumnMapping(detectedMapping);
        
        // Map first 10 rows for preview
        const preview = results.data.slice(0, 10).map(row => {
          const mapped: ParsedRow['mapped'] = {};
          const errors: string[] = [];
          
          columns.forEach(col => {
            const mappedField = detectedMapping[col];
            const value = row[col]?.trim();
            
            if (mappedField && mappedField !== 'ignore' && value) {
              mapped[mappedField] = value;
            }
          });
          
          // Validate required fields
          if (!mapped.comune) errors.push('Comune mancante');
          if (!mapped.provincia) errors.push('Provincia mancante');
          // CAT è richiesto solo se non è esplicitamente N/D
          if (!mapped.cat1 && !isNoCatValue(mapped.cat1)) errors.push('Almeno un CAT richiesto');
          
          return { raw: row, mapped, errors };
        });
        
        setParsedData(preview);
        setShowPreview(true);
      },
      error: (error) => {
        console.error('Errore parsing CSV:', error);
        toast.error('Errore nel parsing del file CSV');
      }
    });
  };

  const updateColumnMapping = (column: string, target: string) => {
    setColumnMapping(prev => ({
      ...prev,
      [column]: target as any
    }));
    
    // Re-map data with new mapping
    setParsedData(prev => prev.map(row => {
      const mapped: ParsedRow['mapped'] = {};
      const errors: string[] = [];
      
      Object.keys(columnMapping).forEach(col => {
        const mappedField = col === column ? target : columnMapping[col];
        const value = row.raw[col]?.trim();
        
        if (mappedField && mappedField !== 'ignore' && value) {
          mapped[mappedField as keyof ParsedRow['mapped']] = value;
        }
      });
      
      if (!mapped.comune) errors.push('Comune mancante');
      if (!mapped.provincia) errors.push('Provincia mancante');
      // CAT è richiesto solo se non è esplicitamente N/D
      if (!mapped.cat1 && !isNoCatValue(mapped.cat1)) errors.push('Almeno un CAT richiesto');
      
      return { ...row, mapped, errors };
    }));
  };

  const downloadTemplate = () => {
    const template = 'quartiere,comune,provincia,CAT 1,CAT 2,CAT 3,NOTE\n' +
                    'Centro,Milano,MI,Centro Assistenza Milano,Centro Est,,Note di esempio\n' +
                    ',Roma,RM,Centro Roma,,,Altra nota';
    
    const blob = new Blob([template], { type: 'text/csv' });
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'template_cat_import.csv';
    a.click();
    window.URL.revokeObjectURL(url);
  };

  const confirmAndImport = async () => {
    // STEP 1: Pre-verifica i comuni
    const { unmapped: unmappedCommunesList } = await preCheckCommunes();
    
    if (unmappedCommunesList.length > 0) {
      // Mostra dialog per mappatura manuale comuni
      setUnmappedCommunes(unmappedCommunesList);
      // Inizializza le mappature con vuoto
      const initialMappings: Record<string, string> = {};
      unmappedCommunesList.forEach(({ comune, provincia }) => {
        initialMappings[`${comune}|${provincia}`] = '';
      });
      setCommuneMappings(prev => ({ ...prev, ...initialMappings }));
      setShowCommuneMappingDialog(true);
      return;
    }
    
    // STEP 2: Pre-verifica i nomi CAT
    await checkCatsAndProceed();
  };

  // Controlla il tipo di intervento e procedi all'import
  const checkInterventionTypeAndProceed = () => {
    if (!hasInterventionTypeColumn()) {
      // Mostra dialog per selezionare il tipo di intervento globale
      setShowInterventionTypeDialog(true);
    } else {
      // Procedi direttamente all'import
      setShowPreview(false);
      handleImport();
    }
  };

  // Gestisce la conferma del tipo di intervento
  const handleConfirmInterventionType = () => {
    setShowInterventionTypeDialog(false);
    setShowPreview(false);
    handleImport();
  };

  // Controlla i CAT e procedi all'import
  const checkCatsAndProceed = async () => {
    const { unmapped } = await preCheckCatNames();
    
    if (unmapped.length > 0) {
      // Mostra dialog per mappatura manuale CAT
      setUnmappedCatNames(unmapped);
      const initialMappings: Record<string, string> = {};
      unmapped.forEach(name => {
        initialMappings[name] = '';
      });
      setCatNameMappings(prev => ({ ...prev, ...initialMappings }));
      setShowCatMappingDialog(true);
    } else {
      // Tutti mappati, verifica tipo di intervento
      checkInterventionTypeAndProceed();
    }
  };

  // Gestisce la conferma delle mappature comuni
  const handleConfirmCommuneMappings = async () => {
    // Verifica che tutti siano mappati
    const allMapped = unmappedCommunes.every(({ comune, provincia }) => 
      communeMappings[`${comune}|${provincia}`]
    );
    
    if (!allMapped) {
      toast.error('Mappa tutti i comuni prima di procedere');
      return;
    }
    
    // Salva le mappature in localStorage per uso futuro
    unmappedCommunes.forEach(({ comune, provincia }) => {
      const key = `${comune}|${provincia}`;
      if (communeMappings[key]) {
        saveCommuneMappingToStorage(comune, provincia, communeMappings[key]);
      }
    });
    
    setShowCommuneMappingDialog(false);
    
    // Ora controlla i CAT
    await checkCatsAndProceed();
  };

  // Salta i comuni non mappati
  const handleSkipUnmappedCommunes = async () => {
    setShowCommuneMappingDialog(false);
    toast.warning('I comuni non mappati verranno ignorati durante l\'import');
    await checkCatsAndProceed();
  };

  // Gestisce la conferma delle mappature CAT
  const handleConfirmCatMappings = () => {
    // Verifica che tutti siano mappati
    const allMapped = unmappedCatNames.every(name => catNameMappings[name]);
    
    if (!allMapped) {
      toast.error('Mappa tutti i CAT prima di procedere');
      return;
    }
    
    // Salva le mappature in localStorage per uso futuro
    unmappedCatNames.forEach(name => {
      if (catNameMappings[name]) {
        saveCatMappingToStorage(name, catNameMappings[name]);
      }
    });
    
    setShowCatMappingDialog(false);
    // Verifica tipo di intervento
    checkInterventionTypeAndProceed();
  };

  // Salta i CAT non mappati
  const handleSkipUnmappedCats = () => {
    setShowCatMappingDialog(false);
    toast.warning('I CAT non mappati verranno ignorati durante l\'import');
    // Verifica tipo di intervento
    checkInterventionTypeAndProceed();
  };

  const handleImport = async () => {
    if (!file) {
      toast.error('Seleziona un file');
      return;
    }

    if (isProcessing) {
      toast.warning('Importazione già in corso');
      return;
    }

    setIsProcessing(true);
    setProgress(0);
    setStats({ processed: 0, success: 0, errors: 0 });

    try {
      const text = await file.text();
      
      Papa.parse<CSVRow>(text, {
        header: true,
        skipEmptyLines: true,
        complete: async (results) => {
          const rows = results.data;
          const total = rows.length;
          
          toast.info(`Inizio importazione di ${total} righe...`);

          let processed = 0;
          let success = 0;
          let errors = 0;

          for (let i = 0; i < rows.length; i++) {
            const row = rows[i];
            const progressPercent = ((i + 1) / total) * 100;
            
            try {
              // Map using column mapping FIRST
              const mappedRow: ParsedRow['mapped'] = {};
              Object.keys(columnMapping).forEach(col => {
                const target = columnMapping[col];
                const value = row[col]?.trim();
                if (target !== 'ignore' && value) {
                  mappedRow[target] = value;
                }
              });

              const comune = mappedRow.comune;
              const provincia = mappedRow.provincia;
              
              if (!comune || !provincia) {
                console.warn('Riga saltata: mancano comune o provincia', row);
                errors++;
                continue;
              }

              setCurrentRow(`${comune} (${provincia})`);
              setProgress(progressPercent);

              // Trova il comune usando le mappature
              const foundCommune = findCommuneByName(comune, provincia, communeMappings);

              if (!foundCommune) {
                // Debug: mostra anche i comuni disponibili per questa provincia
                const communesForProv = allCommunes.filter(c => 
                  matchesProvincia(c, provincia, false)
                );
                // Cerca nomi simili nel DB
                const normalizedSearch = normalizeName(comune);
                
                // Debug dettagliato: mostra tutti i comuni che iniziano con la stessa lettera
                const sameLetterCommunes = communesForProv.filter(c => 
                  c.comune.toLowerCase().startsWith(comune.charAt(0).toLowerCase())
                );
                
                console.warn('Comune non trovato:', {
                  cercato: comune,
                  cercatoNormalizzato: normalizedSearch,
                  provincia: provincia,
                  comuniStessaLettera: sameLetterCommunes.slice(0, 10).map(c => ({
                    originale: c.comune,
                    normalizzato: normalizeName(c.comune),
                    match: normalizeName(c.comune) === normalizedSearch
                  })),
                  totaleInProvincia: communesForProv.length
                });
                errors++;
                continue;
              }

              const communeData = { id: foundCommune.id };

              // Processa i CAT - usa le mappature (salvate + sessione)
              // Filtra valori vuoti e N/D
              const catValues = [
                mappedRow.cat1,
                mappedRow.cat2,
                mappedRow.cat3
              ].filter(v => v && !isNoCatValue(v)) as string[];

              if (catValues.length === 0) {
                // Se è N/D, skip silenzioso (comune senza CAT)
                const hasNoCatMarker = isNoCatValue(mappedRow.cat1) || isNoCatValue(mappedRow.cat2) || isNoCatValue(mappedRow.cat3);
                if (hasNoCatMarker) {
                  console.log(`Comune ${comune} (${provincia}) marcato come N/D - skippato`);
                  // Non incrementare errors, è un caso valido
                  success++; // Consideriamo come successo (elaborato correttamente)
                  processed++;
                  setStats({ processed, success, errors });
                  continue;
                }
                console.warn('Nessun CAT specificato per', comune);
                errors++;
                continue;
              }

              // Cerca CAT usando le mappature
              const catsData: CATFromDB[] = [];
              for (const catName of catValues) {
                const foundCat = findCatByName(catName, catNameMappings);
                if (foundCat && !catsData.find(c => c.id === foundCat.id)) {
                  catsData.push(foundCat);
                }
              }

              if (catsData.length === 0) {
                console.warn('Nessun CAT trovato per i valori:', catValues);
                errors++;
                continue;
              }

              // Rimuovi associazioni esistenti per questo comune
              await supabase
                .from('cat_commune')
                .delete()
                .eq('commune_id', communeData.id);

              // Inserisci nuove associazioni
              const notes = mappedRow.note || null;
              
              // Determina il tipo di intervento (dalla colonna o globale)
              const interventionType: InterventionType = mappedRow.intervention_type 
                ? normalizeInterventionType(mappedRow.intervention_type)
                : globalInterventionType;
              
              for (let j = 0; j < catsData.length; j++) {
                const cat = catsData[j];
                const isPrimary = j === 0; // Il primo CAT è primario

                const { error: insertError } = await supabase
                  .from('cat_commune')
                  .insert({
                    cat_id: cat.id,
                    commune_id: communeData.id,
                    is_primary: isPrimary,
                    notes: notes,
                    intervention_type: interventionType,
                    active: true
                  });

                if (insertError) {
                  console.error('Errore inserimento cat_commune:', insertError);
                  errors++;
                  continue;
                }
              }

              success++;
            } catch (err) {
              console.error('Errore processing riga:', err);
              errors++;
            }

            processed++;
            setStats({ processed, success, errors });
          }

          if (success > 0) {
            toast.success(`Importati ${success} comuni con CAT!`);
          }
          if (errors > 0) {
            toast.warning(`${errors} righe saltate per errori`);
          }

          setFile(null);
          setIsProcessing(false);
          if (fileInputRef.current) {
            fileInputRef.current.value = '';
          }
        },
        error: (error) => {
          console.error('Errore parsing CSV:', error);
          toast.error('Errore nel parsing del file CSV');
          setIsProcessing(false);
        }
      });
    } catch (error: any) {
      console.error('Errore import:', error);
      toast.error(error.message || 'Errore durante l\'importazione');
      setIsProcessing(false);
    }
  };

  // Dialog per mappatura CAT non trovati
  const renderCatMappingDialog = () => {
    // Filtra i CAT non mappati in base alla ricerca
    const filteredUnmappedCats = catSearchFilter
      ? unmappedCatNames.filter(name => 
          normalizeName(name).includes(normalizeName(catSearchFilter))
        )
      : unmappedCatNames;

    return (
      <Dialog open={showCatMappingDialog} onOpenChange={(open) => {
        setShowCatMappingDialog(open);
        if (!open) setCatSearchFilter('');
      }}>
        <DialogContent className="max-w-2xl">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <AlertTriangle className="h-5 w-5 text-yellow-500" />
              CAT Non Trovati
            </DialogTitle>
            <DialogDescription>
              I seguenti nomi CAT nel file non corrispondono a nessun CAT nel database.
              Associali manualmente ai CAT esistenti.
            </DialogDescription>
          </DialogHeader>
          
          <div className="space-y-4">
            
            {/* Campo di ricerca */}
            <div className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
              <Input
                placeholder="Cerca CAT..."
                value={catSearchFilter}
                onChange={(e) => setCatSearchFilter(e.target.value)}
                className="pl-9"
              />
            </div>
            
            <ScrollArea className="max-h-[350px]">
              <div className="space-y-3 pr-4">
                {filteredUnmappedCats.length === 0 ? (
                  <p className="text-sm text-muted-foreground text-center py-4">
                    Nessun risultato per "{catSearchFilter}"
                  </p>
                ) : (
                  filteredUnmappedCats.map(name => {
                    const selectedCat = allCats.find(c => c.id === catNameMappings[name]);
                    return (
                      <div key={name} className="flex items-center gap-3 p-3 bg-muted/50 rounded-lg">
                        <div className="flex-1">
                          <span className="font-medium text-sm">{name}</span>
                        </div>
                        <Link2 className="h-4 w-4 text-muted-foreground" />
                        <Popover open={openCatCombobox === name} onOpenChange={(open) => setOpenCatCombobox(open ? name : null)}>
                          <PopoverTrigger asChild>
                            <Button
                              variant="outline"
                              role="combobox"
                              aria-expanded={openCatCombobox === name}
                              className="w-[250px] justify-between"
                            >
                              {selectedCat ? selectedCat.name : "Cerca CAT..."}
                              <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
                            </Button>
                          </PopoverTrigger>
                          <PopoverContent className="w-[300px] p-0">
                            <Command>
                              <CommandInput placeholder="Cerca CAT..." />
                              <CommandList>
                                <CommandEmpty>Nessun CAT trovato.</CommandEmpty>
                                <CommandGroup>
                                  {allCats.map(cat => (
                                    <CommandItem
                                      key={cat.id}
                                      value={cat.name}
                                      onSelect={() => {
                                        setCatNameMappings(prev => ({
                                          ...prev,
                                          [name]: cat.id
                                        }));
                                        setOpenCatCombobox(null);
                                      }}
                                    >
                                      <Check
                                        className={`mr-2 h-4 w-4 ${
                                          catNameMappings[name] === cat.id ? "opacity-100" : "opacity-0"
                                        }`}
                                      />
                                      {cat.name}
                                    </CommandItem>
                                  ))}
                                </CommandGroup>
                              </CommandList>
                            </Command>
                          </PopoverContent>
                        </Popover>
                      </div>
                    );
                  })
                )}
              </div>
            </ScrollArea>
            
            <p className="text-xs text-muted-foreground">
              Le associazioni verranno salvate automaticamente per le prossime importazioni.
              {catSearchFilter && ` (Visualizzati ${filteredUnmappedCats.length} di ${unmappedCatNames.length})`}
            </p>
          </div>
          
          <DialogFooter className="gap-2 sm:gap-0">
            <Button variant="outline" onClick={handleSkipUnmappedCats}>
              Salta Non Mappati
            </Button>
            <Button onClick={handleConfirmCatMappings}>
              <Check className="h-4 w-4 mr-2" />
              Conferma e Importa
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    );
  };

  // Dialog per mappatura comuni non trovati
  const renderCommuneMappingDialog = () => {
    // Filtra i comuni non mappati in base alla ricerca
    const filteredUnmappedCommunes = communeSearchFilter
      ? unmappedCommunes.filter(({ comune, provincia }) => 
          normalizeName(comune).includes(normalizeName(communeSearchFilter)) ||
          provincia.toLowerCase().includes(communeSearchFilter.toLowerCase())
        )
      : unmappedCommunes;

    return (
      <Dialog open={showCommuneMappingDialog} onOpenChange={(open) => {
        setShowCommuneMappingDialog(open);
        if (!open) setCommuneSearchFilter('');
      }}>
        <DialogContent className="max-w-2xl">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <AlertTriangle className="h-5 w-5 text-yellow-500" />
              Comuni Non Trovati
            </DialogTitle>
            <DialogDescription>
              I seguenti comuni nel file non corrispondono a nessun comune nel database
              (probabilmente per differenze negli accenti o nella scrittura).
              Associali manualmente ai comuni corretti.
            </DialogDescription>
          </DialogHeader>
          
          <div className="space-y-4">
            
            {/* Campo di ricerca */}
            <div className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
              <Input
                placeholder="Cerca comune..."
                value={communeSearchFilter}
                onChange={(e) => setCommuneSearchFilter(e.target.value)}
                className="pl-9"
              />
            </div>
            
            <ScrollArea className="max-h-[350px]">
              <div className="space-y-3 pr-4">
                {filteredUnmappedCommunes.length === 0 ? (
                  <p className="text-sm text-muted-foreground text-center py-4">
                    Nessun risultato per "{communeSearchFilter}"
                  </p>
                ) : (
                  filteredUnmappedCommunes.map(({ comune, provincia }) => {
                    const key = `${comune}|${provincia}`;
                    // Ordina comuni: prima quelli della stessa provincia (match flessibile), poi tutti gli altri
                    const communesInProvincia = allCommunes.filter(c => 
                      matchesProvincia(c, provincia, false) // match flessibile
                    );
                    const communesNotInProvincia = allCommunes.filter(c => 
                      !matchesProvincia(c, provincia, false)
                    );
                    // Mostra tutti i comuni, con priorità a quelli della stessa provincia
                    const communesToShow = [...communesInProvincia, ...communesNotInProvincia];
                    const selectedCommune = allCommunes.find(c => c.id === communeMappings[key]);
                    const hasProvinciaMatches = communesInProvincia.length > 0;
                    
                    return (
                      <div key={key} className="flex items-center gap-3 p-3 bg-muted/50 rounded-lg">
                        <div className="flex-1">
                          <span className="font-medium text-sm">{comune}</span>
                          <Badge variant="outline" className="ml-2">{provincia}</Badge>
                        </div>
                        <Link2 className="h-4 w-4 text-muted-foreground" />
                        <Popover open={openCommuneCombobox === key} onOpenChange={(open) => setOpenCommuneCombobox(open ? key : null)}>
                          <PopoverTrigger asChild>
                            <Button
                              variant="outline"
                              role="combobox"
                              aria-expanded={openCommuneCombobox === key}
                              className="w-[280px] justify-between"
                            >
                              {selectedCommune 
                                ? `${selectedCommune.comune} (${selectedCommune.provincia})`
                                : "Cerca comune..."}
                              <ChevronsUpDown className="ml-2 h-4 w-4 shrink-0 opacity-50" />
                            </Button>
                          </PopoverTrigger>
                          <PopoverContent className="w-[320px] p-0">
                            <Command>
                              <CommandInput placeholder="Cerca comune..." />
                              <CommandList>
                                <CommandEmpty>Nessun comune trovato.</CommandEmpty>
                                {hasProvinciaMatches && (
                                  <CommandGroup heading={`Comuni in ${provincia}`}>
                                    {communesInProvincia.map(c => (
                                      <CommandItem
                                        key={c.id}
                                        value={`${c.comune} ${c.provincia}`}
                                        onSelect={() => {
                                          setCommuneMappings(prev => ({
                                            ...prev,
                                            [key]: c.id
                                          }));
                                          setOpenCommuneCombobox(null);
                                        }}
                                      >
                                        <Check
                                          className={`mr-2 h-4 w-4 ${
                                            communeMappings[key] === c.id ? "opacity-100" : "opacity-0"
                                          }`}
                                        />
                                        {c.comune} ({c.provincia})
                                      </CommandItem>
                                    ))}
                                  </CommandGroup>
                                )}
                                <CommandGroup heading={hasProvinciaMatches ? "Altri comuni" : "Tutti i comuni"}>
                                  {(hasProvinciaMatches ? communesNotInProvincia : communesToShow).map(c => (
                                    <CommandItem
                                      key={c.id}
                                      value={`${c.comune} ${c.provincia}`}
                                      onSelect={() => {
                                        setCommuneMappings(prev => ({
                                          ...prev,
                                          [key]: c.id
                                        }));
                                        setOpenCommuneCombobox(null);
                                      }}
                                    >
                                      <Check
                                        className={`mr-2 h-4 w-4 ${
                                          communeMappings[key] === c.id ? "opacity-100" : "opacity-0"
                                        }`}
                                      />
                                      {c.comune} ({c.provincia})
                                    </CommandItem>
                                  ))}
                                </CommandGroup>
                              </CommandList>
                            </Command>
                          </PopoverContent>
                        </Popover>
                      </div>
                    );
                  })
                )}
              </div>
            </ScrollArea>
            
            <p className="text-xs text-muted-foreground">
              Le associazioni verranno salvate automaticamente per le prossime importazioni.
              {communeSearchFilter && ` (Visualizzati ${filteredUnmappedCommunes.length} di ${unmappedCommunes.length})`}
            </p>
          </div>
          
          <DialogFooter className="gap-2 sm:gap-0">
            <Button variant="outline" onClick={handleSkipUnmappedCommunes}>
              Salta Non Mappati
            </Button>
            <Button onClick={handleConfirmCommuneMappings}>
              <Check className="h-4 w-4 mr-2" />
              Conferma e Continua
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    );
  };

  // Dialog per selezione tipo di intervento globale
  const renderInterventionTypeDialog = () => (
    <Dialog open={showInterventionTypeDialog} onOpenChange={setShowInterventionTypeDialog}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>Tipo di Intervento</DialogTitle>
          <DialogDescription>
            Il file CSV non contiene una colonna per il tipo di intervento.
            Seleziona il tipo che verrà applicato a tutte le associazioni.
          </DialogDescription>
        </DialogHeader>
        
        <div className="space-y-4">
          
          <div className="space-y-2">
            <label className="text-sm font-medium">Tipo di intervento</label>
            <Select
              value={globalInterventionType}
              onValueChange={(value) => setGlobalInterventionType(value as InterventionType)}
            >
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {INTERVENTION_TYPES.map(type => (
                  <SelectItem key={type.value} value={type.value}>
                    {type.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          
          <div className="text-xs text-muted-foreground space-y-1">
            <p><strong>Sopralluogo:</strong> CAT disponibile solo per sopralluoghi</p>
            <p><strong>RFS:</strong> CAT disponibile solo per RFS</p>
            <p><strong>Entrambi:</strong> CAT disponibile per entrambi i tipi</p>
          </div>
        </div>
        
        <DialogFooter>
          <Button variant="outline" onClick={() => setShowInterventionTypeDialog(false)}>
            Annulla
          </Button>
          <Button onClick={handleConfirmInterventionType}>
            <Check className="h-4 w-4 mr-2" />
            Conferma e Importa
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );

  if (showPreview) {
    return (
      <div className="space-y-6">
        {renderCommuneMappingDialog()}
        {renderCatMappingDialog()}
        {renderInterventionTypeDialog()}
        
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <Button
              variant="ghost"
              size="sm"
              onClick={() => {
                setShowPreview(false);
                setFile(null);
                if (fileInputRef.current) fileInputRef.current.value = '';
              }}
            >
              <ArrowLeft className="h-4 w-4 mr-2" />
              Indietro
            </Button>
            <div>
              <h3 className="text-lg font-semibold">Anteprima Importazione</h3>
              <p className="text-sm text-muted-foreground">
                Verifica e correggi la mappatura delle colonne
              </p>
            </div>
          </div>
          <Button onClick={confirmAndImport} disabled={parsedData.some(r => r.errors.length > 0)}>
            <Check className="h-4 w-4 mr-2" />
            Conferma e Importa
          </Button>
        </div>

        <Card className="p-4">
          <h4 className="font-medium mb-4">Mappatura Colonne</h4>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {availableColumns.map(col => (
              <div key={col} className="space-y-2">
                <label className="text-sm font-medium">
                  {col}
                </label>
                <Select
                  value={columnMapping[col] || 'ignore'}
                  onValueChange={(value) => updateColumnMapping(col, value)}
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="ignore">Ignora</SelectItem>
                    <SelectItem value="comune">Comune</SelectItem>
                    <SelectItem value="provincia">Provincia</SelectItem>
                    <SelectItem value="quartiere">Quartiere</SelectItem>
                    <SelectItem value="cat1">CAT 1 (Nome)</SelectItem>
                    <SelectItem value="cat2">CAT 2 (Nome)</SelectItem>
                    <SelectItem value="cat3">CAT 3 (Nome)</SelectItem>
                    <SelectItem value="intervention_type">Tipo Intervento</SelectItem>
                    <SelectItem value="note">Note</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            ))}
          </div>
        </Card>

        <Card className="p-4">
          <h4 className="font-medium mb-4">
            Anteprima Dati (Prime 10 righe)
          </h4>
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Stato</TableHead>
                  <TableHead>Comune</TableHead>
                  <TableHead>Provincia</TableHead>
                  <TableHead>Quartiere</TableHead>
                  <TableHead>CAT 1</TableHead>
                  <TableHead>CAT 2</TableHead>
                  <TableHead>CAT 3</TableHead>
                  <TableHead>Tipo Intervento</TableHead>
                  <TableHead>Note</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {parsedData.map((row, idx) => (
                  <TableRow key={idx}>
                    <TableCell>
                      {row.errors.length === 0 ? (
                        <Badge variant="default" className="bg-green-600">OK</Badge>
                      ) : (
                        <Badge variant="destructive">
                          {row.errors.length} errori
                        </Badge>
                      )}
                    </TableCell>
                    <TableCell className={!row.mapped.comune ? 'text-destructive' : ''}>
                      {row.mapped.comune || '-'}
                    </TableCell>
                    <TableCell className={!row.mapped.provincia ? 'text-destructive' : ''}>
                      {row.mapped.provincia || '-'}
                    </TableCell>
                    <TableCell>{row.mapped.quartiere || '-'}</TableCell>
                    <TableCell className={!row.mapped.cat1 ? 'text-destructive' : ''}>
                      {row.mapped.cat1 || '-'}
                    </TableCell>
                    <TableCell>{row.mapped.cat2 || '-'}</TableCell>
                    <TableCell>{row.mapped.cat3 || '-'}</TableCell>
                    <TableCell>
                      {row.mapped.intervention_type 
                        ? INTERVENTION_TYPES.find(t => 
                            normalizeInterventionType(row.mapped.intervention_type!) === t.value
                          )?.label || row.mapped.intervention_type
                        : <span className="text-muted-foreground italic">Da impostare</span>
                      }
                    </TableCell>
                    <TableCell className="max-w-xs truncate">
                      {row.mapped.note || '-'}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        </Card>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="space-y-4">
        <div className="flex items-center gap-4">
          <div className="flex-1">
            <Input
              ref={fileInputRef}
              type="file"
              accept=".csv"
              onChange={handleFileChange}
              disabled={isProcessing}
            />
          </div>
          {file && !showPreview && (
            <div className="flex items-center gap-2 text-sm text-muted-foreground">
              <FileSpreadsheet className="h-4 w-4" />
              {file.name}
            </div>
          )}
        </div>

        <div className="flex gap-2">
          <Button
            variant="outline"
            onClick={downloadTemplate}
            disabled={isProcessing}
          >
            <Download className="h-4 w-4 mr-2" />
            Scarica Template
          </Button>
        </div>
      </div>

      {isProcessing && (
        <div className="space-y-3 p-4 bg-muted/50 rounded-lg">
          <div className="space-y-2">
            <div className="flex justify-between text-sm">
              <span className="font-medium">Progresso</span>
              <span className="text-muted-foreground">{Math.round(progress)}%</span>
            </div>
            <Progress value={progress} />
          </div>
          
          <div className="text-sm space-y-1">
            <p className="text-muted-foreground">
              <span className="font-medium">Riga corrente:</span> {currentRow}
            </p>
            <div className="flex gap-4 text-xs">
              <span>Processate: {stats.processed}</span>
              <span className="text-green-600">Successo: {stats.success}</span>
              <span className="text-destructive">Errori: {stats.errors}</span>
            </div>
          </div>
        </div>
      )}

      <div className="p-4 bg-muted/50 rounded-lg text-sm text-muted-foreground space-y-3">
        <h4 className="font-medium text-foreground">Formato CSV:</h4>
        <p>Il sistema rileva automaticamente le colonne, ma puoi usare questi nomi suggeriti:</p>
        <ul className="list-disc list-inside space-y-1 ml-2">
          <li><strong>comune</strong> (obbligatorio): Nome del comune</li>
          <li><strong>provincia</strong> (obbligatorio): Sigla provincia (es. MI, RM)</li>
          <li><strong>quartiere</strong> (opzionale): Nome quartiere</li>
          <li><strong>CAT 1</strong> (obbligatorio): Nome CAT primario</li>
          <li><strong>CAT 2</strong> (opzionale): Nome CAT secondario</li>
          <li><strong>CAT 3</strong> (opzionale): Nome CAT terziario</li>
          <li><strong>tipo intervento</strong> (opzionale): sopralluogo, rfs, o entrambi/both</li>
          <li><strong>NOTE</strong> (opzionale): Note aggiuntive</li>
        </ul>
        <p className="text-xs mt-2">
          Dopo aver caricato il file, potrai verificare e correggere la mappatura delle colonne prima dell'importazione.
          Se non c'è una colonna per il tipo di intervento, ti verrà chiesto di selezionarlo.
        </p>
      </div>
    </div>
  );
};

export default CATImport;
