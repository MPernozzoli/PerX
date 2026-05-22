import { useState, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { X, Chrome, Download } from 'lucide-react';

const STORAGE_KEY = 'catDispatcher_extensionBannerDismissed';

interface ChromeExtensionBannerProps {
  /** Mostra come banner compatto invece che come card */
  compact?: boolean;
  /** Callback quando il banner viene chiuso */
  onDismiss?: () => void;
}

/**
 * Rileva se il browser è Chrome
 */
function isChromeBrowser(): boolean {
  const userAgent = navigator.userAgent.toLowerCase();
  return userAgent.includes('chrome') && !userAgent.includes('edg');
}

/**
 * Rileva se l'estensione CAT Dispatcher è installata
 * L'estensione inietta un marker nel DOM
 */
function isExtensionInstalled(): boolean {
  const marker = document.getElementById('cat-dispatcher-extension-marker');
  return marker?.dataset?.installed === 'true';
}

/**
 * Ottiene la versione dell'estensione installata
 */
function getExtensionVersion(): string | null {
  const marker = document.getElementById('cat-dispatcher-extension-marker');
  return marker?.dataset?.version || null;
}

/**
 * Banner/Card per promuovere l'installazione dell'estensione Chrome
 */
export function ChromeExtensionBanner({ compact = false, onDismiss }: ChromeExtensionBannerProps) {
  const [isDismissed, setIsDismissed] = useState(true);
  const [isChrome, setIsChrome] = useState(false);
  const [extensionInstalled, setExtensionInstalled] = useState(false);

  useEffect(() => {
    // Verifica se è Chrome
    setIsChrome(isChromeBrowser());
    
    // Verifica se l'estensione è già installata (dopo un breve delay per dare tempo al content script)
    const checkExtension = () => {
      const installed = isExtensionInstalled();
      setExtensionInstalled(installed);
      if (installed) {
        console.log('[CAT Dispatcher] Estensione rilevata, versione:', getExtensionVersion());
      }
    };
    
    // Controlla subito e dopo un delay
    checkExtension();
    const timeout = setTimeout(checkExtension, 1000);
    
    // Verifica se il banner è stato già chiuso
    const dismissed = localStorage.getItem(STORAGE_KEY);
    setIsDismissed(!!dismissed);
    
    return () => clearTimeout(timeout);
  }, []);

  const handleDismiss = () => {
    localStorage.setItem(STORAGE_KEY, 'true');
    setIsDismissed(true);
    onDismiss?.();
  };

  const handleInstall = () => {
    // Apre la pagina di istruzioni per l'installazione manuale
    window.open('/install-extension.html', '_blank');
  };

  // Non mostrare se:
  // - Non è Chrome
  // - È stato chiuso
  // - L'estensione è già installata
  if (!isChrome || isDismissed || extensionInstalled) {
    return null;
  }

  if (compact) {
    return (
      <div className="flex items-center gap-3 bg-gradient-to-r from-blue-600 to-teal-500 text-white px-4 py-2 text-sm">
        <Chrome className="h-4 w-4 flex-shrink-0" />
        <span className="flex-1">
          Installa l'estensione Chrome per assegnare i CAT direttamente da ACT!
        </span>
        <Button
          size="sm"
          variant="secondary"
          className="bg-white/20 hover:bg-white/30 text-white border-0 h-7 px-3 text-xs"
          onClick={handleInstall}
        >
          <Download className="h-3 w-3 mr-1" />
          Installa
        </Button>
        <button
          onClick={handleDismiss}
          className="p-1 hover:bg-white/20 rounded"
          aria-label="Chiudi"
        >
          <X className="h-4 w-4" />
        </button>
      </div>
    );
  }

  return (
    <div className="relative bg-gradient-to-br from-blue-50 to-teal-50 border border-blue-200 rounded-xl p-5 shadow-sm">
      {/* Pulsante chiudi */}
      <button
        onClick={handleDismiss}
        className="absolute top-3 right-3 p-1.5 hover:bg-black/5 rounded-lg transition-colors"
        aria-label="Chiudi"
      >
        <X className="h-4 w-4 text-gray-400" />
      </button>

      <div className="flex items-start gap-4">
        {/* Icona Chrome */}
        <div className="flex-shrink-0 w-12 h-12 bg-gradient-to-br from-blue-600 to-teal-500 rounded-xl flex items-center justify-center shadow-lg">
          <Chrome className="h-6 w-6 text-white" />
        </div>

        <div className="flex-1 min-w-0">
          <h3 className="font-semibold text-gray-900 mb-1">
            Estensione Chrome disponibile
          </h3>
          <p className="text-sm text-gray-600 mb-4">
            Assegna i CAT direttamente dal gestionale ACT JellyFish.
          </p>

          {/* Pulsante installazione */}
          <Button
            onClick={handleInstall}
            className="bg-blue-600 hover:bg-blue-700"
          >
            <Download className="h-4 w-4 mr-2" />
            Installa estensione
          </Button>
        </div>
      </div>
    </div>
  );
}

/**
 * Pulsante compatto per l'header
 */
export function ChromeExtensionButton() {
  const [isChrome, setIsChrome] = useState(false);
  const [extensionInstalled, setExtensionInstalled] = useState(false);

  useEffect(() => {
    setIsChrome(isChromeBrowser());
    
    // Controlla se l'estensione è installata
    const checkExtension = () => {
      setExtensionInstalled(isExtensionInstalled());
    };
    
    checkExtension();
    const timeout = setTimeout(checkExtension, 1000);
    
    return () => clearTimeout(timeout);
  }, []);

  // Non mostrare se non è Chrome o se l'estensione è già installata
  if (!isChrome || extensionInstalled) {
    return null;
  }

  const handleInstall = () => {
    window.open('/install-extension.html', '_blank');
  };

  return (
    <Button
      variant="outline"
      size="sm"
      onClick={handleInstall}
      className="flex-shrink-0 border-blue-300 text-blue-600 hover:bg-blue-50"
      title="Installa estensione Chrome"
    >
      <Chrome className="h-4 w-4 mr-2" />
      Estensione
    </Button>
  );
}

export default ChromeExtensionBanner;
