import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { History, ChevronDown, ChevronUp } from "lucide-react";
import { useEditHistory } from "@/hooks/useEditHistory";
import { formatDistanceToNow } from "date-fns";
import { it } from "date-fns/locale";
import { useState } from "react";
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible";

interface PolicyHistoryProps {
  policyId: string;
  editionId?: string;
}

export const PolicyHistory = ({ policyId, editionId }: PolicyHistoryProps) => {
  const [expandedItems, setExpandedItems] = useState<Set<string>>(new Set());

  const targetId = editionId || policyId;
  const targetType = editionId ? 'policy_edition' : 'policy';

  const { data: history = [], isLoading } = useEditHistory(targetId, targetType);

  const toggleExpanded = (id: string) => {
    const newExpanded = new Set(expandedItems);
    if (newExpanded.has(id)) {
      newExpanded.delete(id);
    } else {
      newExpanded.add(id);
    }
    setExpandedItems(newExpanded);
  };

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'approved':
        return 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200';
      case 'rejected':
        return 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200';
      case 'pending':
      default:
        return 'bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200';
    }
  };

  const getStatusLabel = (status: string) => {
    switch (status) {
      case 'approved':
        return 'Approvato';
      case 'rejected':
        return 'Rifiutato';
      case 'pending':
      default:
        return 'In attesa';
    }
  };

  if (isLoading) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <History className="h-5 w-5" />
            Cronologia modifiche
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="text-sm text-muted-foreground">Caricamento cronologia...</div>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <History className="h-5 w-5" />
          Cronologia modifiche ({history.length})
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        {history.length === 0 ? (
          <div className="text-center py-8 text-muted-foreground">
            <History className="h-12 w-12 mx-auto mb-3 opacity-50" />
            <p>Nessuna modifica registrata</p>
            <p className="text-sm">Le modifiche future saranno registrate qui</p>
          </div>
        ) : (
          <div className="space-y-3">
            {history.map((edit) => (
              <Collapsible key={edit.id}>
                <div className="border rounded-lg p-4">
                  <div className="flex items-start justify-between mb-2">
                    <div className="flex items-center gap-2">
                      <span className="font-medium text-sm">
                        {edit.user?.name || 'Utente sconosciuto'}
                      </span>
                      <Badge variant="secondary" className={`text-xs ${getStatusColor(edit.status)}`}>
                        {getStatusLabel(edit.status)}
                      </Badge>
                    </div>
                    <span className="text-xs text-muted-foreground">
                      {formatDistanceToNow(new Date(edit.created_at), {
                        addSuffix: true,
                        locale: it
                      })}
                    </span>
                  </div>
                  
                  <div className="text-sm mb-3">
                    {edit.change_summary}
                  </div>

                  {edit.diff && (
                    <CollapsibleTrigger asChild>
                      <Button
                        variant="ghost"
                        size="sm"
                        className="text-xs"
                        onClick={() => toggleExpanded(edit.id)}
                      >
                        {expandedItems.has(edit.id) ? (
                          <>
                            <ChevronUp className="h-3 w-3 mr-1" />
                            Nascondi dettagli
                          </>
                        ) : (
                          <>
                            <ChevronDown className="h-3 w-3 mr-1" />
                            Mostra dettagli
                          </>
                        )}
                      </Button>
                    </CollapsibleTrigger>
                  )}

                  {edit.diff && (
                    <CollapsibleContent className="mt-3">
                      <div className="bg-muted rounded p-3 text-xs">
                        <pre className="whitespace-pre-wrap overflow-x-auto">
                          {JSON.stringify(edit.diff, null, 2)}
                        </pre>
                      </div>
                    </CollapsibleContent>
                  )}
                </div>
              </Collapsible>
            ))}
          </div>
        )}
      </CardContent>
    </Card>
  );
};