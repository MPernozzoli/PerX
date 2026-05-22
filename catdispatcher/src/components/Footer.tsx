import { Link } from 'react-router-dom';
import { useDiagnostics } from '@/contexts/DiagnosticContext';
import { Circle, AlertTriangle, CheckCircle2, XCircle, Shield, Zap, Activity, Sparkles, Crosshair } from 'lucide-react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger, DialogDescription } from '@/components/ui/dialog';
import { Badge } from '@/components/ui/badge';
import { useState } from 'react';

const Footer = () => {
  const { systemStatus, isUnderMaintenance, diagnostics } = useDiagnostics();
  const [isDialogOpen, setIsDialogOpen] = useState(false);
  const [isChangelogOpen, setIsChangelogOpen] = useState(false);

  const statusConfig: Record<string, { color: string; label: string; bgColor: string }> = {
    operational: {
      color: 'text-green-500',
      label: 'Funzionante',
      bgColor: 'bg-green-500/10'
    },
    partial: {
      color: 'text-yellow-500',
      label: 'Parzialmente funzionante',
      bgColor: 'bg-yellow-500/10'
    },
    down: {
      color: 'text-red-500',
      label: 'Non funzionante',
      bgColor: 'bg-red-500/10'
    },
    unknown: {
      color: 'text-muted-foreground',
      label: 'Stato non disponibile',
      bgColor: 'bg-muted/50'
    }
  };

  const status = statusConfig[systemStatus] ?? statusConfig.unknown;
  const showMaintenanceMessage = isUnderMaintenance || (systemStatus !== 'operational' && systemStatus !== 'unknown');

  return (
    <footer className="w-full py-2 px-4 border-t border-border bg-background/80 backdrop-blur-sm">
      <div className="container mx-auto">
        <div className="flex flex-col md:flex-row items-center justify-between gap-2">
          <div className="flex flex-col items-center md:items-start gap-0.5">
            <p className="text-center md:text-left text-xs text-muted-foreground">
              Software realizzato da{" "}
              <a
                href="https://pynkstudio.it"
                target="_blank"
                rel="noopener noreferrer"
                className="text-primary hover:underline font-medium transition-colors"
              >
                PynkStudio
              </a>
            </p>
            <div className="flex items-center gap-2">
              <Dialog open={isChangelogOpen} onOpenChange={setIsChangelogOpen}>
                <DialogTrigger asChild>
                  <button 
                    className="text-xs text-muted-foreground hover:text-foreground transition-colors px-2 py-0.5 rounded hover:bg-accent/50"
                    aria-label="Mostra changelog"
                  >
                    <span className="font-semibold">v2.0.2</span>
                  </button>
                </DialogTrigger>
                <DialogContent className="max-w-md max-h-[80vh] overflow-y-auto">
                  <DialogHeader>
                    <DialogTitle className="flex items-center gap-2">
                      <Sparkles className="h-5 w-5 text-primary" />
                      Novità versione 2.0.2
                    </DialogTitle>
                    <DialogDescription>
                      Nuovo design e miglioramenti
                    </DialogDescription>
                  </DialogHeader>
                  <div className="space-y-3 mt-4">
                    {/* Nuovo logo e color palette */}
                    <div className="flex items-start gap-3 p-3 rounded-lg bg-gradient-to-br from-primary/10 to-primary/5 border border-primary/20">
                      <div className="p-2 rounded-full bg-primary/20">
                        <Sparkles className="h-4 w-4 text-primary" />
                      </div>
                      <div className="flex-1">
                        <h4 className="font-semibold text-sm mb-1">Nuovo Logo e Color Palette</h4>
                        <p className="text-xs text-muted-foreground">
                          Design rinnovato con nuovo logo CAT Dispatcher e palette colori aggiornata
                        </p>
                      </div>
                      <Badge variant="secondary" className="text-[10px]">NEW</Badge>
                    </div>

                    {/* Sezione versioni precedenti */}
                    <div className="pt-2 border-t border-border">
                      <p className="text-xs text-muted-foreground mb-2 font-medium">Versione 2.0.1</p>
                    </div>

                    {/* Nuovo sistema diagnostica */}
                    <div className="flex items-start gap-3 p-3 rounded-lg bg-muted/50">
                      <div className="p-2 rounded-full bg-muted">
                        <Activity className="h-4 w-4 text-muted-foreground" />
                      </div>
                      <div className="flex-1">
                        <h4 className="font-semibold text-sm mb-1">Sistema Diagnostica Avanzato</h4>
                        <p className="text-xs text-muted-foreground">
                          Monitoraggio server-side con cron automatico e report dettagliati
                        </p>
                      </div>
                    </div>

                    {/* Prestazioni migliorate */}
                    <div className="flex items-start gap-3 p-3 rounded-lg bg-muted/50">
                      <div className="p-2 rounded-full bg-muted">
                        <Zap className="h-4 w-4 text-muted-foreground" />
                      </div>
                      <div className="flex-1">
                        <h4 className="font-semibold text-sm mb-1">Prestazioni Ottimizzate</h4>
                        <p className="text-xs text-muted-foreground">
                          Caricamento più veloce e minore consumo risorse
                        </p>
                      </div>
                    </div>

                    {/* Estensione Chrome v1.6 */}
                    <div className="flex items-start gap-3 p-3 rounded-lg bg-muted/50">
                      <div className="p-2 rounded-full bg-muted">
                        <Crosshair className="h-4 w-4 text-muted-foreground" />
                      </div>
                      <div className="flex-1">
                        <h4 className="font-semibold text-sm mb-1">Estensione Chrome v1.6</h4>
                        <p className="text-xs text-muted-foreground">
                          Assegnazione automatica migliorata e nuova interfaccia utente
                        </p>
                      </div>
                    </div>

                    {/* Sezione versioni precedenti */}
                    <div className="pt-2 border-t border-border">
                      <p className="text-xs text-muted-foreground mb-2 font-medium">Versione 2.0</p>
                    </div>

                    {/* Accesso con Google */}
                    <div className="flex items-start gap-3 p-3 rounded-lg bg-muted/50">
                      <div className="p-2 rounded-full bg-muted">
                        <Shield className="h-4 w-4 text-muted-foreground" />
                      </div>
                      <div className="flex-1">
                        <h4 className="font-semibold text-sm mb-1">Accesso con Google</h4>
                        <p className="text-xs text-muted-foreground">
                          Login sicuro con account Google aziendale
                        </p>
                      </div>
                    </div>

                    {/* Sistema di caching */}
                    <div className="flex items-start gap-3 p-3 rounded-lg bg-muted/50">
                      <div className="p-2 rounded-full bg-muted">
                        <Activity className="h-4 w-4 text-muted-foreground" />
                      </div>
                      <div className="flex-1">
                        <h4 className="font-semibold text-sm mb-1">Cache Ottimizzata</h4>
                        <p className="text-xs text-muted-foreground">
                          Sistema di caching per prestazioni ultra-rapide
                        </p>
                      </div>
                    </div>
                  </div>
                </DialogContent>
              </Dialog>
              <span className="text-xs text-muted-foreground">
                <Link to="/privacy" className="hover:text-foreground transition-colors">Privacy</Link>
                {" · "}
                <Link to="/cookie" className="hover:text-foreground transition-colors">Cookie</Link>
              </span>
            </div>
          </div>
          
          <div className="flex flex-col items-center md:items-end gap-1">
            <Dialog open={isDialogOpen} onOpenChange={setIsDialogOpen}>
              <DialogTrigger asChild>
                <button 
                  className={`flex items-center gap-1.5 px-2 py-1 rounded-full ${status.bgColor} transition-all hover:scale-105 cursor-pointer`}
                  aria-label="Apri dettagli stato sistema"
                >
                  <Circle className={`h-2 w-2 fill-current ${status.color}`} />
                  <span className={`text-xs font-medium ${status.color}`}>
                    {status.label}
                  </span>
                </button>
              </DialogTrigger>
              <DialogContent className="max-w-md">
                <DialogHeader>
                  <DialogTitle>Stato del Sistema</DialogTitle>
                </DialogHeader>
                <div className="space-y-3 mt-4">
                  {!diagnostics ? (
                    <div className="py-6 text-center text-sm text-muted-foreground">
                      <p>Dati diagnostica non ancora disponibili.</p>
                      <p className="mt-2">
                        <Link to="/admin" className="text-primary hover:underline">Admin → Diagnostica</Link>
                        {' '}e clicca &quot;Riesegui&quot; per la prima esecuzione.
                      </p>
                    </div>
                  ) : (
                  <>
                  {/* Mappa */}
                  <div className="flex items-start justify-between p-3 rounded-lg bg-muted/50">
                    <div className="flex items-center gap-2">
                      {diagnostics?.geometries.status === 'ok' ? (
                        <CheckCircle2 className="h-4 w-4 text-green-500 flex-shrink-0" />
                      ) : (
                        <XCircle className="h-4 w-4 text-red-500 flex-shrink-0" />
                      )}
                      <span className="font-medium text-sm">Mappa</span>
                    </div>
                    <span className={`text-xs ${diagnostics?.geometries.status === 'ok' ? 'text-green-500' : 'text-red-500'}`}>
                      {diagnostics?.geometries.status === 'ok' ? 'funzionante' : 'non funzionante'}
                    </span>
                  </div>

                  {/* Cerca */}
                  <div className="flex items-start justify-between p-3 rounded-lg bg-muted/50">
                    <div className="flex items-center gap-2">
                      {diagnostics?.search.status === 'ok' ? (
                        <CheckCircle2 className="h-4 w-4 text-green-500 flex-shrink-0" />
                      ) : (
                        <XCircle className="h-4 w-4 text-red-500 flex-shrink-0" />
                      )}
                      <span className="font-medium text-sm">Cerca</span>
                    </div>
                    <span className={`text-xs ${diagnostics?.search.status === 'ok' ? 'text-green-500' : 'text-red-500'}`}>
                      {diagnostics?.search.status === 'ok' ? 'funzionante' : 'non funzionante'}
                    </span>
                  </div>

                  {/* Database */}
                  <div className="flex items-start justify-between p-3 rounded-lg bg-muted/50">
                    <div className="flex items-center gap-2">
                      {diagnostics?.database.status === 'ok' ? (
                        <CheckCircle2 className="h-4 w-4 text-green-500 flex-shrink-0" />
                      ) : (
                        <XCircle className="h-4 w-4 text-red-500 flex-shrink-0" />
                      )}
                      <span className="font-medium text-sm">Database</span>
                    </div>
                    <span className={`text-xs ${diagnostics?.database.status === 'ok' ? 'text-green-500' : 'text-red-500'}`}>
                      {diagnostics?.database.status === 'ok' ? 'funzionante' : 'non funzionante'}
                    </span>
                  </div>

                  {/* Cache */}
                  <div className="flex items-start justify-between p-3 rounded-lg bg-muted/50">
                    <div className="flex items-center gap-2">
                      {diagnostics?.cache.status === 'ok' ? (
                        <CheckCircle2 className="h-4 w-4 text-green-500 flex-shrink-0" />
                      ) : diagnostics?.cache.status === 'warning' ? (
                        <AlertTriangle className="h-4 w-4 text-yellow-500 flex-shrink-0" />
                      ) : (
                        <XCircle className="h-4 w-4 text-red-500 flex-shrink-0" />
                      )}
                      <span className="font-medium text-sm">Cache</span>
                    </div>
                    <span className={`text-xs ${diagnostics?.cache.status === 'ok' ? 'text-green-500' : diagnostics?.cache.status === 'warning' ? 'text-yellow-500' : 'text-red-500'}`}>
                      {diagnostics?.cache.status === 'ok' ? 'funzionante' : diagnostics?.cache.status === 'warning' ? 'parziale' : 'non funzionante'}
                    </span>
                  </div>
                  </>
                  )}
                </div>
              </DialogContent>
            </Dialog>
            
            {showMaintenanceMessage && (
              <div className="flex items-center gap-1 text-xs text-muted-foreground">
                <AlertTriangle className="h-3 w-3" />
                <span>Stiamo lavorando per risolvere il problema</span>
              </div>
            )}
          </div>
        </div>
      </div>
    </footer>
  );
};

export default Footer;
