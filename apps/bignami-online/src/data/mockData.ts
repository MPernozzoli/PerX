// Mock data for Bignami Online v1
import { 
  Company, Policy, PolicyEdition, Coverage, Section, CommonLimit, 
  PolicyWithEditions, UserPolicyInteraction 
} from '@/types';

export const mockCompanies: Company[] = [
  {
    id: 'comp-1',
    name: 'Cattolica Assicurazioni',
    code: 'CAT',
    aliases: ['Cattolica', 'Cattolica Ass.', 'Cattolica Assicurazioni S.p.A.']
  },
  {
    id: 'comp-2',  
    name: 'Generali Italia',
    code: 'GEN',
    aliases: ['Generali', 'Assicurazioni Generali', 'Generali Spa']
  },
  {
    id: 'comp-3',
    name: 'Allianz S.p.A.',
    code: 'ALL',
    aliases: ['Allianz', 'Allianz Italia']
  }
];

export const mockPolicies: Policy[] = [
  {
    id: 'pol-1',
    company_id: 'comp-1',
    name: 'Casa&Persona',
    code: 'CP2024X1',
    type: 'domestica',
    description: 'Polizza multirischi per la famiglia e l\'abitazione',
    tags: ['multirischi', 'famiglia', 'abitazione'],
    default_guarantee: 'Fenomeno Elettrico',
    created_at: '2024-01-15T10:00:00Z'
  },
  {
    id: 'pol-2',
    company_id: 'comp-1',
    name: 'Business Protection',
    code: 'BP2024Y2',
    type: 'azienda',
    description: 'Copertura completa per attività commerciali e industriali',
    tags: ['business', 'commerciale', 'industriale'],
    default_guarantee: 'Fenomeno Elettrico',
    created_at: '2024-02-01T09:30:00Z'
  },
  {
    id: 'pol-3',
    company_id: 'comp-2',
    name: 'Casa Sicura',
    code: 'CS2024Z3',
    type: 'domestica',
    description: 'Protezione totale per la tua abitazione',
    tags: ['casa', 'famiglia', 'protezione'],
    default_guarantee: 'Fenomeno Elettrico',
    created_at: '2024-01-20T14:15:00Z'
  }
];

export const mockPolicyEditions: PolicyEdition[] = [
  // Casa&Persona editions
  {
    id: 'ed-1',
    policy_id: 'pol-1',
    year: 2019,
    code: 'ED2019A',
    edition_label: 'Ed. 01/2019',
    pdf_url: '/demo/cattolica-casa-persona-2019.pdf',
    status: 'published',
    canonical_group_id: 'group-1'
  },
  {
    id: 'ed-2', 
    policy_id: 'pol-1',
    year: 2020,
    code: 'ED2020A',
    edition_label: 'Ed. 03/2020',
    pdf_url: '/demo/cattolica-casa-persona-2020.pdf',
    status: 'published',
    canonical_group_id: 'group-1' // Same conditions as 2019
  },
  {
    id: 'ed-3',
    policy_id: 'pol-1', 
    year: 2021,
    code: 'ED2021A',
    edition_label: 'Ed. 02/2021',
    pdf_url: '/demo/cattolica-casa-persona-2021.pdf',
    status: 'published'
  },
  {
    id: 'ed-4',
    policy_id: 'pol-1',
    year: 2023,
    code: 'ED2023A',
    edition_label: 'Ed. 01/2023',
    status: 'draft'
  },
  // Business Protection
  {
    id: 'ed-5',
    policy_id: 'pol-2',
    year: 2022,
    code: 'ED2022A',
    edition_label: 'Ed. 01/2022',
    pdf_url: '/demo/cattolica-business-2022.pdf',
    status: 'published'
  },
  // Generali Casa Sicura
  {
    id: 'ed-6',
    policy_id: 'pol-3',
    year: 2021,
    code: 'ED2021A',
    pdf_url: '/demo/generali-casa-sicura-2021.pdf',
    status: 'published'
  }
];

// Mock data - Dati puliti per il primo avvio
export const mockCoverages: Coverage[] = [];
export const mockSections: Section[] = [];
export const mockCommonLimits: CommonLimit[] = [];

// Helper function to get policies with their editions and companies
export const getPoliciesWithEditions = (): PolicyWithEditions[] => {
  return mockPolicies.map(policy => {
    const editions = mockPolicyEditions.filter(ed => ed.policy_id === policy.id);
    const company = mockCompanies.find(c => c.id === policy.company_id);
    const latestEdition = editions
      .filter(ed => ed.status === 'published')
      .sort((a, b) => b.year - a.year)[0];
    
    return {
      ...policy,
      company,
      editions,
      latestEdition
    };
  });
};

// Mock user interactions for recent/frequent/bookmarked
export const mockUserInteractions: UserPolicyInteraction[] = [
  {
    policy_id: 'pol-1',
    policy_edition_id: 'ed-3',
    last_viewed: '2024-09-13T16:30:00Z',
    view_count: 15,
    bookmarked: true
  },
  {
    policy_id: 'pol-1', 
    policy_edition_id: 'ed-2',
    last_viewed: '2024-09-12T09:15:00Z',
    view_count: 8,
    bookmarked: false
  },
  {
    policy_id: 'pol-3',
    policy_edition_id: 'ed-6',
    last_viewed: '2024-09-10T14:45:00Z',
    view_count: 22,
    bookmarked: true
  },
  {
    policy_id: 'pol-2',
    policy_edition_id: 'ed-5',
    last_viewed: '2024-09-08T11:20:00Z', 
    view_count: 5,
    bookmarked: false
  }
];

// Search functions
export const searchPolicies = (query: string): PolicyWithEditions[] => {
  const allPolicies = getPoliciesWithEditions();
  
  if (!query.trim()) return allPolicies;
  
  const queryLower = query.toLowerCase();
  
  return allPolicies.filter(policy => {
    const matchesCompany = policy.company?.name.toLowerCase().includes(queryLower) ||
      policy.company?.aliases.some(alias => alias.toLowerCase().includes(queryLower));
    
    const matchesPolicy = policy.name.toLowerCase().includes(queryLower);
    
    const matchesYear = policy.editions.some(edition => 
      edition.year.toString().includes(queryLower)
    );
    
    const matchesType = policy.type.toLowerCase().includes(queryLower);
    
    return matchesCompany || matchesPolicy || matchesYear || matchesType;
  });
};

// Get recent, frequent, bookmarked policies
export const getRecentPolicies = (): PolicyWithEditions[] => {
  const recent = mockUserInteractions
    .sort((a, b) => new Date(b.last_viewed).getTime() - new Date(a.last_viewed).getTime())
    .slice(0, 5);
  
  return recent.map(interaction => {
    const policy = getPoliciesWithEditions().find(p => p.id === interaction.policy_id);
    const edition = policy?.editions.find(ed => ed.id === interaction.policy_edition_id);
    return policy ? { ...policy, latestEdition: edition } : null;
  }).filter(Boolean) as PolicyWithEditions[];
};

export const getFrequentPolicies = (): PolicyWithEditions[] => {
  const frequent = mockUserInteractions
    .sort((a, b) => b.view_count - a.view_count)
    .slice(0, 5);
    
  return frequent.map(interaction => {
    const policy = getPoliciesWithEditions().find(p => p.id === interaction.policy_id);
    const edition = policy?.editions.find(ed => ed.id === interaction.policy_edition_id);
    return policy ? { ...policy, latestEdition: edition } : null;
  }).filter(Boolean) as PolicyWithEditions[];
};

export const getBookmarkedPolicies = (): PolicyWithEditions[] => {
  const bookmarked = mockUserInteractions
    .filter(interaction => interaction.bookmarked)
    .sort((a, b) => b.view_count - a.view_count);
    
  return bookmarked.map(interaction => {
    const policy = getPoliciesWithEditions().find(p => p.id === interaction.policy_id);
    const edition = policy?.editions.find(ed => ed.id === interaction.policy_edition_id);
    return policy ? { ...policy, latestEdition: edition } : null;
  }).filter(Boolean) as PolicyWithEditions[];
};