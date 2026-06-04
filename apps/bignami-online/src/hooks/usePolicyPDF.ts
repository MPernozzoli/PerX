import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

export const usePolicyPDF = () => {
  const [uploading, setUploading] = useState(false);
  const [downloading, setDownloading] = useState(false);
  const queryClient = useQueryClient();

  const uploadPDF = useMutation({
    mutationFn: async ({ 
      file, 
      policyId, 
      editionId 
    }: { 
      file: File; 
      policyId: string; 
      editionId: string; 
    }) => {
      setUploading(true);
      
      // Generate file path
      const fileExt = file.name.split('.').pop();
      const fileName = `${policyId}/${editionId}.${fileExt}`;

      // Upload file to storage
      const { data: uploadData, error: uploadError } = await supabase.storage
        .from('policy-pdfs')
        .upload(fileName, file, { 
          upsert: true,
          cacheControl: '3600'
        });

      if (uploadError) throw uploadError;

      // Get public URL
      const { data: { publicUrl } } = supabase.storage
        .from('policy-pdfs')
        .getPublicUrl(fileName);

      // Generate SHA256 hash
      const arrayBuffer = await file.arrayBuffer();
      const hashBuffer = await crypto.subtle.digest('SHA-256', arrayBuffer);
      const hashArray = Array.from(new Uint8Array(hashBuffer));
      const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');

      // Update policy edition with PDF info
      const { error: updateError } = await supabase
        .from('policy_editions')
        .update({
          pdf_url: publicUrl,
          pdf_sha256: hashHex
        })
        .eq('id', editionId);

      if (updateError) throw updateError;

      setUploading(false);
      return { publicUrl, fileName };
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["policies-with-coverages"] });
      toast.success("PDF caricato con successo!");
    },
    onError: (error) => {
      setUploading(false);
      toast.error("Errore durante il caricamento del PDF");
      console.error(error);
    },
  });

  const downloadPDF = async (pdfUrl: string, filename: string) => {
    if (!pdfUrl) {
      toast.error("PDF non disponibile");
      return;
    }

    setDownloading(true);
    try {
      const response = await fetch(pdfUrl);
      if (!response.ok) throw new Error('Download failed');
      
      const blob = await response.blob();
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      window.URL.revokeObjectURL(url);
      
      toast.success("PDF scaricato con successo!");
    } catch (error) {
      toast.error("Errore durante il download del PDF");
      console.error(error);
    } finally {
      setDownloading(false);
    }
  };

  const viewPDF = (pdfUrl: string) => {
    if (!pdfUrl) {
      toast.error("PDF non disponibile");
      return;
    }
    window.open(pdfUrl, '_blank');
  };

  return {
    uploadPDF: uploadPDF.mutateAsync,
    downloadPDF,
    viewPDF,
    uploading,
    downloading,
  };
};