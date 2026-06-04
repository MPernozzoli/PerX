import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@perx/ui/components/ui/dialog";
import { Button } from "@perx/ui/components/ui/button";
import { Card } from "@perx/ui/components/ui/card";
import { HistoryIcon, CheckCircleIcon } from "lucide-react";

interface HistoryModalProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export const HistoryModal = ({ open, onOpenChange }: HistoryModalProps) => {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-3xl max-h-[80vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <HistoryIcon className="h-5 w-5" />
            Cronologia Modifiche
          </DialogTitle>
        </DialogHeader>
        
        <div className="space-y-4">
          <div className="flex items-center gap-3 p-3 bg-muted/50 rounded-lg">
            <CheckCircleIcon className="h-4 w-4 text-accent" />
            <div className="flex-1">
              <div className="text-sm font-medium">Aggiornamento sovratensioni da rete</div>
              <div className="text-xs text-muted-foreground">Mario Rossi • 15 Set 2024 • Approvato</div>
            </div>
            <Button variant="ghost" size="sm">Visualizza</Button>
          </div>

          <div className="flex items-center gap-3 p-3 bg-muted/50 rounded-lg">
            <CheckCircleIcon className="h-4 w-4 text-accent" />
            <div className="flex-1">
              <div className="text-sm font-medium">Correzione definizione impianti</div>
              <div className="text-xs text-muted-foreground">Giulia Bianchi • 12 Set 2024 • Approvato</div>
            </div>
            <Button variant="ghost" size="sm">Visualizza</Button>
          </div>

          <div className="flex items-center gap-3 p-3 bg-muted/50 rounded-lg">
            <CheckCircleIcon className="h-4 w-4 text-accent" />
            <div className="flex-1">
              <div className="text-sm font-medium">Aggiornamento franchigie</div>
              <div className="text-xs text-muted-foreground">Anna Verde • 10 Set 2024 • Approvato</div>
            </div>
            <Button variant="ghost" size="sm">Visualizza</Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
};