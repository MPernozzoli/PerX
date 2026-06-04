import { createContext, useContext, useState, useCallback, useEffect, ReactNode } from 'react';

interface UploadState {
  isUploading: boolean;
  progress: number;
  currentCommune: string;
  totalCount: number;
  importedCount: number;
  errorCount: number;
}

interface UploadContextType {
  uploadState: UploadState;
  startUpload: (total: number) => void;
  updateProgress: (commune: string, progress: number, imported: number, errors: number) => void;
  finishUpload: () => void;
  resetUpload: () => void;
}

const UploadContext = createContext<UploadContextType | undefined>(undefined);

const STORAGE_KEY = 'geojson_upload_state';

const defaultState: UploadState = {
  isUploading: false,
  progress: 0,
  currentCommune: '',
  totalCount: 0,
  importedCount: 0,
  errorCount: 0,
};

export const UploadProvider = ({ children }: { children: ReactNode }) => {
  const [uploadState, setUploadState] = useState<UploadState>(() => {
    // Recupera lo stato da localStorage all'avvio
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved) {
      try {
        return JSON.parse(saved);
      } catch {
        return defaultState;
      }
    }
    return defaultState;
  });

  // Salva lo stato in localStorage ogni volta che cambia
  useEffect(() => {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(uploadState));
  }, [uploadState]);

  const startUpload = useCallback((total: number) => {
    setUploadState({
      isUploading: true,
      progress: 0,
      currentCommune: '',
      totalCount: total,
      importedCount: 0,
      errorCount: 0,
    });
  }, []);

  const updateProgress = useCallback((commune: string, progress: number, imported: number, errors: number) => {
    setUploadState(prev => ({
      ...prev,
      currentCommune: commune,
      progress,
      importedCount: imported,
      errorCount: errors,
    }));
  }, []);

  const finishUpload = useCallback(() => {
    setUploadState(prev => ({
      ...prev,
      isUploading: false,
      currentCommune: '',
    }));
  }, []);

  const resetUpload = useCallback(() => {
    setUploadState(defaultState);
    localStorage.removeItem(STORAGE_KEY);
  }, []);

  return (
    <UploadContext.Provider
      value={{
        uploadState,
        startUpload,
        updateProgress,
        finishUpload,
        resetUpload,
      }}
    >
      {children}
    </UploadContext.Provider>
  );
};

export const useUpload = () => {
  const context = useContext(UploadContext);
  if (!context) {
    throw new Error('useUpload must be used within UploadProvider');
  }
  return context;
};
