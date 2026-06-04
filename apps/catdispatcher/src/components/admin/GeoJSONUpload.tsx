import { useState, useRef, useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useQueryClient } from '@tanstack/react-query';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { toast } from 'sonner';
import { Upload, FileJson, Settings2, Check, AlertTriangle } from 'lucide-react';
import { useUpload } from '@/contexts/UploadContext';
import proj4 from 'proj4';
import { getProvinceCode } from '@/lib/textUtils';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { Label } from '@/components/ui/label';
import { Badge } from '@/components/ui/badge';
import { Card } from '@/components/ui/card';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Separator } from '@/components/ui/separator';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from '@/components/ui/dialog';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';

// Tipi di intervento disponibili
const INTERVENTION_TYPES = [
  { value: 'sopralluogo', label: 'Sopralluogo' },
  { value: 'rfs', label: 'RFS' },
  { value: 'both', label: 'Entrambi' },
] as const;

type InterventionType = 'sopralluogo' | 'rfs' | 'both';

type MappableField = 'comune' | 'provincia_sigla' | 'provincia_nome' | 'regione' | 'quartiere' | 'cat1' | 'cat2' | 'cat3' | 'ignore';

interface ColumnMapping {
  [propertyName: string]: MappableField;
}

interface CATMapping {
  cat1_intervention: InterventionType;
  cat2_intervention: InterventionType;
  cat3_intervention: InterventionType;
}

interface PreviewFeature {
  properties: Record<string, any>;
  mapped: {
    comune?: string;
    provincia?: string;
    regione?: string;
    quartiere?: string;
    cat1?: string;
    cat2?: string;
    cat3?: string;
  };
  errors: string[];
}

const FIELD_LABELS: Record<MappableField, string> = {
  comune: 'Comune',
  provincia_sigla: 'Provincia (Sigla)',
  provincia_nome: 'Provincia (Nome)',
  regione: 'Regione',
  quartiere: 'Quartiere',
  cat1: 'CAT 1',
  cat2: 'CAT 2',
  cat3: 'CAT 3',
  ignore: 'Ignora',
};

const GeoJSONUpload = () => {
  const [file, setFile] = useState<File | null>(null);
  const [geojsonData, setGeojsonData] = useState<any>(null);
  const queryClient = useQueryClient();
  const { uploadState, startUpload, updateProgress, finishUpload } = useUpload();
  const uploadAbortRef = useRef<(() => void) | null>(null);

  // Mapping states
  const [showMappingDialog, setShowMappingDialog] = useState(false);
  const [availableProperties, setAvailableProperties] = useState<string[]>([]);
  const [columnMapping, setColumnMapping] = useState<ColumnMapping>({});
  const [catMapping, setCatMapping] = useState<CATMapping>({
    cat1_intervention: 'both',
    cat2_intervention: 'both',
    cat3_intervention: 'both',
  });
  const [previewFeatures, setPreviewFeatures] = useState<PreviewFeature[]>([]);
  const [detectedCRS, setDetectedCRS] = useState<string>('WGS84');

  // Define coordinate systems
  const EPSG3003 = '+proj=tmerc +lat_0=0 +lon_0=9 +k=0.9996 +x_0=1500000 +y_0=0 +ellps=intl +towgs84=-104.1,-49.1,-9.9,0.971,-2.917,0.714,-11.68 +units=m +no_defs';
  const EPSG32632 = '+proj=utm +zone=32 +datum=WGS84 +units=m +no_defs';
  const WGS84 = 'EPSG:4326';

  // Mapping province -> regione
  const provinciaToRegione: Record<string, string> = {
    'TORINO': 'Piemonte', 'VERCELLI': 'Piemonte', 'NOVARA': 'Piemonte', 'CUNEO': 'Piemonte',
    'ASTI': 'Piemonte', 'ALESSANDRIA': 'Piemonte', 'BIELLA': 'Piemonte', 'VERBANO-CUSIO-OSSOLA': 'Piemonte',
    'MILANO': 'Lombardia', 'BERGAMO': 'Lombardia', 'BRESCIA': 'Lombardia', 'COMO': 'Lombardia',
    'CREMONA': 'Lombardia', 'LECCO': 'Lombardia', 'LODI': 'Lombardia', 'MANTOVA': 'Lombardia',
    'PAVIA': 'Lombardia', 'SONDRIO': 'Lombardia', 'VARESE': 'Lombardia', 'MONZA E DELLA BRIANZA': 'Lombardia',
  };

  // Auto-detect column mapping based on property names
  const autoDetectMapping = (properties: string[]): ColumnMapping => {
    const mapping: ColumnMapping = {};
    
    properties.forEach(prop => {
      const lower = prop.toLowerCase();
      
      if (lower === 'comune' || lower === 'nomcom' || lower === 'nome_com' || lower === 'name') {
        mapping[prop] = 'comune';
      } else if (lower === 'sig_pro' || lower === 'prov' || (lower.includes('provincia') && lower.length <= 12)) {
        mapping[prop] = 'provincia_sigla';
      } else if (lower === 'nome_pro' || lower === 'provincia_nome' || lower.includes('provincia')) {
        mapping[prop] = 'provincia_nome';
      } else if (lower === 'regione' || lower === 'nome_reg' || lower === 'reg') {
        mapping[prop] = 'regione';
      } else if (lower === 'quartiere' || lower === 'denom' || lower === 'neighborhood') {
        mapping[prop] = 'quartiere';
      } else if (lower.includes('cat') && (lower.includes('1') || lower.includes('primo'))) {
        mapping[prop] = 'cat1';
      } else if (lower.includes('cat') && (lower.includes('2') || lower.includes('secondo'))) {
        mapping[prop] = 'cat2';
      } else if (lower.includes('cat') && (lower.includes('3') || lower.includes('terzo'))) {
        mapping[prop] = 'cat3';
      } else {
        mapping[prop] = 'ignore';
      }
    });
    
    return mapping;
  };

  // Update preview when mapping changes
  useEffect(() => {
    if (!geojsonData || !geojsonData.features) return;
    
    const preview = geojsonData.features.slice(0, 5).map((feature: any) => {
      const props = feature.properties || {};
      const mapped: PreviewFeature['mapped'] = {};
      const errors: string[] = [];
      
      Object.entries(columnMapping).forEach(([propName, fieldType]) => {
        const value = props[propName];
        if (!value || fieldType === 'ignore') return;
        
        switch (fieldType) {
          case 'comune':
            mapped.comune = String(value);
            break;
          case 'provincia_sigla':
            mapped.provincia = String(value).toUpperCase();
            break;
          case 'provincia_nome':
            // Convert nome to sigla for preview
            const convertedCode = getProvinceCode(String(value));
            mapped.provincia = convertedCode || (String(value).length <= 3 ? String(value).toUpperCase() : String(value));
            break;
          case 'regione':
            mapped.regione = String(value);
            break;
          case 'quartiere':
            mapped.quartiere = String(value);
            break;
          case 'cat1':
            mapped.cat1 = String(value);
            break;
          case 'cat2':
            mapped.cat2 = String(value);
            break;
          case 'cat3':
            mapped.cat3 = String(value);
            break;
        }
      });
      
      // Validate required fields
      if (!mapped.comune) errors.push('Comune mancante');
      if (!mapped.provincia) errors.push('Provincia mancante');
      
      return { properties: props, mapped, errors };
    });
    
    setPreviewFeatures(preview);
  }, [columnMapping, geojsonData]);

  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const selectedFile = e.target.files?.[0];
    if (!selectedFile) return;
    
    if (!selectedFile.name.endsWith('.json') && !selectedFile.name.endsWith('.geojson')) {
      toast.error('Formato file non valido. Usa .json o .geojson');
      return;
    }
    
    setFile(selectedFile);
    
    try {
      const text = await selectedFile.text();
      const geojson = JSON.parse(text);
      
      if (!geojson.features || !Array.isArray(geojson.features)) {
        throw new Error('GeoJSON non valido: manca features array');
      }
      
      setGeojsonData(geojson);
      
      // Detect CRS
      let crs = 'WGS84';
      if (geojson.crs?.properties?.name) {
        const crsName = geojson.crs.properties.name;
        if (crsName.includes('EPSG::3003') || crsName.includes('3003')) {
          crs = 'EPSG:3003';
        } else if (crsName.includes('EPSG::32632') || crsName.includes('32632')) {
          crs = 'EPSG:32632';
        }
      }
      setDetectedCRS(crs);
      
      // Extract all unique property names from features
      const allProperties = new Set<string>();
      geojson.features.forEach((feature: any) => {
        if (feature.properties) {
          Object.keys(feature.properties).forEach(key => allProperties.add(key));
        }
      });
      
      const propertiesArray = Array.from(allProperties).sort();
      setAvailableProperties(propertiesArray);
      
      // Auto-detect mapping
      const detectedMapping = autoDetectMapping(propertiesArray);
      setColumnMapping(detectedMapping);
      
      // Show mapping dialog
      setShowMappingDialog(true);
      
    } catch (error: any) {
      console.error('Errore parsing GeoJSON:', error);
      toast.error(error.message || 'Errore nel parsing del file');
      setFile(null);
    }
  };

  const updateColumnMapping = (property: string, field: MappableField) => {
    setColumnMapping(prev => ({
      ...prev,
      [property]: field
    }));
  };

  const convertCoordinates = (coordinates: any, fromCRS: string): any => {
    if (fromCRS === WGS84 || fromCRS === 'EPSG:4326' || fromCRS === 'WGS84') {
      return coordinates;
    }

    const sourceCRS = fromCRS === 'EPSG:32632' ? EPSG32632 : EPSG3003;
    
    const convertPoint = (point: [number, number]): [number, number] => {
      const [lng, lat] = proj4(sourceCRS, WGS84, point);
      return [lng, lat];
    };

    const convertRing = (ring: [number, number][]): [number, number][] => {
      return ring.map(convertPoint);
    };

    const convertPolygon = (polygon: [number, number][][]): [number, number][][] => {
      return polygon.map(convertRing);
    };

    if (Array.isArray(coordinates[0][0][0])) {
      return coordinates.map(convertPolygon);
    } else {
      return convertPolygon(coordinates);
    }
  };

  const calculateCentroid = (geometry: any) => {
    let sumLat = 0;
    let sumLng = 0;
    let count = 0;

    const coords = geometry.type === 'MultiPolygon' 
      ? geometry.coordinates[0][0] 
      : geometry.coordinates[0];

    coords.forEach((coord: [number, number]) => {
      sumLng += coord[0];
      sumLat += coord[1];
      count++;
    });

    return {
      lat: sumLat / count,
      lng: sumLng / count
    };
  };

  // Get mapped value from properties based on column mapping
  const getMappedValue = (properties: Record<string, any>, fieldType: MappableField): string | null => {
    for (const [propName, mappedField] of Object.entries(columnMapping)) {
      if (mappedField === fieldType && properties[propName]) {
        return String(properties[propName]);
      }
    }
    return null;
  };

  const handleConfirmAndImport = async () => {
    // Validate mapping
    const hasComuneMapping = Object.values(columnMapping).includes('comune');
    const hasProvinciaMapping = Object.values(columnMapping).includes('provincia_sigla') || 
                                Object.values(columnMapping).includes('provincia_nome');
    
    if (!hasComuneMapping) {
      toast.error('Devi mappare almeno la colonna Comune');
      return;
    }
    
    if (!hasProvinciaMapping) {
      toast.error('Devi mappare almeno la colonna Provincia');
      return;
    }
    
    setShowMappingDialog(false);
    await handleImport();
  };

  const handleImport = async () => {
    if (!geojsonData || !file) return;

    if (uploadState.isUploading) {
      toast.warning('Upload già in corso');
      return;
    }

    try {
      const crs = detectedCRS;
      if (crs !== 'WGS84') {
        toast.info(`Sistema di coordinate ${crs} rilevato, conversione in corso...`);
      }

      // Extract region name from root level if present
      const regionNameFromRoot = geojsonData.name || null;

      const total = geojsonData.features.length;
      startUpload(total);
      toast.info(`Inizio importazione di ${total} comuni...`);

      let imported = 0;
      let errors = 0;
      let shouldAbort = false;

      uploadAbortRef.current = () => {
        shouldAbort = true;
      };

      for (let i = 0; i < geojsonData.features.length; i++) {
        if (shouldAbort) {
          toast.warning('Upload interrotto');
          break;
        }

        const feature = geojsonData.features[i];
        const progressPercent = ((i + 1) / total) * 100;
        
        try {
          const props = feature.properties || {};
          let geometry = feature.geometry;

          if (!geometry || (geometry.type !== 'Polygon' && geometry.type !== 'MultiPolygon')) {
            console.warn('Geometria non valida, skip:', props);
            errors++;
            continue;
          }

          // Convert coordinates if necessary
          if (crs !== 'WGS84') {
            const convertedCoords = convertCoordinates(geometry.coordinates, crs);
            geometry = {
              type: geometry.type,
              coordinates: convertedCoords
            };
          }

          // Convert Polygon to MultiPolygon if needed
          const multiPolygonGeom = geometry.type === 'Polygon'
            ? { type: 'MultiPolygon', coordinates: [geometry.coordinates] }
            : geometry;

          const centroid = calculateCentroid(geometry);
          
          // Get mapped values
          let rawComuneName = getMappedValue(props, 'comune') || 'Sconosciuto';
          const provinciaSigla = getMappedValue(props, 'provincia_sigla');
          const provinciaNome = getMappedValue(props, 'provincia_nome');
          
          // Convert provincia nome to sigla if needed
          let provincia: string | null = null;
          if (provinciaSigla) {
            // Already a sigla, use directly (max 2-3 chars)
            provincia = provinciaSigla.toUpperCase();
          } else if (provinciaNome) {
            // Convert nome to sigla
            const convertedCode = getProvinceCode(provinciaNome);
            if (convertedCode) {
              provincia = convertedCode;
            } else {
              // Fallback: if it's short, it might already be a sigla, otherwise use as-is
              provincia = provinciaNome.length <= 3 ? provinciaNome.toUpperCase() : provinciaNome;
              console.warn(`Provincia "${provinciaNome}" non trovata nella mappa, usato valore originale`);
            }
          }
          
          const quartiere = getMappedValue(props, 'quartiere');
          
          // Parse bilingual names: "NomeItaliano/NomeStraniero"
          let communeName = rawComuneName;
          let communeAlias: string | null = null;
          
          if (rawComuneName.includes('/') && !rawComuneName.includes(' / ')) {
            const parts = rawComuneName.split('/');
            if (parts.length === 2 && parts[0].trim() && parts[1].trim()) {
              communeName = parts[0].trim();
              communeAlias = parts[1].trim();
            }
          }
          
          // Derive regione
          let regione = getMappedValue(props, 'regione') || regionNameFromRoot || null;
          if (!regione && provincia) {
            regione = provinciaToRegione[provincia.toUpperCase()] || null;
          }

          // For neighborhoods, find existing commune
          let finalComuneName = quartiere ? communeName : communeName;
          let finalQuartiere = quartiere;
          let finalRegione = regione;
          let finalProvincia = provincia;
          
          if (quartiere && finalComuneName) {
            const { data: existingCommune } = await supabase
              .from('communes')
              .select('comune, regione, provincia')
              .ilike('comune', finalComuneName)
              .is('quartiere', null)
              .limit(1)
              .maybeSingle();
            
            if (existingCommune) {
              finalComuneName = existingCommune.comune;
              finalRegione = existingCommune.regione;
              finalProvincia = existingCommune.provincia;
            }
          }
          
          // Get CAT values
          const cat1 = getMappedValue(props, 'cat1');
          const cat2 = getMappedValue(props, 'cat2');
          const cat3 = getMappedValue(props, 'cat3');
          
          updateProgress(communeName, progressPercent, imported, errors);

          const quartiereFinal = finalQuartiere || '';
          
          // Upsert commune
          const { data: communeData, error } = await supabase
            .from('communes')
            .upsert({
              comune: finalComuneName,
              alias: communeAlias,
              quartiere: quartiereFinal,
              provincia: finalProvincia || '',
              regione: finalRegione,
              geom: multiPolygonGeom,
              centroid_lat: centroid.lat,
              centroid_lng: centroid.lng
            }, {
              onConflict: 'comune,provincia,quartiere',
              ignoreDuplicates: false
            })
            .select('id')
            .single();

          if (error) {
            console.error('Errore inserimento comune:', error);
            errors++;
          } else {
            imported++;
            
            // Process CAT associations with intervention types
            const catConfigs = [
              { name: cat1, intervention: catMapping.cat1_intervention, isPrimary: true },
              { name: cat2, intervention: catMapping.cat2_intervention, isPrimary: false },
              { name: cat3, intervention: catMapping.cat3_intervention, isPrimary: false },
            ].filter(c => c.name);
            
            if (catConfigs.length > 0 && communeData?.id) {
              for (const catConfig of catConfigs) {
                const { data: catData } = await supabase
                  .from('cats')
                  .select('id')
                  .ilike('name', catConfig.name!)
                  .maybeSingle();
                
                if (catData?.id) {
                  const { error: assocError } = await supabase
                    .from('cat_commune')
                    .upsert({
                      cat_id: catData.id,
                      commune_id: communeData.id,
                      is_primary: catConfig.isPrimary,
                      intervention_type: catConfig.intervention,
                      active: true
                    }, {
                      onConflict: 'cat_id,commune_id',
                      ignoreDuplicates: false
                    });
                  
                  if (assocError) {
                    console.error('Error creating CAT association:', assocError);
                  }
                } else {
                  console.warn(`CAT not found: ${catConfig.name}`);
                }
              }
            }
          }
        } catch (err) {
          console.error('Errore processing feature:', err);
          errors++;
        }
      }

      if (imported > 0) {
        toast.success(`Importati ${imported} comuni con successo!`);
      }
      if (errors > 0) {
        toast.warning(`${errors} comuni saltati per errori`);
      }

      await queryClient.invalidateQueries({ queryKey: ['communes-admin-paginated'] });
      await queryClient.invalidateQueries({ queryKey: ['communes-all-paginated'] });
      await queryClient.refetchQueries({ queryKey: ['communes-admin-paginated'] });
      await queryClient.refetchQueries({ queryKey: ['communes-all-paginated'] });

      setFile(null);
      setGeojsonData(null);
      finishUpload();
      uploadAbortRef.current = null;
    } catch (error: any) {
      console.error('Errore upload:', error);
      toast.error(error.message || 'Errore durante l\'upload');
      finishUpload();
      uploadAbortRef.current = null;
    }
  };

  // Check if required fields are mapped
  const hasComuneMapping = Object.values(columnMapping).includes('comune');
  const hasProvinciaMapping = Object.values(columnMapping).includes('provincia_sigla') || 
                              Object.values(columnMapping).includes('provincia_nome');
  const hasCatMapping = Object.values(columnMapping).includes('cat1') || 
                        Object.values(columnMapping).includes('cat2') || 
                        Object.values(columnMapping).includes('cat3');

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-4">
        <div className="flex-1">
          <Input
            type="file"
            accept=".json,.geojson"
            onChange={handleFileChange}
            disabled={uploadState.isUploading}
          />
        </div>
        {file && (
          <div className="flex items-center gap-2 text-sm text-muted-foreground">
            <FileJson className="h-4 w-4" />
            {file.name}
          </div>
        )}
      </div>

      {file && !showMappingDialog && !uploadState.isUploading && (
        <Button
          onClick={() => setShowMappingDialog(true)}
          variant="outline"
          className="w-full"
        >
          <Settings2 className="h-4 w-4 mr-2" />
          Configura Mapping Colonne
        </Button>
      )}

      {uploadState.isUploading && (
        <div className="space-y-2">
          <Button
            variant="destructive"
            onClick={() => {
              if (uploadAbortRef.current) {
                uploadAbortRef.current();
                toast.info('Interruzione import richiesta...');
              }
            }}
            className="w-full"
          >
            Annulla Import
          </Button>
          <div className="text-sm text-muted-foreground text-center p-4 bg-muted/50 rounded-lg">
            <p className="font-medium">Upload in corso in background</p>
            <p className="text-xs mt-1">
              Puoi navigare liberamente. Lo stato verrà mostrato in basso a destra.
            </p>
          </div>
        </div>
      )}

      {/* Mapping Dialog */}
      <Dialog open={showMappingDialog} onOpenChange={setShowMappingDialog}>
        <DialogContent className="max-w-4xl max-h-[90vh] overflow-hidden flex flex-col">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Settings2 className="h-5 w-5" />
              Configura Mapping Colonne
            </DialogTitle>
            <DialogDescription>
              Mappa le colonne del file GeoJSON ai campi del database. 
              <strong> Comune</strong> e <strong>Provincia</strong> sono obbligatori.
            </DialogDescription>
          </DialogHeader>

          <div className="flex-1 overflow-hidden flex flex-col gap-4">
            {/* Info badges */}
            <div className="flex flex-wrap gap-2">
              <Badge variant="outline">
                {geojsonData?.features?.length || 0} features
              </Badge>
              <Badge variant={detectedCRS === 'WGS84' ? 'secondary' : 'default'}>
                CRS: {detectedCRS}
              </Badge>
              {hasComuneMapping && (
                <Badge variant="default" className="bg-green-600">
                  <Check className="h-3 w-3 mr-1" />
                  Comune
                </Badge>
              )}
              {hasProvinciaMapping && (
                <Badge variant="default" className="bg-green-600">
                  <Check className="h-3 w-3 mr-1" />
                  Provincia
                </Badge>
              )}
              {!hasComuneMapping && (
                <Badge variant="destructive">
                  <AlertTriangle className="h-3 w-3 mr-1" />
                  Comune mancante
                </Badge>
              )}
              {!hasProvinciaMapping && (
                <Badge variant="destructive">
                  <AlertTriangle className="h-3 w-3 mr-1" />
                  Provincia mancante
                </Badge>
              )}
            </div>

            <ScrollArea className="flex-1">
              <div className="space-y-6 pr-4">
                {/* Column Mapping */}
                <div>
                  <h4 className="text-sm font-semibold mb-3">Mapping Colonne</h4>
                  <div className="grid grid-cols-2 gap-3">
                    {availableProperties.map(prop => (
                      <div key={prop} className="flex items-center gap-2">
                        <Label className="w-32 truncate text-xs" title={prop}>
                          {prop}
                        </Label>
                        <Select
                          value={columnMapping[prop] || 'ignore'}
                          onValueChange={(value) => updateColumnMapping(prop, value as MappableField)}
                        >
                          <SelectTrigger className="flex-1 h-8 text-xs">
                            <SelectValue />
                          </SelectTrigger>
                          <SelectContent>
                            {Object.entries(FIELD_LABELS).map(([value, label]) => (
                              <SelectItem key={value} value={value} className="text-xs">
                                {label}
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </div>
                    ))}
                  </div>
                </div>

                <Separator />

                {/* CAT Intervention Types */}
                {hasCatMapping && (
                  <div>
                    <h4 className="text-sm font-semibold mb-3">Tipo Intervento per CAT</h4>
                    <div className="grid grid-cols-3 gap-4">
                      {Object.values(columnMapping).includes('cat1') && (
                        <div>
                          <Label className="text-xs">CAT 1</Label>
                          <Select
                            value={catMapping.cat1_intervention}
                            onValueChange={(value) => setCatMapping(prev => ({
                              ...prev,
                              cat1_intervention: value as InterventionType
                            }))}
                          >
                            <SelectTrigger className="h-8 text-xs mt-1">
                              <SelectValue />
                            </SelectTrigger>
                            <SelectContent>
                              {INTERVENTION_TYPES.map(type => (
                                <SelectItem key={type.value} value={type.value} className="text-xs">
                                  {type.label}
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </div>
                      )}
                      {Object.values(columnMapping).includes('cat2') && (
                        <div>
                          <Label className="text-xs">CAT 2</Label>
                          <Select
                            value={catMapping.cat2_intervention}
                            onValueChange={(value) => setCatMapping(prev => ({
                              ...prev,
                              cat2_intervention: value as InterventionType
                            }))}
                          >
                            <SelectTrigger className="h-8 text-xs mt-1">
                              <SelectValue />
                            </SelectTrigger>
                            <SelectContent>
                              {INTERVENTION_TYPES.map(type => (
                                <SelectItem key={type.value} value={type.value} className="text-xs">
                                  {type.label}
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </div>
                      )}
                      {Object.values(columnMapping).includes('cat3') && (
                        <div>
                          <Label className="text-xs">CAT 3</Label>
                          <Select
                            value={catMapping.cat3_intervention}
                            onValueChange={(value) => setCatMapping(prev => ({
                              ...prev,
                              cat3_intervention: value as InterventionType
                            }))}
                          >
                            <SelectTrigger className="h-8 text-xs mt-1">
                              <SelectValue />
                            </SelectTrigger>
                            <SelectContent>
                              {INTERVENTION_TYPES.map(type => (
                                <SelectItem key={type.value} value={type.value} className="text-xs">
                                  {type.label}
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </div>
                      )}
                    </div>
                  </div>
                )}

                <Separator />

                {/* Preview Table */}
                <div>
                  <h4 className="text-sm font-semibold mb-3">
                    Anteprima (prime 5 righe)
                  </h4>
                  <Card>
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <TableHead className="text-xs">Comune</TableHead>
                          <TableHead className="text-xs">Provincia</TableHead>
                          <TableHead className="text-xs">Regione</TableHead>
                          <TableHead className="text-xs">Quartiere</TableHead>
                          <TableHead className="text-xs">CAT</TableHead>
                          <TableHead className="text-xs">Stato</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {previewFeatures.map((feature, idx) => (
                          <TableRow key={idx}>
                            <TableCell className="text-xs">
                              {feature.mapped.comune || <span className="text-destructive">-</span>}
                            </TableCell>
                            <TableCell className="text-xs">
                              {feature.mapped.provincia || <span className="text-destructive">-</span>}
                            </TableCell>
                            <TableCell className="text-xs">
                              {feature.mapped.regione || '-'}
                            </TableCell>
                            <TableCell className="text-xs">
                              {feature.mapped.quartiere || '-'}
                            </TableCell>
                            <TableCell className="text-xs">
                              {[feature.mapped.cat1, feature.mapped.cat2, feature.mapped.cat3]
                                .filter(Boolean)
                                .join(', ') || '-'}
                            </TableCell>
                            <TableCell>
                              {feature.errors.length === 0 ? (
                                <Badge variant="outline" className="text-xs text-green-600">
                                  <Check className="h-3 w-3 mr-1" />
                                  OK
                                </Badge>
                              ) : (
                                <Badge variant="destructive" className="text-xs">
                                  {feature.errors.join(', ')}
                                </Badge>
                              )}
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </Card>
                </div>
              </div>
            </ScrollArea>
          </div>

          <DialogFooter className="mt-4">
            <Button variant="outline" onClick={() => setShowMappingDialog(false)}>
              Annulla
            </Button>
            <Button 
              onClick={handleConfirmAndImport}
              disabled={!hasComuneMapping || !hasProvinciaMapping}
            >
              <Upload className="h-4 w-4 mr-2" />
              Importa {geojsonData?.features?.length || 0} comuni
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <div className="mt-4 p-4 bg-muted/50 rounded-lg text-sm text-muted-foreground">
        <h4 className="font-medium mb-2">Come funziona:</h4>
        <ol className="list-decimal list-inside space-y-1 text-xs">
          <li>Seleziona un file GeoJSON</li>
          <li>Configura il mapping delle colonne nella modale</li>
          <li>Per i CAT, specifica il tipo di intervento (Sopralluogo, RFS, Entrambi)</li>
          <li>Verifica l'anteprima e avvia l'import</li>
        </ol>
      </div>
    </div>
  );
};

export default GeoJSONUpload;
