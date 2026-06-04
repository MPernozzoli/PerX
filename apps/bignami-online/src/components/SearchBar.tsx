import { useState } from "react";
import { Input } from "@perx/ui/components/ui/input";
import { Button } from "@perx/ui/components/ui/button";
import { Badge } from "@perx/ui/components/ui/badge";
import { Card } from "@perx/ui/components/ui/card";
import { 
  SearchIcon, 
  SlidersHorizontalIcon,
  XIcon,
  FilterIcon,
  PlusIcon,
  MinusIcon
} from "lucide-react";
import { 
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@perx/ui/components/ui/select";
import { cn } from "@/lib/utils";
import { PolicyType, GuaranteeType } from "@/types";
import { useCompanies } from "@/hooks/useCompanies";
import { useUserPreferences } from "@/hooks/useUserPreferences";
import { useGuaranteeGroups, GuaranteeGroup } from "@/hooks/useGuaranteeGroups";

interface SearchBarProps {
  onSearch: (query: string, filters?: SearchFilters) => void;
  className?: string;
}

interface SearchFilters {
  company?: string;
  policy?: string;
  year?: number;
  type?: PolicyType;
  guarantee?: GuaranteeType;
}

export const SearchBar = ({ onSearch, className }: SearchBarProps) => {
  const [query, setQuery] = useState("");
  const [showAdvanced, setShowAdvanced] = useState(false);
  const { preferences } = useUserPreferences();
  const [filters, setFilters] = useState<SearchFilters>({
    guarantee: preferences?.default_guarantee || 'FE',
    company: preferences?.default_company || undefined
  });
  
  const [recognizedTerms, setRecognizedTerms] = useState<string[]>([]);
  const { data: companies = [] } = useCompanies();
  const { data: guaranteeGroups = [] } = useGuaranteeGroups();

  const handleSearch = () => {
    // Simple NLP parsing simulation
    const terms = parseQuery(query);
    setRecognizedTerms(terms);
    onSearch(query, filters);
  };

  const parseQuery = (query: string): string[] => {
    const terms: string[] = [];
    const lowerQuery = query.toLowerCase();
    
    // Recognize companies dynamically from database
    companies.forEach(company => {
      if (lowerQuery.includes(company.name.toLowerCase())) {
        terms.push(`Compagnia: ${company.name}`);
      }
      // Check aliases
      company.aliases?.forEach(alias => {
        if (lowerQuery.includes(alias.toLowerCase())) {
          terms.push(`Compagnia: ${alias}`);
        }
      });
    });
    
    // Recognize years
    const yearMatch = query.match(/20\d{2}/);
    if (yearMatch) terms.push(`Anno: ${yearMatch[0]}`);
    
    // Recognize types
    if (lowerQuery.includes('domestica')) terms.push('Tipo: domestica');
    if (lowerQuery.includes('azienda') || lowerQuery.includes('commerciale')) terms.push('Tipo: azienda');
    if (lowerQuery.includes('agricola')) terms.push('Tipo: agricola');
    
    return terms;
  };

  const clearFilter = (filterKey: keyof SearchFilters) => {
    const newFilters = { ...filters };
    delete newFilters[filterKey];
    // Keep guarantee as default
    if (filterKey !== 'guarantee') {
      setFilters(newFilters);
    }
  };

  const clearRecognizedTerm = (index: number) => {
    setRecognizedTerms(prev => prev.filter((_, i) => i !== index));
  };

  return (
    <div className={cn("space-y-4", className)}>
      {/* Main search */}
      <div className="relative">
        <SearchIcon className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-muted-foreground" />
        <Input
          placeholder="Es. Cattolica Casa&Persona, anno 2021, domestica — FE"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && handleSearch()}
          className="pl-10 pr-24 h-12 text-base"
        />
        <div className="absolute right-2 top-1/2 transform -translate-y-1/2 flex gap-2">
          <Button
            variant="ghost"
            size="sm"
            onClick={() => setShowAdvanced(!showAdvanced)}
            className="h-8"
          >
            <SlidersHorizontalIcon className="h-4 w-4" />
          </Button>
          <Button onClick={handleSearch} className="h-8">
            Cerca
          </Button>
        </div>
      </div>

      {/* Recognized terms from NLP */}
      {recognizedTerms.length > 0 && (
        <div className="flex flex-wrap gap-2">
          <span className="text-sm text-muted-foreground">Riconosciuto:</span>
          {recognizedTerms.map((term, index) => (
            <Badge 
              key={index} 
              variant="secondary" 
              className="gap-1 bg-primary/10 text-primary"
            >
              {term}
              <button
                onClick={() => clearRecognizedTerm(index)}
                className="ml-1 hover:bg-primary/20 rounded-full p-0.5"
              >
                <XIcon className="h-3 w-3" />
              </button>
            </Badge>
          ))}
        </div>
      )}

      {/* Advanced search */}
      {showAdvanced && (
        <Card className="p-4 bg-muted/30">
          <div className="flex items-center gap-2 mb-4">
            <FilterIcon className="h-4 w-4 text-muted-foreground" />
            <span className="font-medium">Ricerca avanzata</span>
          </div>
          
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            <div className="space-y-2">
              <label className="text-sm font-medium">Compagnia</label>
              <Select 
                value={filters.company} 
                onValueChange={(value) => setFilters(prev => ({ ...prev, company: value }))}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Seleziona..." />
                </SelectTrigger>
                <SelectContent>
                  {companies.map(company => (
                    <SelectItem key={company.id} value={company.name}>
                      {company.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-2">
              <label className="text-sm font-medium">Tipo Polizza</label>
              <Select 
                value={filters.type} 
                onValueChange={(value) => setFilters(prev => ({ ...prev, type: value as PolicyType }))}
              >
                <SelectTrigger>
                  <SelectValue placeholder="Tutti" />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="domestica">Domestica</SelectItem>
                  <SelectItem value="azienda">Azienda</SelectItem>
                  <SelectItem value="agricola">Agricola</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-2">
              <label className="text-sm font-medium">Anno</label>
              <div className="flex items-center">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => {
                    const currentYear = filters.year || new Date().getFullYear();
                    if (currentYear > 2000) {
                      setFilters(prev => ({ ...prev, year: currentYear - 1 }));
                    }
                  }}
                  className="h-10 w-10 p-0 rounded-r-none border-r-0"
                >
                  <MinusIcon className="h-4 w-4" />
                </Button>
                <Input
                  type="number"
                  value={filters.year || ''}
                  onChange={(e) => {
                    const year = parseInt(e.target.value);
                    if (!isNaN(year) && year >= 2000 && year <= 2030) {
                      setFilters(prev => ({ ...prev, year }));
                    } else if (e.target.value === '') {
                      setFilters(prev => ({ ...prev, year: undefined }));
                    }
                  }}
                  placeholder="Anno"
                  className="h-10 rounded-none border-x-0 text-center [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none"
                  min="2000"
                  max="2030"
                />
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => {
                    const currentYear = filters.year || new Date().getFullYear();
                    if (currentYear < 2030) {
                      setFilters(prev => ({ ...prev, year: currentYear + 1 }));
                    }
                  }}
                  className="h-10 w-10 p-0 rounded-l-none border-l-0"
                >
                  <PlusIcon className="h-4 w-4" />
                </Button>
              </div>
            </div>

            <div className="space-y-2">
              <label className="text-sm font-medium">Garanzia</label>
              <Select 
                value={filters.guarantee} 
                onValueChange={(value) => setFilters(prev => ({ ...prev, guarantee: value as GuaranteeType }))}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {guaranteeGroups.map(group => (
                    <SelectItem key={group.id} value={group.code}>{group.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>

          {/* Active filters */}
          {Object.entries(filters).some(([key, value]) => value && key !== 'guarantee') && (
            <div className="mt-4 pt-4 border-t">
              <div className="flex flex-wrap gap-2">
                <span className="text-sm text-muted-foreground">Filtri attivi:</span>
                {Object.entries(filters).map(([key, value]) => {
                  if (!value || key === 'guarantee') return null;
                  return (
                    <Badge key={key} variant="outline" className="gap-1">
                      {key}: {value}
                      <button
                        onClick={() => clearFilter(key as keyof SearchFilters)}
                        className="ml-1 hover:bg-destructive/20 rounded-full p-0.5"
                      >
                        <XIcon className="h-3 w-3" />
                      </button>
                    </Badge>
                  );
                })}
              </div>
            </div>
          )}
        </Card>
      )}
    </div>
  );
};
