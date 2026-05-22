import { useState, useEffect, useRef } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useQueryClient } from '@tanstack/react-query';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Progress } from '@/components/ui/progress';
import { toast } from 'sonner';
import { Upload, FileJson, Trash2, Settings2, Check, AlertTriangle, Loader2 } from 'lucide-react';
import { useUpload } from '@/contexts/UploadContext';
import { Card } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Separator } from '@/components/ui/separator';
import proj4 from 'proj4';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
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

type BoundaryType = 'province' | 'region';

// Province fields
type ProvinceMappableField = 'nome' | 'sigla' | 'regione' | 'ignore';
// Region fields  
type RegionMappableField = 'nome' | 'ignore';

interface ColumnMapping {
  [propertyName: string]: string;
}

interface PreviewFeature {
  properties: Record<string, any>;
  mapped: Record<string, string>;
  errors: string[];
}

const PROVINCE_FIELD_LABELS: Record<ProvinceMappableField, string> = {
  nome: 'Nome Provincia',
  sigla: 'Sigla Provincia',
  regione: 'Regione',
  ignore: 'Ignora',
};

const REGION_FIELD_LABELS: Record<RegionMappableField, string> = {
  nome: 'Nome Regione',
  ignore: 'Ignora',
};

interface BoundaryUploadProps {
  provinceCount: number;
  regionCount: number;
  onRefresh: () => void;
}

const BoundaryUpload = ({ provinceCount, regionCount, onRefresh }: BoundaryUploadProps) => {
  const [file, setFile] = useState<File | null>(null);
  const [geojsonData, setGeojsonData] = useState<any>(null);
  const [boundaryType, setBoundaryType] = useState<BoundaryType>('province');
  const queryClient = useQueryClient();
  const { uploadState, startUpload, updateProgress, finishUpload } = useUpload();
  const uploadAbortRef = useRef<(() => void) | null>(null);
  
  // Local progress state for boundary-specific progress display
  const [localProgress, setLocalProgress] = useState({
    isRunning: false,
    current: '',
    progress: 0,
    imported: 0,
    errors: 0,
    total: 0
  });

  // Mapping states
  const [showMappingDialog, setShowMappingDialog] = useState(false);
  const [availableProperties, setAvailableProperties] = useState<string[]>([]);
  const [columnMapping, setColumnMapping] = useState<ColumnMapping>({});
  const [previewFeatures, setPreviewFeatures] = useState<PreviewFeature[]>([]);
  const [detectedCRS, setDetectedCRS] = useState<string>('WGS84');

  // Define coordinate systems
  const EPSG3003 = '+proj=tmerc +lat_0=0 +lon_0=9 +k=0.9996 +x_0=1500000 +y_0=0 +ellps=intl +towgs84=-104.1,-49.1,-9.9,0.971,-2.917,0.714,-11.68 +units=m +no_defs';
  const EPSG32632 = '+proj=utm +zone=32 +datum=WGS84 +units=m +no_defs';
  const WGS84 = 'EPSG:4326';

  // Auto-detect column mapping based on property names and boundary type
  const autoDetectMapping = (properties: string[], type: BoundaryType): ColumnMapping => {
    const mapping: ColumnMapping = {};
    
    properties.forEach(prop => {
      const lower = prop.toLowerCase();
      
      if (type === 'province') {
        if (lower === 'nome_pro' || lower === 'den_uts' || lower === 'provincia' || lower === 'name' || lower === 'nome') {
          mapping[prop] = 'nome';
        } else if (lower === 'sig_pro' || lower === 'sigla' || lower === 'cod_pro' || lower === 'prov') {
          mapping[prop] = 'sigla';
        } else if (lower === 'nome_reg' || lower === 'regione' || lower === 'den_reg' || lower === 'reg') {
          mapping[prop] = 'regione';
        } else {
          mapping[prop] = 'ignore';
        }
      } else {
        // Region
        if (lower === 'nome_reg' || lower === 'regione' || lower === 'den_reg' || lower === 'name' || lower === 'nome') {
          mapping[prop] = 'nome';
        } else {
          mapping[prop] = 'ignore';
        }
      }
    });
    
    return mapping;
  };

  // Update preview when mapping changes
  useEffect(() => {
    if (!geojsonData || !geojsonData.features) return;
    
    const preview = geojsonData.features.slice(0, 5).map((feature: any) => {
      const props = feature.properties || {};
      const mapped: Record<string, string> = {};
      const errors: string[] = [];
      
      Object.entries(columnMapping).forEach(([propName, fieldType]) => {
        const value = props[propName];
        if (!value || fieldType === 'ignore') return;
        
        mapped[fieldType] = String(value);
      });
      
      // Validate required fields based on boundary type
      if (boundaryType === 'province') {
        if (!mapped.nome && !mapped.sigla) {
          errors.push('Nome o Sigla mancante');
        }
      } else {
        if (!mapped.nome) {
          errors.push('Nome mancante');
        }
      }
      
      return { properties: props, mapped, errors };
    });
    
    setPreviewFeatures(preview);
  }, [columnMapping, geojsonData, boundaryType]);

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
      const detectedMapping = autoDetectMapping(propertiesArray, boundaryType);
      setColumnMapping(detectedMapping);
      
      // Show mapping dialog
      setShowMappingDialog(true);
      
    } catch (error: any) {
      console.error('Errore parsing GeoJSON:', error);
      toast.error(error.message || 'Errore nel parsing del file');
      setFile(null);
    }
  };

  // Re-detect mapping when boundary type changes and we have data
  useEffect(() => {
    if (availableProperties.length > 0) {
      const detectedMapping = autoDetectMapping(availableProperties, boundaryType);
      setColumnMapping(detectedMapping);
    }
  }, [boundaryType, availableProperties]);

  const updateColumnMapping = (property: string, field: string) => {
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

  // Get mapped value from properties based on column mapping
  const getMappedValue = (properties: Record<string, any>, fieldType: string): string | null => {
    for (const [propName, mappedField] of Object.entries(columnMapping)) {
      if (mappedField === fieldType && properties[propName]) {
        return String(properties[propName]);
      }
    }
    return null;
  };

  // Check if required fields are mapped
  const hasRequiredMapping = () => {
    if (boundaryType === 'province') {
      return Object.values(columnMapping).includes('nome') || Object.values(columnMapping).includes('sigla');
    } else {
      return Object.values(columnMapping).includes('nome');
    }
  };

  const hasNomeMapping = Object.values(columnMapping).includes('nome');
  const hasSiglaMapping = Object.values(columnMapping).includes('sigla');
  const hasRegioneMapping = Object.values(columnMapping).includes('regione');

  const handleConfirmAndImport = async () => {
    if (!hasRequiredMapping()) {
      if (boundaryType === 'province') {
        toast.error('Devi mappare almeno Nome o Sigla provincia');
      } else {
        toast.error('Devi mappare il Nome regione');
      }
      return;
    }
    
    setShowMappingDialog(false);
    await handleImport();
  };

  const handleImport = async () => {
    if (!geojsonData || !file) return;

    if (localProgress.isRunning || uploadState.isUploading) {
      toast.warning('Upload già in corso');
      return;
    }

    try {
      const crs = detectedCRS;
      if (crs !== 'WGS84') {
        toast.info(`Sistema di coordinate ${crs} rilevato, conversione in corso...`);
      }

      const label = boundaryType === 'province' ? 'province' : 'regioni';
      const total = geojsonData.features.length;
      
      // Initialize progress
      setLocalProgress({
        isRunning: true,
        current: '',
        progress: 0,
        imported: 0,
        errors: 0,
        total
      });
      startUpload(total);
      toast.info(`Inizio importazione di ${total} ${label}...`);
      
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
            geometry = {
              type: geometry.type,
              coordinates: convertCoordinates(geometry.coordinates, crs)
            };
          }

          // Get mapped values
          const nome = getMappedValue(props, 'nome');
          const sigla = getMappedValue(props, 'sigla');
          const regione = getMappedValue(props, 'regione');

          // Determine the name to use
          let name: string;
          if (boundaryType === 'province') {
            name = nome || sigla || '';
          } else {
            name = nome || '';
          }

          if (!name) {
            console.warn('Nome mancante, skip:', props);
            errors++;
            continue;
          }

          // Update progress
          setLocalProgress(prev => ({
            ...prev,
            current: name,
            progress: progressPercent,
            imported,
            errors
          }));
          updateProgress(name, progressPercent, imported, errors);

          // Call edge function for import (bypasses RLS)
          const { data, error } = await supabase.functions.invoke('geojson-backup-manager', {
            body: {
              action: 'import_boundary',
              boundary_type: boundaryType,
              name: name.toUpperCase(),
              geom: geometry,
              regione: boundaryType === 'province' ? regione : undefined
            }
          });

          if (error || data?.status === 'error') {
            console.error(`Errore inserimento ${boundaryType}:`, error || data?.error);
            errors++;
          } else {
            imported++;
          }
        } catch (err) {
          console.error('Errore processing feature:', err);
          errors++;
        }
      }

      // Final progress update
      setLocalProgress(prev => ({
        ...prev,
        progress: 100,
        imported,
        errors
      }));

      if (imported > 0) {
        toast.success(`Importate ${imported} ${label}`);
      }
      if (errors > 0) {
        toast.warning(`${errors} elementi saltati per errori`);
      }

      onRefresh();
      setFile(null);
      setGeojsonData(null);
    } catch (error: any) {
      console.error('Errore upload:', error);
      toast.error(error.message || 'Errore durante l\'upload');
    } finally {
      setLocalProgress(prev => ({ ...prev, isRunning: false }));
      finishUpload();
      uploadAbortRef.current = null;
    }
  };

  const handleClear = async (type: BoundaryType) => {
    const tableName = type === 'province' ? 'provinces' : 'regions';
    const label = type === 'province' ? 'province' : 'regioni';
    
    if (!confirm(`Eliminare tutte le ${label}?`)) return;

    try {
      const { error } = await (supabase as any).from(tableName).delete().neq('id', '00000000-0000-0000-0000-000000000000');
      if (error) throw error;
      toast.success(`${label.charAt(0).toUpperCase() + label.slice(1)} eliminate`);
      onRefresh();
    } catch (error: any) {
      toast.error(`Errore: ${error.message}`);
    }
  };

  const getFieldLabels = () => {
    return boundaryType === 'province' ? PROVINCE_FIELD_LABELS : REGION_FIELD_LABELS;
  };

  return (
    <Card className="p-4 space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="font-medium">Confini Amministrativi</h3>
        <div className="flex gap-2">
          <Badge variant={provinceCount > 0 ? 'default' : 'secondary'}>
            {provinceCount} province
          </Badge>
          <Badge variant={regionCount > 0 ? 'default' : 'secondary'}>
            {regionCount} regioni
          </Badge>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-4">
        <div className="space-y-2">
          <Label>Tipo confine</Label>
          <Select value={boundaryType} onValueChange={(v) => setBoundaryType(v as BoundaryType)}>
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="province">Province</SelectItem>
              <SelectItem value="region">Regioni</SelectItem>
            </SelectContent>
          </Select>
        </div>
        
        <div className="space-y-2">
          <Label>File GeoJSON</Label>
          <Input
            type="file"
            accept=".json,.geojson"
            onChange={handleFileChange}
            disabled={localProgress.isRunning}
          />
        </div>
      </div>

      {file && (
        <div className="flex items-center gap-2 text-sm text-muted-foreground">
          <FileJson className="h-4 w-4" />
          {file.name}
        </div>
      )}

      {file && !showMappingDialog && !localProgress.isRunning && (
        <Button
          onClick={() => setShowMappingDialog(true)}
          variant="outline"
          className="w-full"
        >
          <Settings2 className="h-4 w-4 mr-2" />
          Configura Mapping Colonne
        </Button>
      )}

      {/* Progress UI */}
      {localProgress.isRunning && (
        <div className="space-y-3 p-4 rounded-lg border bg-blue-500/10 border-blue-500/50">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Loader2 className="h-4 w-4 animate-spin text-blue-500" />
              <span className="font-medium text-sm">
                Importazione {boundaryType === 'province' ? 'province' : 'regioni'} in corso...
              </span>
            </div>
            <Badge variant="outline">
              {localProgress.imported + localProgress.errors}/{localProgress.total}
            </Badge>
          </div>
          
          <Progress value={localProgress.progress} className="h-2" />
          
          {localProgress.current && (
            <div className="flex items-center justify-between text-xs">
              <span className="text-muted-foreground">
                Processando: <span className="font-medium text-foreground">{localProgress.current}</span>
              </span>
              <span className="text-muted-foreground">
                {Math.round(localProgress.progress)}%
              </span>
            </div>
          )}
          
          <div className="flex items-center gap-4 text-xs text-muted-foreground">
            <span className="flex items-center gap-1">
              <Check className="h-3 w-3 text-green-500" />
              {localProgress.imported} importate
            </span>
            {localProgress.errors > 0 && (
              <span className="flex items-center gap-1">
                <AlertTriangle className="h-3 w-3 text-red-500" />
                {localProgress.errors} errori
              </span>
            )}
          </div>
          
          <div className="text-xs text-yellow-600 dark:text-yellow-400 bg-yellow-500/10 p-2 rounded">
            ⚠️ Non chiudere questa pagina durante l'importazione.
          </div>
          
          <Button
            variant="destructive"
            size="sm"
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
        </div>
      )}

      <div className="flex gap-2 pt-2 border-t">
        <Button
          variant="outline"
          size="sm"
          onClick={() => handleClear('province')}
          disabled={provinceCount === 0 || localProgress.isRunning}
          className="flex-1"
        >
          <Trash2 className="h-4 w-4 mr-2" />
          Svuota Province
        </Button>
        <Button
          variant="outline"
          size="sm"
          onClick={() => handleClear('region')}
          disabled={regionCount === 0 || localProgress.isRunning}
          className="flex-1"
        >
          <Trash2 className="h-4 w-4 mr-2" />
          Svuota Regioni
        </Button>
      </div>

      {/* Mapping Dialog */}
      <Dialog open={showMappingDialog} onOpenChange={setShowMappingDialog}>
        <DialogContent className="max-w-3xl max-h-[90vh] overflow-hidden flex flex-col">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Settings2 className="h-5 w-5" />
              Configura Mapping - {boundaryType === 'province' ? 'Province' : 'Regioni'}
            </DialogTitle>
            <DialogDescription>
              {boundaryType === 'province' 
                ? 'Mappa le colonne. Almeno Nome o Sigla è obbligatorio.'
                : 'Mappa le colonne. Nome regione è obbligatorio.'
              }
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
              
              {boundaryType === 'province' ? (
                <>
                  {(hasNomeMapping || hasSiglaMapping) ? (
                    <Badge variant="default" className="bg-green-600">
                      <Check className="h-3 w-3 mr-1" />
                      {hasNomeMapping ? 'Nome' : 'Sigla'}
                    </Badge>
                  ) : (
                    <Badge variant="destructive">
                      <AlertTriangle className="h-3 w-3 mr-1" />
                      Nome/Sigla mancante
                    </Badge>
                  )}
                  {hasRegioneMapping && (
                    <Badge variant="secondary">
                      <Check className="h-3 w-3 mr-1" />
                      Regione
                    </Badge>
                  )}
                </>
              ) : (
                hasNomeMapping ? (
                  <Badge variant="default" className="bg-green-600">
                    <Check className="h-3 w-3 mr-1" />
                    Nome
                  </Badge>
                ) : (
                  <Badge variant="destructive">
                    <AlertTriangle className="h-3 w-3 mr-1" />
                    Nome mancante
                  </Badge>
                )
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
                          onValueChange={(value) => updateColumnMapping(prop, value)}
                        >
                          <SelectTrigger className="flex-1 h-8 text-xs">
                            <SelectValue />
                          </SelectTrigger>
                          <SelectContent>
                            {Object.entries(getFieldLabels()).map(([value, label]) => (
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

                {/* Preview Table */}
                <div>
                  <h4 className="text-sm font-semibold mb-3">
                    Anteprima (prime 5 righe)
                  </h4>
                  <Card>
                    <Table>
                      <TableHeader>
                        <TableRow>
                          {boundaryType === 'province' ? (
                            <>
                              <TableHead className="text-xs">Nome</TableHead>
                              <TableHead className="text-xs">Sigla</TableHead>
                              <TableHead className="text-xs">Regione</TableHead>
                            </>
                          ) : (
                            <TableHead className="text-xs">Nome</TableHead>
                          )}
                          <TableHead className="text-xs">Stato</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {previewFeatures.map((feature, idx) => (
                          <TableRow key={idx}>
                            {boundaryType === 'province' ? (
                              <>
                                <TableCell className="text-xs">
                                  {feature.mapped.nome || '-'}
                                </TableCell>
                                <TableCell className="text-xs">
                                  {feature.mapped.sigla || '-'}
                                </TableCell>
                                <TableCell className="text-xs">
                                  {feature.mapped.regione || '-'}
                                </TableCell>
                              </>
                            ) : (
                              <TableCell className="text-xs">
                                {feature.mapped.nome || <span className="text-destructive">-</span>}
                              </TableCell>
                            )}
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
              disabled={!hasRequiredMapping()}
            >
              <Upload className="h-4 w-4 mr-2" />
              Importa {geojsonData?.features?.length || 0} {boundaryType === 'province' ? 'province' : 'regioni'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <div className="text-xs text-muted-foreground">
        <p>Seleziona un file GeoJSON e configura il mapping delle colonne.</p>
      </div>
    </Card>
  );
};

export default BoundaryUpload;
