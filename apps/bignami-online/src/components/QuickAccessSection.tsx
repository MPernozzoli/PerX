import { useState } from "react";
import { Button } from "@perx/ui/components/ui/button";
import { Card } from "@perx/ui/components/ui/card";
import { Badge } from "@perx/ui/components/ui/badge";
import { 
  ClockIcon,
  TrendingUpIcon,
  BookmarkIcon,
  EyeIcon,
  StarIcon
} from "lucide-react";
import { PolicyCard } from "./PolicyCard";
import { PolicyWithEditions } from "@/types";
import { 
  useRecentPolicies, 
  useFrequentPolicies, 
  useBookmarkedPolicies,
  useUserInteractions
} from "@/hooks/useUserInteractions";
import { useAuth } from "@/contexts/AuthContext";

type QuickAccessType = 'recent' | 'frequent' | 'bookmarked';

export const QuickAccessSection = () => {
  const [activeTab, setActiveTab] = useState<QuickAccessType>('recent');
  const { user } = useAuth();
  
  const { data: recentPolicies = [] } = useRecentPolicies(user?.id);
  const { data: frequentPolicies = [] } = useFrequentPolicies(user?.id);
  const { data: bookmarkedPolicies = [] } = useBookmarkedPolicies(user?.id);
  const { data: interactions = [] } = useUserInteractions(user?.id);
  
  const tabs = [
    {
      key: 'recent' as const,
      label: 'Visualizzate di recente',
      icon: ClockIcon,
      policies: recentPolicies
    },
    {
      key: 'frequent' as const,
      label: 'Più frequenti',
      icon: TrendingUpIcon,
      policies: frequentPolicies
    },
    {
      key: 'bookmarked' as const,
      label: 'Salvate',
      icon: BookmarkIcon,
      policies: bookmarkedPolicies
    }
  ];

  const currentTab = tabs.find(tab => tab.key === activeTab);
  const policies = currentTab?.policies || [];
  
  const getInteractionData = (policyId: string, editionId?: string) => {
    return interactions.find(
      i => i.policy_id === policyId && 
      (!editionId || i.policy_edition_id === editionId)
    );
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h2 className="text-lg font-semibold">Accesso Rapido</h2>
        <div className="flex gap-1 bg-muted p-1 rounded-lg">
          {tabs.map(tab => {
            const Icon = tab.icon;
            return (
              <Button
                key={tab.key}
                variant={activeTab === tab.key ? "default" : "ghost"}
                size="sm"
                onClick={() => setActiveTab(tab.key)}
                className="gap-2"
              >
                <Icon className="h-4 w-4" />
                <span className="hidden sm:inline">{tab.label}</span>
              </Button>
            );
          })}
        </div>
      </div>

      {policies.length === 0 ? (
        <Card className="p-8 text-center">
          <div className="text-muted-foreground">
            {activeTab === 'recent' && "Nessuna polizza visualizzata di recente"}
            {activeTab === 'frequent' && "Nessuna polizza consultata frequentemente"}
            {activeTab === 'bookmarked' && "Nessuna polizza salvata"}
          </div>
        </Card>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {policies.map(policy => {
            const interaction = getInteractionData(
              policy.id, 
              policy.latestEdition?.id
            );
            
            return (
              <PolicyCard
                key={`${policy.id}-${policy.latestEdition?.id}`}
                policy={policy}
                showStats={activeTab === 'frequent'}
                viewCount={interaction?.view_count || 0}
                isBookmarked={interaction?.bookmarked || false}
                onClick={() => {
                  const editionId = policy.latestEdition?.id;
                  if (editionId) {
                    window.location.href = `/policy/${policy.id}/edition/${editionId}`;
                  }
                }}
                className="h-full"
              />
            );
          })}
        </div>
      )}

      {policies.length > 0 && (
        <div className="flex justify-center">
          <Button variant="outline">
            Visualizza tutte ({policies.length})
          </Button>
        </div>
      )}
    </div>
  );
};