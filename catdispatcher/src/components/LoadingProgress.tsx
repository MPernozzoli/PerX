import { useEffect, useState } from 'react';
import { Progress } from '@/components/ui/progress';
import { AlertCircle, CheckCircle, AlertTriangle } from 'lucide-react';

interface LoadingProgressProps {
  isLoading: boolean;
  onComplete?: () => void;
  geometryStatus?: {
    total: number;
    loaded: number;
  };
}

export const LoadingProgress = ({ isLoading, onComplete, geometryStatus }: LoadingProgressProps) => {
  const [progress, setProgress] = useState(0);
  
  // Calculate geometry status
  const getGeometryStatus = () => {
    if (!geometryStatus) return null;
    
    const { total, loaded } = geometryStatus;
    if (total === 0) return null;
    
    const percentage = (loaded / total) * 100;
    
    if (percentage === 0) {
      return {
        icon: AlertCircle,
        color: 'text-destructive',
        message: 'Mappa non funzionante',
        description: 'Nessuna geometria caricata'
      };
    } else if (percentage < 100) {
      return {
        icon: AlertTriangle,
        color: 'text-yellow-500',
        message: 'Mappa parzialmente funzionante',
        description: `${loaded}/${total} comuni caricati (${percentage.toFixed(0)}%)`
      };
    } else {
      return {
        icon: CheckCircle,
        color: 'text-green-500',
        message: 'Mappa completamente funzionante',
        description: `Tutti i ${total} comuni caricati`
      };
    }
  };
  
  const geometryInfo = getGeometryStatus();

  useEffect(() => {
    if (!isLoading) {
      setProgress(100);
      setTimeout(() => {
        onComplete?.();
      }, 500);
      return;
    }

    setProgress(0);
    
    // Simulate progressive loading
    const intervals = [
      { time: 100, value: 10 },
      { time: 300, value: 25 },
      { time: 600, value: 40 },
      { time: 1000, value: 60 },
      { time: 1500, value: 75 },
      { time: 2000, value: 85 },
      { time: 3000, value: 95 },
    ];

    const timers = intervals.map(({ time, value }) =>
      setTimeout(() => {
        if (isLoading) {
          setProgress(value);
        }
      }, time)
    );

    return () => {
      timers.forEach(clearTimeout);
    };
  }, [isLoading, onComplete]);

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between text-sm">
        <span className="font-medium">Caricamento comuni</span>
        <span className="text-muted-foreground">{progress}%</span>
      </div>
      <Progress value={progress} className="h-2" />
      <p className="text-xs text-muted-foreground">
        {progress < 100 
          ? 'Stiamo caricando tutti i comuni sulla mappa...' 
          : 'Completato!'}
      </p>
      
      {/* Geometry status indicator */}
      {geometryInfo && progress === 100 && (
        <div className={`flex items-start gap-2 mt-3 p-2 rounded-md border ${
          geometryInfo.color === 'text-destructive' ? 'border-destructive bg-destructive/5' :
          geometryInfo.color === 'text-yellow-500' ? 'border-yellow-500 bg-yellow-500/5' :
          'border-green-500 bg-green-500/5'
        }`}>
          <geometryInfo.icon className={`h-4 w-4 mt-0.5 flex-shrink-0 ${geometryInfo.color}`} />
          <div className="space-y-0.5">
            <p className={`text-xs font-medium ${geometryInfo.color}`}>
              {geometryInfo.message}
            </p>
            <p className="text-xs text-muted-foreground">
              {geometryInfo.description}
            </p>
          </div>
        </div>
      )}
    </div>
  );
};
