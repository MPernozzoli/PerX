import { useState, useEffect } from 'react';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { AlertTriangle } from 'lucide-react';

const SUSPENSION_DATE = new Date('2026-01-01T00:00:00');
const STORAGE_KEY = 'serviceSuspensionAcknowledged';

interface ServiceSuspensionDialogProps {
  onLoginRequired: () => void;
}

export const ServiceSuspensionDialog = ({ onLoginRequired }: ServiceSuspensionDialogProps) => {
  const [open, setOpen] = useState(false);
  const [isServiceSuspended, setIsServiceSuspended] = useState(false);

  useEffect(() => {
    const now = new Date();
    const suspended = now >= SUSPENSION_DATE;
    setIsServiceSuspended(suspended);

    if (suspended) {
      // Service is suspended, require login
      onLoginRequired();
    } else {
      // Show warning popup if not already acknowledged in this session
      const acknowledged = sessionStorage.getItem(STORAGE_KEY);
      if (!acknowledged) {
        setOpen(true);
      }
    }
  }, [onLoginRequired]);

  const handleAcknowledge = () => {
    sessionStorage.setItem(STORAGE_KEY, 'true');
    setOpen(false);
  };

  // Don't render if service is suspended (login page will handle it)
  if (isServiceSuspended) {
    return null;
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <div className="flex items-center gap-3 mb-2">
            <div className="flex h-10 w-10 items-center justify-center rounded-full bg-amber-100 dark:bg-amber-900">
              <AlertTriangle className="h-5 w-5 text-amber-600 dark:text-amber-400" />
            </div>
            <DialogTitle className="text-xl">Avviso Importante</DialogTitle>
          </div>
          <DialogDescription className="text-base pt-2">
            <strong>A partire dal 01/01/2026, non sarà più possibile accedere al servizio</strong> fino alla stipula dell'accordo di fruizione con la Direzione.
          </DialogDescription>
        </DialogHeader>
        <DialogFooter className="mt-4">
          <Button onClick={handleAcknowledge} className="w-full sm:w-auto">
            Ho capito
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
};

export const isServiceSuspended = (): boolean => {
  return new Date() >= SUSPENSION_DATE;
};
