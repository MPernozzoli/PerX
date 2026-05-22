import { useQuery } from '@tanstack/react-query';
import { perxGet } from '@/lib/perxApi';

export interface CommuneDetailsResult {
  commune: any | null;
  catAssociations: any[];
  suspensions: any[];
  parentCommune?: any | null;
  neighborhoods?: any[];
}

async function fetchCommuneDetails(communeId: string): Promise<CommuneDetailsResult> {
  const params = encodeURIComponent(communeId);
  const data = await perxGet<CommuneDetailsResult>(`/cat-dispatcher/communes/${params}`);
  return {
    commune: data.commune ?? null,
    catAssociations: data.catAssociations ?? [],
    suspensions: data.suspensions ?? [],
    parentCommune: data.parentCommune ?? null,
    neighborhoods: data.neighborhoods ?? [],
  };
}

export function useCommuneDetails(communeId: string | null) {
  return useQuery({
    queryKey: ['commune-details', communeId],
    queryFn: () => fetchCommuneDetails(communeId!),
    enabled: !!communeId,
  });
}
