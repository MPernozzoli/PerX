import { Layout } from "@/components/Layout";
import { useAuth } from "@/contexts/AuthContext";
import { useIsAdmin } from "@/hooks/useUserRoles";
import { usePendingEdits, useApproveEdit, useRejectEdit } from "@/hooks/useEditApprovals";
import { useBulkImports, useCreateBulkImport } from "@/hooks/useBulkImports";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { CheckIcon, XIcon, UploadIcon, FileSpreadsheetIcon, ClockIcon, CheckCircleIcon, XCircleIcon } from "lucide-react";
import { useState, useRef } from "react";
import { Navigate } from "react-router-dom";
import { supabase } from "@/integrations/supabase/client";
import { useToast } from "@/hooks/use-toast";

export const Admin = () => {
  const { user } = useAuth();
  const isAdmin = useIsAdmin(user?.id);
  const { data: pendingEdits = [] } = usePendingEdits();
  const { data: bulkImports = [] } = useBulkImports();
  const approveEdit = useApproveEdit();
  const rejectEdit = useRejectEdit();
  const createBulkImport = useCreateBulkImport();
  const { toast } = useToast();

  const [rejectReason, setRejectReason] = useState("");
  const [selectedEditId, setSelectedEditId] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  // Redirect non-admin users
  if (!user || !isAdmin) {
    return <Navigate to="/" replace />;
  }

  const handleFileUpload = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;

    if (!file.name.match(/\.(xlsx|xls)$/)) {
      toast({
        title: "Errore",
        description: "Seleziona un file Excel valido (.xlsx o .xls)",
        variant: "destructive"
      });
      return;
    }

    try {
      // Upload file to Supabase Storage
      const fileName = `bulk-import-${Date.now()}-${file.name}`;
      const { data: uploadData, error: uploadError } = await supabase.storage
        .from('policy-pdfs')
        .upload(fileName, file);

      if (uploadError) throw uploadError;

      // Get public URL
      const { data: { publicUrl } } = supabase.storage
        .from('policy-pdfs')
        .getPublicUrl(fileName);

      // Create bulk import record
      await createBulkImport.mutateAsync({
        filename: file.name,
        file_url: publicUrl
      });

      // Reset file input
      if (fileInputRef.current) {
        fileInputRef.current.value = '';
      }

    } catch (error: any) {
      toast({
        title: "Errore",
        description: "Si è verificato un errore durante il caricamento del file.",
        variant: "destructive"
      });
    }
  };

  const handleReject = async () => {
    if (!selectedEditId || !rejectReason.trim()) return;
    
    await rejectEdit.mutateAsync({
      editId: selectedEditId,
      reason: rejectReason
    });
    
    setSelectedEditId(null);
    setRejectReason("");
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'pending': return <ClockIcon className="h-4 w-4 text-warning" />;
      case 'processing': return <ClockIcon className="h-4 w-4 text-primary animate-spin" />;
      case 'completed': return <CheckCircleIcon className="h-4 w-4 text-success" />;
      case 'failed': return <XCircleIcon className="h-4 w-4 text-destructive" />;
      default: return null;
    }
  };

  const getStatusVariant = (status: string) => {
    switch (status) {
      case 'pending': return 'outline';
      case 'processing': return 'default';
      case 'completed': return 'default';
      case 'failed': return 'destructive';
      default: return 'outline';
    }
  };

  return (
    <Layout>
      <div className="max-w-6xl mx-auto">
        <div className="mb-8">
          <h1 className="text-3xl font-bold">Pannello Amministratore</h1>
          <p className="text-muted-foreground mt-2">
            Gestisci le proposte di modifica e i caricamenti massivi
          </p>
        </div>

        <Tabs defaultValue="edits" className="space-y-6">
          <TabsList className="grid w-full grid-cols-2">
            <TabsTrigger value="edits">
              Proposte di Modifica ({pendingEdits.length})
            </TabsTrigger>
            <TabsTrigger value="imports">
              Caricamenti Massivi ({bulkImports.length})
            </TabsTrigger>
          </TabsList>

          <TabsContent value="edits" className="space-y-4">
            {pendingEdits.length === 0 ? (
              <Card>
                <CardContent className="py-8 text-center">
                  <p className="text-muted-foreground">Nessuna proposta di modifica in attesa</p>
                </CardContent>
              </Card>
            ) : (
              pendingEdits.map((edit) => (
                <Card key={edit.id}>
                  <CardHeader>
                    <div className="flex items-center justify-between">
                      <div>
                        <CardTitle className="text-lg">{edit.change_summary}</CardTitle>
                        <CardDescription>
                          Proposto da {edit.user?.name || edit.user?.email} • {new Date(edit.created_at).toLocaleDateString('it-IT')}
                        </CardDescription>
                      </div>
                      <Badge variant="outline">
                        {edit.target_type} - {edit.visibility}
                      </Badge>
                    </div>
                  </CardHeader>
                  <CardContent>
                    {edit.diff && (
                      <div className="mb-4 p-3 bg-muted rounded-lg">
                        <h4 className="font-medium mb-2">Modifiche proposte:</h4>
                        <pre className="text-sm overflow-auto max-h-40">
                          {JSON.stringify(edit.diff, null, 2)}
                        </pre>
                      </div>
                    )}
                    
                    <div className="flex gap-2">
                      <Button
                        onClick={() => approveEdit.mutate(edit.id)}
                        disabled={approveEdit.isPending}
                        className="gap-2"
                      >
                        <CheckIcon className="h-4 w-4" />
                        Approva
                      </Button>
                      
                      <Dialog>
                        <DialogTrigger asChild>
                          <Button
                            variant="outline"
                            onClick={() => setSelectedEditId(edit.id)}
                            className="gap-2"
                          >
                            <XIcon className="h-4 w-4" />
                            Rifiuta
                          </Button>
                        </DialogTrigger>
                        <DialogContent>
                          <DialogHeader>
                            <DialogTitle>Rifiuta Modifica</DialogTitle>
                            <DialogDescription>
                              Specifica il motivo del rifiuto per aiutare l'utente a migliorare future proposte.
                            </DialogDescription>
                          </DialogHeader>
                          <div className="py-4">
                            <Label htmlFor="reason">Motivo del rifiuto</Label>
                            <Textarea
                              id="reason"
                              value={rejectReason}
                              onChange={(e) => setRejectReason(e.target.value)}
                              placeholder="Descrivi il motivo per cui questa modifica non può essere accettata..."
                              className="mt-2"
                            />
                          </div>
                          <DialogFooter>
                            <Button
                              onClick={handleReject}
                              disabled={!rejectReason.trim() || rejectEdit.isPending}
                              variant="destructive"
                            >
                              Rifiuta Modifica
                            </Button>
                          </DialogFooter>
                        </DialogContent>
                      </Dialog>
                    </div>
                  </CardContent>
                </Card>
              ))
            )}
          </TabsContent>

          <TabsContent value="imports" className="space-y-4">
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center gap-2">
                  <UploadIcon className="h-5 w-5" />
                  Carica nuovo file Excel
                </CardTitle>
                <CardDescription>
                  Carica un file Excel contenente le polizze da importare. L'IA analizzerà automaticamente il contenuto.
                </CardDescription>
              </CardHeader>
              <CardContent>
                <div className="space-y-4">
                  <div>
                    <Label htmlFor="file-upload">File Excel</Label>
                    <Input
                      id="file-upload"
                      type="file"
                      accept=".xlsx,.xls"
                      onChange={handleFileUpload}
                      ref={fileInputRef}
                      className="mt-2"
                    />
                  </div>
                  <p className="text-sm text-muted-foreground">
                    Formati supportati: .xlsx, .xls. Una compagnia per foglio.
                  </p>
                </div>
              </CardContent>
            </Card>

            <div className="space-y-4">
              {bulkImports.map((importItem) => (
                <Card key={importItem.id}>
                  <CardHeader>
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-3">
                        <FileSpreadsheetIcon className="h-5 w-5 text-muted-foreground" />
                        <div>
                          <CardTitle className="text-lg">{importItem.filename}</CardTitle>
                          <CardDescription>
                            Caricato il {new Date(importItem.created_at).toLocaleDateString('it-IT')}
                          </CardDescription>
                        </div>
                      </div>
                      <div className="flex items-center gap-2">
                        {getStatusIcon(importItem.status)}
                        <Badge variant={getStatusVariant(importItem.status)}>
                          {importItem.status}
                        </Badge>
                      </div>
                    </div>
                  </CardHeader>
                  <CardContent>
                    <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
                      <div>
                        <span className="font-medium">Stato:</span>
                        <p className="text-muted-foreground capitalize">{importItem.status}</p>
                      </div>
                      {importItem.imported_policies_count > 0 && (
                        <div>
                          <span className="font-medium">Polizze importate:</span>
                          <p className="text-muted-foreground">{importItem.imported_policies_count}</p>
                        </div>
                      )}
                      {importItem.processed_at && (
                        <div>
                          <span className="font-medium">Completato:</span>
                          <p className="text-muted-foreground">
                            {new Date(importItem.processed_at).toLocaleDateString('it-IT')}
                          </p>
                        </div>
                      )}
                      {importItem.error_message && (
                        <div className="col-span-full">
                          <span className="font-medium text-destructive">Errore:</span>
                          <p className="text-destructive text-sm mt-1">{importItem.error_message}</p>
                        </div>
                      )}
                    </div>
                    
                    {importItem.ai_analysis && (
                      <div className="mt-4 p-3 bg-muted rounded-lg">
                        <h4 className="font-medium mb-2">Analisi IA:</h4>
                        <pre className="text-sm overflow-auto max-h-40">
                          {JSON.stringify(importItem.ai_analysis, null, 2)}
                        </pre>
                      </div>
                    )}
                  </CardContent>
                </Card>
              ))}
            </div>
          </TabsContent>
        </Tabs>
      </div>
    </Layout>
  );
};