import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { Layout } from "@/components/Layout";
import { SearchBar } from "@/components/SearchBar";
import { QuickAccessSection } from "@/components/QuickAccessSection";
import { PolicyCard } from "@/components/PolicyCard";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { 
  SearchIcon,
  FilterIcon,
  BookOpenIcon,
  ZapIcon,
  TrendingUpIcon
} from "lucide-react";
import { PolicyWithEditions } from "@/types";
import { usePolicies } from "@/hooks/usePolicies";
import { useSearchPolicies } from "@/hooks/useSearchPolicies";
import { useCompanies } from "@/hooks/useCompanies";

export const HomePage = () => {
  const navigate = useNavigate();
  const [searchQuery, setSearchQuery] = useState("");
  const [searchFilters, setSearchFilters] = useState<any>({});
  const [isSearching, setIsSearching] = useState(false);

  const { data: allPolicies = [] } = usePolicies();
  const { data: companies = [] } = useCompanies();
  const { data: searchResults = [], isLoading: isSearchLoading } = useSearchPolicies(
    searchQuery, 
    searchFilters
  );

  const handleSearch = (query: string, filters?: any) => {
    setIsSearching(!!query.trim());
    setSearchQuery(query);
    setSearchFilters(filters || {});
  };

  const totalEditions = allPolicies.reduce((sum, policy) => sum + (policy.policy_editions?.length || 0), 0);

  return (
    <Layout>
      <div className="space-y-8">
        {/* Hero Section */}
        <div className="text-center space-y-4">
          <h1 className="text-3xl font-bold">
            Bignami Online
          </h1>
          <p className="text-lg text-muted-foreground max-w-2xl mx-auto">
            Consultazione rapida delle condizioni di polizza per periti property. 
            Ricerca intelligente, confronto edizioni, editing collaborativo.
          </p>
          
          {/* Quick stats */}
          <div className="flex justify-center gap-6 pt-4">
            <div className="text-center">
              <div className="text-2xl font-bold text-primary">{allPolicies.length}</div>
              <div className="text-sm text-muted-foreground">Polizze</div>
            </div>
            <div className="text-center">
              <div className="text-2xl font-bold text-primary">{totalEditions}</div>
              <div className="text-sm text-muted-foreground">Edizioni</div>
            </div>
            <div className="text-center">
              <div className="text-2xl font-bold text-primary">{companies.length}</div>
              <div className="text-sm text-muted-foreground">Compagnie</div>
            </div>
          </div>
        </div>

        {/* Search Section */}
        <Card className="p-6">
          <div className="flex items-center gap-2 mb-4">
            <SearchIcon className="h-5 w-5 text-primary" />
            <h2 className="text-lg font-semibold">Ricerca Polizze</h2>
          </div>
          <SearchBar onSearch={handleSearch} />
        </Card>

        {/* Search Results */}
        {isSearching && (
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <h2 className="text-lg font-semibold">
                Risultati ricerca
                {searchQuery && ` per "${searchQuery}"`}
              </h2>
              <Badge variant="outline">
                {searchResults.length} risultati
              </Badge>
            </div>

            {isSearchLoading ? (
              <Card className="p-8 text-center">
                <div className="text-muted-foreground">
                  Ricerca in corso...
                </div>
              </Card>
            ) : searchResults.length === 0 ? (
              <Card className="p-8 text-center">
                <div className="text-muted-foreground">
                  Nessuna polizza trovata per la ricerca corrente.
                  <br />
                  Prova a modificare i termini di ricerca o i filtri.
                </div>
              </Card>
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                {searchResults.map(policy => (
                <PolicyCard
                  key={policy.id}
                  policy={policy}
                  onClick={() => {
                    const editionId = policy.latestEdition?.id || policy.editions[0]?.id;
                    if (editionId) {
                      window.location.href = `/policy/${policy.id}/edition/${editionId}`;
                    }
                  }}
                />
                ))}
              </div>
            )}
          </div>
        )}

        {/* Quick Access Section - only show when not searching */}
        {!isSearching && allPolicies.length > 0 && <QuickAccessSection />}

        {/* Popular Policies - only show when not searching and we have policies */}
        {!isSearching && allPolicies.length > 0 && (
          <div className="space-y-4">
            <div className="flex items-center gap-2">
              <TrendingUpIcon className="h-5 w-5 text-primary" />
              <h2 className="text-lg font-semibold">Polizze Popolari</h2>
            </div>
            
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              {allPolicies.slice(0, 3).map(policy => {
                const policyWithEditions: PolicyWithEditions = {
                  ...policy,
                  type: policy.type as 'domestica' | 'azienda' | 'agricola',
                  company: policy.companies,
                  editions: policy.policy_editions.map(edition => ({
                    ...edition,
                    status: edition.status as 'draft' | 'published'
                  })) || [],
                  latestEdition: policy.policy_editions?.sort((a, b) => b.year - a.year)[0] ? {
                    ...policy.policy_editions.sort((a, b) => b.year - a.year)[0],
                    status: policy.policy_editions.sort((a, b) => b.year - a.year)[0].status as 'draft' | 'published'
                  } : undefined
                };
                
                return (
                  <PolicyCard
                    key={policy.id}
                    policy={policyWithEditions}
                    onClick={() => {
                      const editionId = policyWithEditions.latestEdition?.id || policyWithEditions.editions[0]?.id;
                      if (editionId) {
                        window.location.href = `/policy/${policy.id}/edition/${editionId}`;
                      }
                    }}
                  />
                );
              })}
            </div>
          </div>
        )}

        {/* Empty State - when no policies exist */}
        {!isSearching && allPolicies.length === 0 && (
          <Card className="p-8 text-center">
            <div className="space-y-4">
              <BookOpenIcon className="h-12 w-12 text-muted-foreground mx-auto" />
              <div>
                <h3 className="text-lg font-semibold mb-2">Nessuna polizza ancora inserita</h3>
                <p className="text-muted-foreground mb-4">
                  Inizia aggiungendo la prima polizza al sistema.
                  <br />
                  Potrai poi gestire coperture, sezioni e garanzie.
                </p>
                <Button onClick={() => navigate("/add-policy")} className="gap-2">
                  <ZapIcon className="h-4 w-4" />
                  Aggiungi Prima Polizza
                </Button>
              </div>
            </div>
          </Card>
        )}

        {/* Quick Actions */}
        {!isSearching && (
          <Card className="p-6 bg-muted/30">
            <h3 className="font-semibold mb-4">Azioni Rapide</h3>
            <div className="flex flex-wrap gap-3">
              <Button variant="outline" className="gap-2">
                <BookOpenIcon className="h-4 w-4" />
                Riferimenti Normativi
              </Button>
              <Button variant="outline" className="gap-2">
                <FilterIcon className="h-4 w-4" />
                Ricerca Avanzata
              </Button>
              <Button className="gap-2" onClick={() => navigate("/add-policy")}>
                <ZapIcon className="h-4 w-4" />
                Nuova Polizza
              </Button>
            </div>
          </Card>
        )}
      </div>
    </Layout>
  );
};