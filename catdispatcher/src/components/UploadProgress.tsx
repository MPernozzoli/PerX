import { useUpload } from '@/contexts/UploadContext';
import { Card } from '@/components/ui/card';
import { Progress } from '@/components/ui/progress';
import { Button } from '@/components/ui/button';
import { X, Upload } from 'lucide-react';

const UploadProgress = () => {
  const { uploadState, resetUpload } = useUpload();

  if (!uploadState.isUploading && uploadState.progress === 0) {
    return null;
  }

  return (
    <Card className="fixed bottom-4 right-4 p-4 w-80 shadow-lg z-50">
      <div className="space-y-3">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Upload className="h-4 w-4 text-primary" />
            <h3 className="font-semibold text-sm">
              {uploadState.isUploading ? 'Importazione in corso' : 'Importazione completata'}
            </h3>
          </div>
          {!uploadState.isUploading && (
            <Button
              variant="ghost"
              size="sm"
              onClick={resetUpload}
              className="h-6 w-6 p-0"
            >
              <X className="h-4 w-4" />
            </Button>
          )}
        </div>

        <Progress value={uploadState.progress} className="w-full" />

        <div className="text-xs space-y-1">
          {uploadState.currentCommune && uploadState.isUploading && (
            <p className="font-medium text-foreground">
              {uploadState.currentCommune}
            </p>
          )}
          <div className="flex justify-between text-muted-foreground">
            <span>{Math.round(uploadState.progress)}%</span>
            <span>
              {uploadState.importedCount} / {uploadState.totalCount} comuni
            </span>
          </div>
          {uploadState.errorCount > 0 && (
            <p className="text-destructive">
              {uploadState.errorCount} errori
            </p>
          )}
        </div>

        {!uploadState.isUploading && uploadState.progress === 100 && (
          <p className="text-xs text-success">
            ✓ Importazione completata con successo
          </p>
        )}
      </div>
    </Card>
  );
};

export default UploadProgress;
