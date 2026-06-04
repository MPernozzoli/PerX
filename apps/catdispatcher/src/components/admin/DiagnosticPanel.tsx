import { useDiagnostics } from '@/contexts/DiagnosticContext';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { RefreshCw, CheckCircle2, XCircle, AlertCircle, Database, Server, Key, Users, Map, Trash2, AlertTriangle } from 'lucide-react';
import { Separator } from '@/components/ui/separator';
import { Switch } from '@/components/ui/switch';
import { Label } from '@/components/ui/label';
import { forceReloadMapData } from '@/lib/cacheUtils';
import { toast } from 'sonner';

interface DiagnosticPanelProps {
  selectedRegions?: string[];
}

export const DiagnosticPanel = ({ selectedRegions = [] }: DiagnosticPanelProps) => {
  const { diagnostics, isRunning, lastRun, isUnderMaintenance, setIsUnderMaintenance, runDiagnostics } = useDiagnostics();

  const handleResetCache = async () => {
    if (confirm('Sei sicuro di voler resettare tutta la cache? La pagina verrà ricaricata.')) {
      toast.loading('Reset cache in corso...');
      await forceReloadMapData();
    }
  };

  const getStatusIcon = (status: 'ok' | 'warning' | 'error') => {
    switch (status) {
      case 'ok':
        return <CheckCircle2 className="h-5 w-5 text-green-500" />;
      case 'warning':
        return <AlertCircle className="h-5 w-5 text-yellow-500" />;
      case 'error':
        return <XCircle className="h-5 w-5 text-red-500" />;
    }
  };

  const getStatusBadge = (status: 'ok' | 'warning' | 'error') => {
    const variants: Record<string, 'default' | 'destructive' | 'outline' | 'secondary'> = {
      ok: 'default',
      warning: 'secondary',
      error: 'destructive',
    };
    return (
      <Badge variant={variants[status]}>
        {status === 'ok' ? 'OK' : status === 'warning' ? 'ATTENZIONE' : 'ERRORE'}
      </Badge>
    );
  };

  const DiagnosticItem = ({ 
    icon: Icon, 
    title, 
    diagnostic 
  }: { 
    icon: any, 
    title: string, 
    diagnostic: { status: 'ok' | 'warning' | 'error', message: string, details?: string }
  }) => (
    <div className="space-y-2">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Icon className="h-5 w-5 text-muted-foreground" />
          <div>
            <h4 className="font-medium text-sm">{title}</h4>
            <p className="text-sm text-muted-foreground">{diagnostic.message}</p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          {getStatusIcon(diagnostic.status)}
          {getStatusBadge(diagnostic.status)}
        </div>
      </div>
      {diagnostic.details && (
        <p className="text-xs text-muted-foreground ml-8 pl-3 border-l-2 border-border">
          {diagnostic.details}
        </p>
      )}
    </div>
  );

  return (
    <Card>
      <CardHeader>
        <div className="flex items-center justify-between">
          <div>
            <CardTitle className="flex items-center gap-2">
              <Server className="h-5 w-5" />
              Diagnostica Sistema
            </CardTitle>
            <CardDescription>
              Stato in tempo reale delle componenti dell'applicazione
            </CardDescription>
          </div>
          <div className="flex items-center gap-2">
            <Button
              variant="destructive"
              size="sm"
              onClick={handleResetCache}
            >
              <Trash2 className="h-4 w-4 mr-2" />
              Reset Cache
            </Button>
            <Button
              variant="outline"
              size="sm"
              onClick={() => runDiagnostics(true)}
              disabled={isRunning}
            >
              <RefreshCw className={`h-4 w-4 mr-2 ${isRunning ? 'animate-spin' : ''}`} />
              {isRunning ? 'Analisi...' : 'Riesegui'}
            </Button>
          </div>
        </div>
        
        {/* Maintenance Mode Toggle */}
        <div className={`mt-4 p-3 rounded-lg border ${isUnderMaintenance ? 'bg-yellow-500/10 border-yellow-500/50' : 'bg-muted/50 border-border'}`}>
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <AlertTriangle className={`h-5 w-5 ${isUnderMaintenance ? 'text-yellow-500' : 'text-muted-foreground'}`} />
              <div>
                <Label htmlFor="maintenance-mode" className="text-sm font-medium cursor-pointer">
                  Modalità Manutenzione
                </Label>
                <p className="text-xs text-muted-foreground">
                  {isUnderMaintenance 
                    ? 'Sistema in riparazione - gli utenti vedranno un avviso' 
                    : 'Attiva per informare gli utenti di lavori in corso'}
                </p>
              </div>
            </div>
            <Switch
              id="maintenance-mode"
              checked={isUnderMaintenance}
              onCheckedChange={setIsUnderMaintenance}
            />
          </div>
        </div>
        
        {lastRun && (
          <p className="text-xs text-muted-foreground mt-2">
            Ultima esecuzione: {lastRun.toLocaleString('it-IT')}
          </p>
        )}
      </CardHeader>
      <CardContent className="space-y-4">
        {!diagnostics ? (
          <div className="flex flex-col items-center justify-center py-8 gap-4">
            <p className="text-sm text-muted-foreground text-center">
              Nessun dato nella tabella system_diagnostics.
            </p>
            <p className="text-xs text-muted-foreground text-center max-w-md">
              Esegui la prima diagnostica: clicca &quot;Riesegui&quot; sopra. Verifica che la migration sia applicata e che run-diagnostics sia deployata.
            </p>
            <Button
              variant="outline"
              size="sm"
              onClick={() => runDiagnostics(true)}
              disabled={isRunning}
            >
              <RefreshCw className={`h-4 w-4 mr-2 ${isRunning ? 'animate-spin' : ''}`} />
              {isRunning ? 'Esecuzione...' : 'Esegui ora'}
            </Button>
          </div>
        ) : (
          <>
            <DiagnosticItem
              icon={Users}
              title="Autenticazione"
              diagnostic={diagnostics.session}
            />
            <Separator />
            <DiagnosticItem
              icon={Server}
              title="Dati Mappa"
              diagnostic={diagnostics.mapData}
            />
            <Separator />
            <DiagnosticItem
              icon={Map}
              title="Geometrie"
              diagnostic={diagnostics.geometries}
            />
            <Separator />
            <DiagnosticItem
              icon={Server}
              title="Ricerca"
              diagnostic={diagnostics.search}
            />
            <Separator />
            <DiagnosticItem
              icon={Database}
              title="Database"
              diagnostic={diagnostics.database}
            />
            <Separator />
            <DiagnosticItem
              icon={Key}
              title="Cache Locale"
              diagnostic={diagnostics.cache}
            />
          </>
        )}
      </CardContent>
    </Card>
  );
};
