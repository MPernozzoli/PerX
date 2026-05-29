import { useState } from 'react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { Badge } from '@/components/ui/badge';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { RichTextDisplay } from '@/components/ui/rich-text-display';
import { AlertTriangle, Bot, CheckCircle, XCircle } from 'lucide-react';
import type { AIExtractedData } from '@/hooks/useAIExtractPolicy';

interface AIExtractResultsModalProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  data: AIExtractedData | null;
  onConfirm: () => void;
  onCancel: () => void;
  isApplying: boolean;
}

export const AIExtractResultsModal = ({
  open,
  onOpenChange,
  data,
  onConfirm,
  onCancel,
  isApplying
}: AIExtractResultsModalProps) => {
  if (!data) return null;

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-4xl max-h-[90vh] overflow-hidden">
        <DialogHeader>
          <div className="flex items-center gap-2">
            <Bot className="h-5 w-5 text-primary" />
            <DialogTitle>Risultati Estrazione IA</DialogTitle>
          </div>
          <DialogDescription>
            Controlla i dati estratti dall'IA prima di applicarli alla polizza.
          </DialogDescription>
        </DialogHeader>

        <Alert className="mb-4">
          <AlertTriangle className="h-4 w-4" />
          <AlertDescription>
            <strong>Importante:</strong> L'IA può commettere errori. Verifica attentamente tutti i dati 
            estratti prima di confermare l'applicazione alla polizza.
          </AlertDescription>
        </Alert>

        <ScrollArea className="h-[60vh]">
          <Tabs defaultValue="coverage" className="w-full">
            <TabsList className="grid w-full grid-cols-5">
              <TabsTrigger value="coverage">Copertura</TabsTrigger>
              <TabsTrigger value="sections">Partite</TabsTrigger>
              <TabsTrigger value="guarantees">Garanzie</TabsTrigger>
              <TabsTrigger value="limits">Limiti</TabsTrigger>
              <TabsTrigger value="notes">Note</TabsTrigger>
            </TabsList>

            <TabsContent value="coverage" className="space-y-4">
              <Card>
                <CardHeader>
                  <CardTitle>Aggiornamenti Copertura</CardTitle>
                  <CardDescription>
                    Informazioni generali sulla copertura estratte dal PDF
                  </CardDescription>
                </CardHeader>
                <CardContent className="space-y-4">
                  {data.coverage_updates.overview_text && (
                    <div>
                      <h4 className="font-medium mb-2">Panoramica</h4>
                      <RichTextDisplay content={data.coverage_updates.overview_text} />
                    </div>
                  )}
                  
                  {data.coverage_updates.value_type && (
                    <div>
                      <h4 className="font-medium mb-2">Tipo di Valore</h4>
                      <Badge variant="outline">{data.coverage_updates.value_type}</Badge>
                      {data.coverage_updates.primo_rischio_value && (
                        <span className="ml-2 text-sm text-muted-foreground">
                          {data.coverage_updates.primo_rischio_value}
                        </span>
                      )}
                    </div>
                  )}

                  {data.coverage_updates.definitions && data.coverage_updates.definitions.length > 0 && (
                    <div>
                      <h4 className="font-medium mb-2">Definizioni Generali</h4>
                      {data.coverage_updates.definitions.map((def, index) => (
                        <RichTextDisplay key={index} content={def} className="mb-2" />
                      ))}
                    </div>
                  )}

                  {data.coverage_updates.common_exclusions && data.coverage_updates.common_exclusions.length > 0 && (
                    <div>
                      <h4 className="font-medium mb-2">Esclusioni Comuni</h4>
                      <ul className="list-disc list-inside space-y-1">
                        {data.coverage_updates.common_exclusions.map((exclusion, index) => (
                          <li key={index} className="text-sm">{exclusion}</li>
                        ))}
                      </ul>
                    </div>
                  )}
                </CardContent>
              </Card>
            </TabsContent>

            <TabsContent value="sections" className="space-y-4">
              <div className="grid gap-4">
                {data.sections_to_create.map((section, index) => (
                  <Card key={index}>
                    <CardHeader>
                      <CardTitle className="flex items-center gap-2">
                        <span className="text-xl">{section.emoji}</span>
                        {section.exact_name}
                      </CardTitle>
                      <CardDescription>
                        <Badge variant="outline">{section.party}</Badge>
                      </CardDescription>
                    </CardHeader>
                    <CardContent className="space-y-3">
                      <div>
                        <h5 className="font-medium mb-1">Definizione</h5>
                        <RichTextDisplay content={section.definition} />
                        {section.definition_page_reference && (
                          <p className="text-xs text-muted-foreground mt-1">
                            Riferimento: {section.definition_page_reference}
                            {section.definition_article_number && ` - ${section.definition_article_number}`}
                          </p>
                        )}
                      </div>

                      {section.value_type && (
                        <div className="flex items-center gap-2">
                          <Badge variant="secondary">{section.value_type}</Badge>
                          {section.primo_rischio_value && (
                            <span className="text-sm">{section.primo_rischio_value}</span>
                          )}
                        </div>
                      )}

                      {section.deroga_percentage && (
                        <div>
                          <span className="text-sm font-medium">Deroga: </span>
                          <span className="text-sm">{section.deroga_percentage}%</span>
                        </div>
                      )}

                      {section.determinazione && section.determinazione.length > 0 && (
                        <div>
                          <h5 className="font-medium mb-1">Determinazione</h5>
                          <div className="flex flex-wrap gap-1">
                            {section.determinazione.map((det, i) => (
                              <Badge key={i} variant="outline" className="text-xs">{det}</Badge>
                            ))}
                          </div>
                        </div>
                      )}
                    </CardContent>
                  </Card>
                ))}
              </div>
            </TabsContent>

            <TabsContent value="guarantees" className="space-y-4">
              <div className="grid gap-4">
                {data.guarantees_to_create.map((guarantee, index) => (
                  <Card key={index}>
                    <CardHeader>
                      <CardTitle className="flex items-center gap-2">
                        {guarantee.guarantee_name}
                        <Badge>{guarantee.guarantee_group}</Badge>
                      </CardTitle>
                      {guarantee.description && (
                        <CardDescription>
                          <RichTextDisplay content={guarantee.description} />
                        </CardDescription>
                      )}
                    </CardHeader>
                    <CardContent className="space-y-3">
                      {guarantee.available_parties_refs && guarantee.available_parties_refs.length > 0 && (
                        <div>
                          <h5 className="font-medium mb-1">Partite Applicabili</h5>
                          <div className="flex flex-wrap gap-1">
                            {guarantee.available_parties_refs.map((party, i) => (
                              <Badge key={i} variant="outline" className="text-xs">{party}</Badge>
                            ))}
                          </div>
                        </div>
                      )}

                      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                        {guarantee.maximum_value && (
                          <div className="p-3 border rounded-lg">
                            <h6 className="font-medium text-sm mb-1 text-green-700">Massimale</h6>
                            <p className="text-sm">{guarantee.maximum_value}</p>
                            {guarantee.maximum_applies_to && (
                              <p className="text-xs text-muted-foreground">{guarantee.maximum_applies_to}</p>
                            )}
                            {guarantee.maximum_page_reference && (
                              <p className="text-xs text-muted-foreground">
                                Ref: {guarantee.maximum_page_reference}
                                {guarantee.maximum_article_number && ` - ${guarantee.maximum_article_number}`}
                              </p>
                            )}
                          </div>
                        )}

                        {guarantee.deductible_value && (
                          <div className="p-3 border rounded-lg">
                            <h6 className="font-medium text-sm mb-1 text-orange-700">Franchigia</h6>
                            <p className="text-sm">{guarantee.deductible_value}</p>
                            {guarantee.deductible_applies_to && (
                              <p className="text-xs text-muted-foreground">{guarantee.deductible_applies_to}</p>
                            )}
                            {guarantee.deductible_page_reference && (
                              <p className="text-xs text-muted-foreground">
                                Ref: {guarantee.deductible_page_reference}
                                {guarantee.deductible_article_number && ` - ${guarantee.deductible_article_number}`}
                              </p>
                            )}
                          </div>
                        )}
                      </div>

                      {guarantee.guarantee_exclusions && guarantee.guarantee_exclusions.length > 0 && (
                        <div>
                          <h5 className="font-medium mb-1 text-red-700">Esclusioni Specifiche</h5>
                          <ul className="list-disc list-inside space-y-1">
                            {guarantee.guarantee_exclusions.map((exclusion, i) => (
                              <li key={i} className="text-sm">{exclusion}</li>
                            ))}
                          </ul>
                          {guarantee.exclusions_page_reference && (
                            <p className="text-xs text-muted-foreground mt-1">
                              Ref: {guarantee.exclusions_page_reference}
                              {guarantee.exclusions_article_number && ` - ${guarantee.exclusions_article_number}`}
                            </p>
                          )}
                        </div>
                      )}
                    </CardContent>
                  </Card>
                ))}
              </div>
            </TabsContent>

            <TabsContent value="limits" className="space-y-4">
              <div className="grid gap-4">
                {data.common_limits_to_create.map((limit, index) => (
                  <Card key={index}>
                    <CardContent className="pt-4">
                      <div className="flex justify-between items-start mb-2">
                        <h4 className="font-medium">{limit.label}</h4>
                        {limit.on_frontespizio && (
                          <Badge variant="secondary" className="text-xs">Su Frontespizio</Badge>
                        )}
                      </div>
                      <p className="text-sm text-muted-foreground mb-2">{limit.scope}</p>
                      <p className="text-sm font-medium">{limit.value}</p>
                      {limit.page_reference && (
                        <p className="text-xs text-muted-foreground mt-2">
                          Ref: {limit.page_reference}
                          {limit.article_number && ` - ${limit.article_number}`}
                        </p>
                      )}
                    </CardContent>
                  </Card>
                ))}
              </div>
            </TabsContent>

            <TabsContent value="notes" className="space-y-4">
              {data.special_notes && data.special_notes.length > 0 && (
                <Card>
                  <CardHeader>
                    <CardTitle>Note Speciali</CardTitle>
                  </CardHeader>
                  <CardContent>
                    <ul className="space-y-2">
                      {data.special_notes.map((note, index) => (
                        <li key={index} className="text-sm border-l-2 border-primary/20 pl-3">
                          {note}
                        </li>
                      ))}
                    </ul>
                  </CardContent>
                </Card>
              )}

              {data.unresolved && (
                <div className="space-y-4">
                  {data.unresolved.frontespizio_flags_set && data.unresolved.frontespizio_flags_set.length > 0 && (
                    <Alert>
                      <AlertTriangle className="h-4 w-4" />
                      <AlertDescription>
                        <strong>Valori da Frontespizio:</strong>
                        <ul className="mt-2 space-y-1">
                          {data.unresolved.frontespizio_flags_set.map((item, index) => (
                            <li key={index} className="text-sm">
                              • <code className="text-xs">{item.field}</code>: {item.reason}
                            </li>
                          ))}
                        </ul>
                      </AlertDescription>
                    </Alert>
                  )}

                  {data.unresolved.ambiguous_text && data.unresolved.ambiguous_text.length > 0 && (
                    <Alert>
                      <AlertTriangle className="h-4 w-4" />
                      <AlertDescription>
                        <strong>Testi Ambigui:</strong>
                        <ul className="mt-2 space-y-1">
                          {data.unresolved.ambiguous_text.map((item, index) => (
                            <li key={index} className="text-sm">
                              • "{item.quote}" ({item.pages.join(', ')}) - {item.why_ambiguous}
                            </li>
                          ))}
                        </ul>
                      </AlertDescription>
                    </Alert>
                  )}

                  {data.unresolved.missing_fields && data.unresolved.missing_fields.length > 0 && (
                    <Alert>
                      <XCircle className="h-4 w-4" />
                      <AlertDescription>
                        <strong>Campi Mancanti:</strong>
                        <ul className="mt-2 space-y-1">
                          {data.unresolved.missing_fields.map((item, index) => (
                            <li key={index} className="text-sm">
                              • <code className="text-xs">{item.path}</code>: {item.reason}
                            </li>
                          ))}
                        </ul>
                      </AlertDescription>
                    </Alert>
                  )}
                </div>
              )}
            </TabsContent>
          </Tabs>
        </ScrollArea>

        <div className="flex justify-between items-center pt-4 border-t">
          <div className="text-sm text-muted-foreground">
            Controlla accuratamente i dati prima di applicarli
          </div>
          <div className="flex gap-2">
            <Button variant="outline" onClick={onCancel} disabled={isApplying}>
              Annulla
            </Button>
            <Button onClick={onConfirm} disabled={isApplying}>
              {isApplying ? 'Applicando...' : 'Applica Dati'}
            </Button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
};