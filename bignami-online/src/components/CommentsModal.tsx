import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { MessageSquareIcon, PlusIcon } from "lucide-react";
import { useState } from "react";

interface CommentsModalProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export const CommentsModal = ({ open, onOpenChange }: CommentsModalProps) => {
  const [newComment, setNewComment] = useState("");
  const [showNewCommentForm, setShowNewCommentForm] = useState(false);

  const handleAddComment = () => {
    // TODO: Implement comment submission
    console.log("Adding comment:", newComment);
    setNewComment("");
    setShowNewCommentForm(false);
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-3xl max-h-[80vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <MessageSquareIcon className="h-5 w-5" />
            Commenti
          </DialogTitle>
        </DialogHeader>
        
        <div className="space-y-4">
          {!showNewCommentForm ? (
            <Button 
              onClick={() => setShowNewCommentForm(true)}
              className="w-full gap-2"
              variant="outline"
            >
              <PlusIcon className="h-4 w-4" />
              Nuovo Commento
            </Button>
          ) : (
            <div className="space-y-3 p-4 border rounded-lg">
              <Textarea
                placeholder="Scrivi il tuo commento..."
                value={newComment}
                onChange={(e) => setNewComment(e.target.value)}
                className="min-h-[100px]"
              />
              <div className="flex gap-2 justify-end">
                <Button 
                  variant="outline" 
                  size="sm"
                  onClick={() => {
                    setShowNewCommentForm(false);
                    setNewComment("");
                  }}
                >
                  Annulla
                </Button>
                <Button 
                  size="sm"
                  onClick={handleAddComment}
                  disabled={!newComment.trim()}
                >
                  Pubblica
                </Button>
              </div>
            </div>
          )}

          <div className="text-center text-muted-foreground py-8">
            Nessun commento disponibile
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
};