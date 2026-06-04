import { useState, useEffect, useCallback, useRef } from 'react';
import { Search, Loader2, MapPin, Building2, X } from 'lucide-react';
import { Input } from '@/components/ui/input';
import { useQuery } from '@tanstack/react-query';
import { normalizeText, getProvinceName } from '@/lib/textUtils';
import { searchCache } from '@/lib/searchCache';
import { perxGet } from '@/lib/perxApi';
import { Button } from '@/components/ui/button';
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandItem,
  CommandList,
} from '@/components/ui/command';
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from '@/components/ui/popover';
import { Badge } from '@/components/ui/badge';

interface SearchResult {
  id: string;
  type: 'comune' | 'quartiere' | 'cat' | 'address';
  label: string;
  sublabel?: string;
  alias?: string;
  icon: string;
  coordinates?: { lat: number; lng: number };
  catName?: string;
  catColor?: string;
}

interface SearchBarProps {
  onSelect?: (result: SearchResult) => void;
  mapBounds?: { north: number; south: number; east: number; west: number } | null;
  initialValue?: string;
}

const SearchBar = ({ onSelect, mapBounds, initialValue }: SearchBarProps) => {
  const [open, setOpen] = useState(false);
  const [searchTerm, setSearchTerm] = useState('');
  const [debouncedSearchTerm, setDebouncedSearchTerm] = useState('');
  const [cachedResults, setCachedResults] = useState<SearchResult[] | null>(null);
  const [isFromCache, setIsFromCache] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const isSelectingRef = useRef(false);
  const initialValueProcessedRef = useRef(false);
  
  // Handle initial value from URL
  useEffect(() => {
    if (initialValue && !initialValueProcessedRef.current) {
      initialValueProcessedRef.current = true;
      setSearchTerm(initialValue);
      setDebouncedSearchTerm(initialValue);
      setOpen(true);
    }
  }, [initialValue]);

  // Debounce search term and check cache immediately
  useEffect(() => {
    // Check cache immediately for instant results
    if (searchTerm.length >= 2) {
      const cached = searchCache.get(searchTerm);
      if (cached) {
        console.log('⚡ Loading from cache:', searchTerm);
        setCachedResults(cached);
        setIsFromCache(true);
      } else {
        setCachedResults(null);
        setIsFromCache(false);
      }
    } else {
      setCachedResults(null);
      setIsFromCache(false);
    }

    const timer = setTimeout(() => {
      if (!isSelectingRef.current) {
        setDebouncedSearchTerm(searchTerm);
      }
    }, 400);

    return () => clearTimeout(timer);
  }, [searchTerm]);

  // Search communes and cats using protected edge function
  const { data: searchResults, isLoading } = useQuery({
    queryKey: ['search-protected', debouncedSearchTerm],
    queryFn: async () => {
      if (!debouncedSearchTerm || debouncedSearchTerm.length < 2) return [];

      const results: SearchResult[] = [];
      const term = debouncedSearchTerm.trim().slice(0, 100);

      console.log('Searching via PerX API:', term);

      const data = await perxGet<any>(`/cat-dispatcher/search?query=${encodeURIComponent(term)}`);

      if (!data?.results) {
        return [];
      }

      // Process communes
      if (data.results.communes && Array.isArray(data.results.communes)) {
        const seenComunes = new Set<string>();
        
        for (const c of data.results.communes) {
          if (c.quartiere) {
            results.push({
              id: c.id,
              type: 'quartiere',
              label: c.quartiere,
              sublabel: `${normalizeText(c.comune)}, ${getProvinceName(c.provincia) || 'N/D'}`,
              alias: c.alias || undefined,
              icon: 'quartiere',
              catName: c.cat_name,
              catColor: c.cat_color
            });
          } else if (!seenComunes.has(c.comune)) {
            seenComunes.add(c.comune);
            results.push({
              id: c.id,
              type: 'comune',
              label: c.comune,
              sublabel: getProvinceName(c.provincia) || 'N/D',
              alias: c.alias || undefined,
              icon: 'comune',
              catName: c.cat_name,
              catColor: c.cat_color
            });
          }
        }
      }

      // Process CATs
      if (data.results.cats && Array.isArray(data.results.cats)) {
        data.results.cats.forEach((cat: any) => {
          results.push({
            id: cat.id,
            type: 'cat',
            label: cat.name,
            icon: 'cat'
          });
        });
      }

      console.log('✅ Search results:', results.length);
      
      // Cache the results for future searches
      searchCache.set(term, results);
      
      // Clear the "from cache" flag since we now have fresh results
      setIsFromCache(false);
      
      return results;
    },
    enabled: debouncedSearchTerm.length >= 2 && !searchCache.get(debouncedSearchTerm.trim()),
    staleTime: 30000, // Cache for 30 seconds
  });

  const handleSelect = useCallback((result: SearchResult) => {
    isSelectingRef.current = true;
    setOpen(false);
    setSearchTerm('');
    setDebouncedSearchTerm('');
    setCachedResults(null);
    
    if (onSelect) {
      onSelect(result);
    }
    
    // Reset flag after selection is complete
    setTimeout(() => {
      isSelectingRef.current = false;
    }, 100);
  }, [onSelect]);

  const handleClear = useCallback(() => {
    setSearchTerm('');
    setDebouncedSearchTerm('');
    setCachedResults(null);
    setOpen(false);
    inputRef.current?.focus();
  }, []);

  const getIcon = (iconType: string) => {
    switch (iconType) {
      case 'comune':
        return <Building2 className="h-4 w-4 text-primary" />;
      case 'quartiere':
        return <MapPin className="h-4 w-4 text-blue-500" />;
      case 'address':
        return <MapPin className="h-4 w-4 text-green-500" />;
      case 'cat':
        return <div className="w-4 h-4 rounded bg-primary/20 flex items-center justify-center text-[10px]">C</div>;
      default:
        return <Search className="h-4 w-4" />;
    }
  };

  const getTypeLabel = (type: string) => {
    switch (type) {
      case 'comune':
        return 'Comune';
      case 'quartiere':
        return 'Quartiere';
      case 'address':
        return 'Indirizzo';
      case 'cat':
        return 'CAT';
      default:
        return '';
    }
  };

  return (
    <div className="relative w-full max-w-2xl">
      <Popover open={open} onOpenChange={setOpen} modal={false}>
        <PopoverTrigger asChild>
          <div className="relative">
            <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground pointer-events-none z-10" />
            {searchTerm.length > 0 && !isLoading && (
              <Button
                variant="ghost"
                size="icon"
                onClick={handleClear}
                className="absolute right-2 top-1/2 h-6 w-6 -translate-y-1/2 z-10 hover:bg-muted/50 transition-all"
                aria-label="Cancella ricerca"
              >
                <X className="h-3 w-3" />
              </Button>
            )}
            {isLoading && debouncedSearchTerm.length >= 2 && (
              <Loader2 className="absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground animate-spin" />
            )}
            <Input
              ref={inputRef}
              placeholder="Cerca Comuni, Quartieri, Indirizzi o CAT..."
              value={searchTerm}
              onChange={(e) => {
                const value = e.target.value.slice(0, 100); // Max 100 characters
                setSearchTerm(value);
                if (value.length >= 2) {
                  setOpen(true);
                }
              }}
              onFocus={() => {
                if (searchTerm.length >= 2) {
                  setOpen(true);
                }
              }}
              onKeyDown={(e) => {
                // Keep popover open while typing
                if (e.key === 'Escape') {
                  setOpen(false);
                  inputRef.current?.blur();
                }
              }}
              className="pl-9 pr-9 h-10 text-sm border-border bg-card transition-all focus:ring-2 focus:ring-primary/20"
              autoComplete="off"
              spellCheck={false}
            />
          </div>
        </PopoverTrigger>
        <PopoverContent 
          className="w-[--radix-popover-trigger-width] p-0 bg-card backdrop-blur-md border-border shadow-lg animate-in fade-in-0 slide-in-from-top-2 duration-200" 
          align="start"
          sideOffset={4}
          onOpenAutoFocus={(e) => {
            // Prevent focus from moving away from input
            e.preventDefault();
          }}
        >
          <Command className="bg-transparent">
            <CommandList className="max-h-[400px]">
              {isLoading && !cachedResults && debouncedSearchTerm.length >= 2 ? (
                <div className="flex items-center justify-center py-6 animate-in fade-in-0 duration-300">
                  <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
                </div>
              ) : debouncedSearchTerm.length < 2 && !cachedResults ? (
                <div className="py-6 text-center text-sm text-muted-foreground animate-in fade-in-0 duration-200">
                  Digita almeno 2 caratteri per cercare
                </div>
              ) : (
                <>
                  <CommandEmpty className="py-6 text-center text-sm text-muted-foreground animate-in fade-in-0 duration-200">
                    Nessun risultato trovato per "{debouncedSearchTerm}"
                  </CommandEmpty>
                  {/* Show API results if available, otherwise show cached results */}
                  {((searchResults && searchResults.length > 0) || (cachedResults && cachedResults.length > 0)) && (
                    <CommandGroup heading={`${(searchResults || cachedResults)?.length || 0} risultati`} className="animate-in fade-in-0 slide-in-from-top-1 duration-300">
                  {(searchResults || cachedResults)?.map((result, index) => (
                    <CommandItem
                      key={`${result.type}-${result.id}`}
                      onSelect={() => handleSelect(result)}
                      className="flex items-center gap-3 cursor-pointer py-3 px-3 hover:bg-muted/50 transition-all animate-in fade-in-0 slide-in-from-left-1 duration-200"
                      style={{ animationDelay: `${index * 30}ms` }}
                    >
                      <div className="flex-shrink-0">
                        {getIcon(result.icon)}
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 flex-wrap">
                          <span className="font-medium text-foreground truncate">
                            {result.label}
                            {result.alias && (
                              <span className="text-muted-foreground font-normal ml-1">
                                - {result.alias}
                              </span>
                            )}
                          </span>
                          <Badge variant="secondary" className="text-[10px] px-1.5 py-0 flex-shrink-0">
                            {getTypeLabel(result.type)}
                          </Badge>
                          {result.catName && result.catColor && (
                            <Badge 
                              variant="outline" 
                              className="text-[10px] px-1.5 py-0 flex-shrink-0"
                              style={{ 
                                borderLeft: `3px solid ${result.catColor}`,
                                borderLeftWidth: '3px'
                              }}
                            >
                              {result.catName}
                            </Badge>
                          )}
                        </div>
                        {result.sublabel && (
                          <div className="text-xs text-muted-foreground truncate mt-0.5">
                            {result.sublabel}
                          </div>
                        )}
                      </div>
                    </CommandItem>
                  ))}
                    </CommandGroup>
                  )}
                </>
              )}
            </CommandList>
          </Command>
        </PopoverContent>
      </Popover>
    </div>
  );
};

export default SearchBar;
