import { useState } from "react";
import { Card, CardContent, CardHeader, CardTitle } from "@perx/ui/components/ui/card";
import { Button } from "@perx/ui/components/ui/button";
import { Textarea } from "@perx/ui/components/ui/textarea";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@perx/ui/components/ui/select";
import { Badge } from "@perx/ui/components/ui/badge";
import { MessageCircle, Plus, Eye, EyeOff, Users } from "lucide-react";
import { useComments, useCreateComment, useUpdateComment } from "@/hooks/useComments";
import { formatDistanceToNow } from "date-fns";
import { it } from "date-fns/locale";
import { toast } from "sonner";

interface PolicyCommentsProps {
  policyId: string;
  editionId?: string;
}

export const PolicyComments = ({ policyId, editionId }: PolicyCommentsProps) => {
  const [newComment, setNewComment] = useState("");
  const [newCommentVisibility, setNewCommentVisibility] = useState<'public' | 'private' | 'studio'>('public');
  const [showAddForm, setShowAddForm] = useState(false);

  const targetId = editionId || policyId;
  const targetType = editionId ? 'policy_edition' : 'policy';

  const { data: comments = [], isLoading } = useComments(targetId, targetType);
  const createCommentMutation = useCreateComment();
  const updateCommentMutation = useUpdateComment();

  const handleSubmitComment = async () => {
    if (!newComment.trim()) return;

    try {
      await createCommentMutation.mutateAsync({
        targetId,
        targetType,
        body: newComment,
        visibility: newCommentVisibility
      });
      
      setNewComment("");
      setShowAddForm(false);
      toast.success("Commento aggiunto con successo");
    } catch (error) {
      toast.error("Errore nell'aggiungere il commento");
    }
  };

  const handleToggleResolved = async (commentId: string, currentResolved: boolean) => {
    try {
      await updateCommentMutation.mutateAsync({
        commentId,
        resolved: !currentResolved
      });
      toast.success(currentResolved ? "Commento riaperto" : "Commento risolto");
    } catch (error) {
      toast.error("Errore nell'aggiornare il commento");
    }
  };

  const getVisibilityIcon = (visibility: string) => {
    switch (visibility) {
      case 'private':
        return <EyeOff className="h-3 w-3" />;
      case 'studio':
        return <Users className="h-3 w-3" />;
      case 'public':
      default:
        return <Eye className="h-3 w-3" />;
    }
  };

  const getVisibilityLabel = (visibility: string) => {
    switch (visibility) {
      case 'private':
        return 'Privato';
      case 'studio':
        return 'Studio';
      case 'public':
      default:
        return 'Pubblico';
    }
  };

  const getVisibilityColor = (visibility: string) => {
    switch (visibility) {
      case 'private':
        return 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200';
      case 'studio':
        return 'bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200';
      case 'public':
      default:
        return 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200';
    }
  };

  if (isLoading) {
    return (
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <MessageCircle className="h-5 w-5" />
            Commenti
          </CardTitle>
        </CardHeader>
        <CardContent>
          <div className="text-sm text-muted-foreground">Caricamento commenti...</div>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <MessageCircle className="h-5 w-5" />
            Commenti ({comments.length})
          </div>
          <Button
            variant="outline"
            size="sm"
            onClick={() => setShowAddForm(!showAddForm)}
          >
            <Plus className="h-4 w-4 mr-2" />
            Aggiungi
          </Button>
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        {showAddForm && (
          <div className="border rounded-lg p-4 space-y-3">
            <Textarea
              placeholder="Scrivi un commento..."
              value={newComment}
              onChange={(e) => setNewComment(e.target.value)}
              className="min-h-[80px]"
            />
            <div className="flex items-center justify-between">
              <Select value={newCommentVisibility} onValueChange={(value: 'public' | 'private' | 'studio') => setNewCommentVisibility(value)}>
                <SelectTrigger className="w-[140px]">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="public">
                    <div className="flex items-center gap-2">
                      <Eye className="h-3 w-3" />
                      Pubblico
                    </div>
                  </SelectItem>
                  <SelectItem value="studio">
                    <div className="flex items-center gap-2">
                      <Users className="h-3 w-3" />
                      Studio
                    </div>
                  </SelectItem>
                  <SelectItem value="private">
                    <div className="flex items-center gap-2">
                      <EyeOff className="h-3 w-3" />
                      Privato
                    </div>
                  </SelectItem>
                </SelectContent>
              </Select>
              <div className="flex gap-2">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => setShowAddForm(false)}
                >
                  Annulla
                </Button>
                <Button
                  size="sm"
                  onClick={handleSubmitComment}
                  disabled={!newComment.trim() || createCommentMutation.isPending}
                >
                  {createCommentMutation.isPending ? "Invio..." : "Invia"}
                </Button>
              </div>
            </div>
          </div>
        )}

        <div className="space-y-3">
          {comments.length === 0 ? (
            <div className="text-center py-8 text-muted-foreground">
              <MessageCircle className="h-12 w-12 mx-auto mb-3 opacity-50" />
              <p>Nessun commento presente</p>
              <p className="text-sm">Aggiungi il primo commento per iniziare la discussione</p>
            </div>
          ) : (
            comments.map((comment) => (
              <div
                key={comment.id}
                className={`border rounded-lg p-4 ${comment.resolved ? 'opacity-60 bg-muted/30' : ''}`}
              >
                <div className="flex items-start justify-between mb-2">
                  <div className="flex items-center gap-2">
                    <span className="font-medium text-sm">
                      {comment.user?.name || 'Utente sconosciuto'}
                    </span>
                    <Badge variant="secondary" className={`text-xs ${getVisibilityColor(comment.visibility)}`}>
                      <div className="flex items-center gap-1">
                        {getVisibilityIcon(comment.visibility)}
                        {getVisibilityLabel(comment.visibility)}
                      </div>
                    </Badge>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="text-xs text-muted-foreground">
                      {formatDistanceToNow(new Date(comment.created_at), {
                        addSuffix: true,
                        locale: it
                      })}
                    </span>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => handleToggleResolved(comment.id, comment.resolved)}
                      className="text-xs"
                    >
                      {comment.resolved ? 'Riapri' : 'Risolvi'}
                    </Button>
                  </div>
                </div>
                <div 
                  className="text-sm prose prose-sm max-w-none"
                  dangerouslySetInnerHTML={{ __html: comment.body }}
                />
                {comment.resolved && (
                  <Badge variant="outline" className="mt-2 text-xs">
                    Risolto
                  </Badge>
                )}
              </div>
            ))
          )}
        </div>
      </CardContent>
    </Card>
  );
};