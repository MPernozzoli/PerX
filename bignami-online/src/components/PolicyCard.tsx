import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge"; 
import { Button } from "@/components/ui/button";
import { BookmarkIcon, EyeIcon, FileTextIcon, StarIcon } from "lucide-react";
import { PolicyWithEditions } from "@/types";
import { cn } from "@/lib/utils";
import { useNavigate } from "react-router-dom";

interface PolicyCardProps {
  policy: PolicyWithEditions;
  showStats?: boolean;
  viewCount?: number;
  isBookmarked?: boolean;
  onClick?: () => void;
  className?: string;
}

export const PolicyCard = ({ 
  policy, 
  showStats = false, 
  viewCount = 0, 
  isBookmarked = false,
  onClick,
  className 
}: PolicyCardProps) => {
  const navigate = useNavigate();
  const publishedEditions = policy.editions.filter(ed => ed.status === 'published');
  const draftEditions = policy.editions.filter(ed => ed.status === 'draft');
  const latestYear = Math.max(...publishedEditions.map(ed => ed.year));
  
  // Check for grouped editions
  const groupedEditions = publishedEditions.filter(ed => ed.canonical_group_id);
  const groupedYears = groupedEditions.map(ed => ed.year).sort();
  
  const getPolicyTypeColor = (type: string) => {
    switch(type) {
      case 'domestica': return 'bg-primary text-primary-foreground';
      case 'azienda': return 'bg-warning text-warning-foreground';
      case 'agricola': return 'bg-accent text-accent-foreground';
      default: return 'bg-secondary text-secondary-foreground';
    }
  };

  return (
    <Card 
      className={cn(
        "p-6 hover:shadow-lg transition-all duration-300 cursor-pointer border hover:border-primary/20 bg-card",
        className
      )}
      onClick={onClick}
    >
      <div className="flex items-start justify-between mb-4">
        <div className="flex-1">
          <div className="flex items-center gap-2 mb-2">
            <h3 className="text-lg font-semibold text-foreground">{policy.name}</h3>
            <Badge className={getPolicyTypeColor(policy.type)} variant="secondary">
              {policy.type}
            </Badge>
            {isBookmarked && (
              <StarIcon className="h-4 w-4 text-warning fill-current" />
            )}
          </div>
          
          <p className="text-sm text-muted-foreground mb-2">
            {policy.company?.name}
          </p>
          
          <p className="text-sm text-muted-foreground line-clamp-2">
            {policy.description}
          </p>
        </div>
        
        {showStats && (
          <div className="flex items-center gap-2 text-xs text-muted-foreground ml-4">
            <EyeIcon className="h-3 w-3" />
            <span>{viewCount}</span>
          </div>
        )}
      </div>
      
      <div className="flex flex-wrap gap-2 mb-4">
        {policy.tags.slice(0, 3).map(tag => (
          <Badge key={tag} variant="outline" className="text-xs">
            {tag}
          </Badge>
        ))}
        {policy.tags.length > 3 && (
          <Badge variant="outline" className="text-xs">
            +{policy.tags.length - 3}
          </Badge>
        )}
      </div>
      
      <div className="space-y-2">
        {/* Edition info */}
        <div className="flex items-center justify-between text-sm">
          <span className="text-muted-foreground">
            Edizioni disponibili: {publishedEditions.length}
            {draftEditions.length > 0 && ` (+${draftEditions.length} bozze)`}
          </span>
          <span className="font-medium">
            Ultima: {latestYear}
          </span>
        </div>
        
        {/* Grouped editions indicator */}
        {groupedYears.length > 1 && (
          <div className="flex items-center gap-2">
            <Badge className="bg-badge-raggruppata text-white text-xs">
              Raggruppate
            </Badge>
            <span className="text-xs text-muted-foreground">
              Condizioni identiche: {groupedYears.join(', ')}
            </span>
          </div>
        )}
        
        {/* PDF availability */}
        {publishedEditions.some(ed => ed.pdf_url) && (
          <div className="flex items-center gap-1 text-xs text-muted-foreground">
            <FileTextIcon className="h-3 w-3" />
            <span>PDF disponibili</span>
          </div>
        )}
      </div>
      
      <div className="flex items-center justify-between mt-4 pt-4 border-t">
        <div className="flex items-center gap-2">
          <Badge variant="outline" className="text-xs">
            {policy.default_guarantee}
          </Badge>
        </div>
        
        <div className="flex gap-2">
          <Button size="sm" variant="ghost" className="h-8 px-2">
            <BookmarkIcon className="h-3 w-3" />
          </Button>
          <Button 
            size="sm" 
            variant="outline" 
            className="h-8"
            onClick={(e) => {
              e.stopPropagation();
              if (onClick) {
                onClick();
              } else {
                const latestEdition = policy.latestEdition || publishedEditions[0];
                if (latestEdition && policy.company?.code && policy.code) {
                  navigate(`/${policy.company.code}/${policy.code}/${latestEdition.code}`);
                } else if (policy.company?.code && policy.code) {
                  navigate(`/${policy.company.code}/${policy.code}`);
                } else {
                  // Fallback to legacy URLs
                  const editionId = latestEdition?.id;
                  if (editionId) {
                    navigate(`/policy/${policy.id}/edition/${editionId}`);
                  } else {
                    navigate(`/policy/${policy.id}`);
                  }
                }
              }
            }}
          >
            Visualizza
          </Button>
        </div>
      </div>
    </Card>
  );
};