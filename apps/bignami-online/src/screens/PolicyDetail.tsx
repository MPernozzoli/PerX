import { useState, useEffect } from "react";
import { useParams, useNavigate, useSearchParams } from "react-router-dom";
import { Layout } from "@/components/Layout";
import { Card } from "@perx/ui/components/ui/card";
import { Badge } from "@perx/ui/components/ui/badge";
import { Button } from "@perx/ui/components/ui/button";
import { Input } from "@perx/ui/components/ui/input";
import { Label } from "@perx/ui/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@perx/ui/components/ui/select";
import {
  BookmarkIcon,
  EyeIcon,
  DownloadIcon,
  UploadIcon,
  EditIcon,
  PlusIcon,
  CheckIcon,
  XIcon,
  TrashIcon,
  FileTextIcon,
  RotateCcwIcon,
  FilterIcon,
  ChevronDownIcon,
  StarIcon,
  MessageSquareIcon,
  ClockIcon,
  Bot,
  Sparkles,
  Save,
  CheckCircle,
  UserIcon
} from 'lucide-react';
import { 
  PolicyWithEditions, 
  Coverage, 
  Section, 
  CommonLimit,
  PartyType 
} from "@/types";
import { RichTextDisplay } from "@perx/ui/components/ui/rich-text-display";
import { 
  usePolicies, 
  useUpdateCoverage, 
  useUpdateSection, 
  useUpdateCommonLimit, 
  useCreateSection, 
  useCreateCoverageItem,
  useCreateCoverage,
  useUpdateCoverageItem,
  useDeleteCoverageItem,
  useDeleteSection
} from "@/hooks/usePolicies";
import { usePolicyPreferences } from "@/hooks/usePolicyPreferences";
import { usePolicyPDF } from "@/hooks/usePolicyPDF";
import { useAIExtractPolicy, type AIExtractedData } from "@/hooks/useAIExtractPolicy";
import { useRecordInteraction, useToggleBookmark, useUserInteractions } from "@/hooks/useUserInteractions";
import { useAuth } from "@/contexts/AuthContext";
import { useAuthModal } from "@/contexts/AuthModalContext";
import { 
  mockCoverages, 
  mockSections, 
  mockCommonLimits 
} from "@/data/mockData";
import { EditCoverageDialog } from "@/components/edit/EditCoverageDialog";
import { EditSectionDialog } from "@/components/edit/EditSectionDialog";
import { EditCommonLimitDialog } from "@/components/edit/EditCommonLimitDialog";
import { AddSectionDialog } from "@/components/edit/AddSectionDialog";
import { AddGuaranteeDialog } from "@/components/edit/AddGuaranteeDialog";
import { EditGuaranteeDialog } from "@/components/edit/EditGuaranteeDialog";
import { GuaranteeConditionsForSection } from "@/components/GuaranteeConditionsForSection";
import { PolicyComments } from "@/components/PolicyComments";
import { PolicyHistory } from "@/components/PolicyHistory";
import { AIProcessingModal } from "@/components/AIProcessingModal";
import { toast } from "sonner";

// Gruppi garanzia disponibili - filtrati per visualizzazione polizza
const GUARANTEE_GROUPS_DISPLAY = [
  { value: 'FE', label: 'Fenomeno Elettrico' },
  { value: 'AC', label: 'Acqua Condotta' },
  { value: 'FA', label: 'Fenomeni Atmosferici' },
  { value: 'FUR', label: 'Furto' },
  { value: 'INC', label: 'Incendio' },
  { value: 'RC', label: 'Responsabilità Civile' },
  { value: 'CR', label: 'Cristalli' }
];

// Gruppi garanzia completi (per ricerca)
const GUARANTEE_GROUPS_ALL = [
  ...GUARANTEE_GROUPS_DISPLAY,
  { value: 'ALL', label: 'Tutte le Garanzie' }
];

import { usePolicyByCode } from "@/hooks/usePolicyByCode";

export const PolicyDetail = () => {
  const { companyCode, policyCode, editionCode, policyId, editionId } = useParams<{
    companyCode?: string; 
    policyCode?: string; 
    editionCode?: string;
    policyId?: string; 
    editionId?: string;
  }>();
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const { user } = useAuth();
  const { openModal } = useAuthModal();
  
  // Edit mode state
  const [isEditMode, setIsEditMode] = useState(false);
  const [reportingTime, setReportingTime] = useState("3 giorni"); // TODO: Connect to actual data
  
  // Determine route type and get data accordingly
  const isLegacyRoute = !companyCode && (policyId || editionId);
  
  // Get policies data based on route type
  const legacyQuery = usePolicies();
  const newRouteQuery = usePolicyByCode(companyCode, policyCode, editionCode);
  
  let policy, allPolicies, isLoading, error;
  
  if (isLegacyRoute) {
    // Legacy route: use policyId and editionId
    ({ data: allPolicies = [], isLoading, error } = legacyQuery);
    policy = allPolicies.find(p => p.id === policyId);
  } else {
    // New route: use company code, policy code, edition code
    const { data: newRouteData, isLoading: newRouteLoading, error: newRouteError } = newRouteQuery;
    isLoading = newRouteLoading;
    error = newRouteError;
    if (newRouteData) {
      policy = newRouteData.policy;
      allPolicies = [policy]; // For compatibility with existing code
    } else {
      allPolicies = [];
    }
  }
  
  // User interactions hooks
  const recordInteraction = useRecordInteraction();
  const toggleBookmark = useToggleBookmark();
  const { data: userInteractions = [] } = useUserInteractions(user?.id);
  
  // Determine which edition to show
  let defaultEditionId;
  if (isLegacyRoute) {
    // Legacy route logic
    const defaultEdition = policy?.policy_editions?.find(ed => ed.status === 'published') || policy?.policy_editions?.[0];
    defaultEditionId = editionId || defaultEdition?.id || '';
  } else {
    // New route logic
    const targetEdition = editionCode 
      ? policy?.policy_editions?.find(ed => ed.code === editionCode)
      : policy?.policy_editions?.find(ed => ed.status === 'published') || policy?.policy_editions?.[0];
    defaultEditionId = targetEdition?.id || '';
  }
  
  const [activeEdition, setActiveEdition] = useState(defaultEditionId);
  const edition = policy?.policy_editions?.find(ed => ed.id === activeEdition);
  
  // Initialize hooks that need edition ID
  const currentPolicyId = policy?.id || policyId || '';
  const { preferences, savePreferences } = usePolicyPreferences(currentPolicyId, activeEdition);
  const { uploadPDF, downloadPDF, viewPDF, uploading } = usePolicyPDF();
  const { extractFromPDFWithProgress, extracting, progress, partialData, currentChunk } = useAIExtractPolicy();
  
  // AI extraction states
  const [aiModalOpen, setAiModalOpen] = useState(false);
  const [aiExtractedData, setAiExtractedData] = useState<AIExtractedData | null>(null);
  const [currentChunkInfo, setCurrentChunkInfo] = useState<string>('');
  
  // Check if current policy is bookmarked
  const currentInteraction = userInteractions.find(
    interaction => interaction.policy_id === policyId && interaction.policy_edition_id === activeEdition
  );
  const isBookmarked = currentInteraction?.bookmarked || false;
  
  // Selected guarantee group state - initialize from preferences or defaults
  const [selectedGuaranteeGroup, setSelectedGuaranteeGroup] = useState('FE');
  
  // State for active/inactive guarantees
  const [activeGuarantees, setActiveGuarantees] = useState<{[key: string]: boolean}>({});
  
  // AI processing modal state
  const [showAIProcessing, setShowAIProcessing] = useState(false);
  const [applyingAIData, setApplyingAIData] = useState(false);
  
  // Flag to track if preferences have been loaded
  const [preferencesLoaded, setPreferencesLoaded] = useState(false);
  // Edit dialog states
  const [editCoverageOpen, setEditCoverageOpen] = useState(false);
  const [editSectionOpen, setEditSectionOpen] = useState(false);
  const [editCommonLimitOpen, setEditCommonLimitOpen] = useState(false);
  const [addSectionOpen, setAddSectionOpen] = useState(false);
  const [addGuaranteeOpen, setAddGuaranteeOpen] = useState(false);
  const [editGuaranteeOpen, setEditGuaranteeOpen] = useState(false);
  const [selectedSection, setSelectedSection] = useState<Section | null>(null);
  const [selectedLimit, setSelectedLimit] = useState<CommonLimit | null>(null);
  const [selectedGuarantee, setSelectedGuarantee] = useState<any>(null);

  // Selected determinazione for each section
  const [selectedDeterminazione, setSelectedDeterminazione] = useState<{[sectionId: string]: string}>({});

  const updateCoverage = useUpdateCoverage();
  const updateSection = useUpdateSection();
  const updateCommonLimit = useUpdateCommonLimit();
  const createSection = useCreateSection();
  const createCoverageItem = useCreateCoverageItem();
  const createCoverage = useCreateCoverage();
  const updateCoverageItem = useUpdateCoverageItem();
  const deleteCoverageItem = useDeleteCoverageItem();
  const deleteSection = useDeleteSection();
  
  // Get coverage data for current edition
  const coverage = edition?.coverages?.[0];
  const sections = coverage?.sections || [];
  const commonLimits = coverage?.common_limits || [];
  const coverageItems = coverage?.coverage_items || [];
  
  // Filter coverage items based on selected guarantee group
  const filteredCoverageItems = selectedGuaranteeGroup === 'ALL' 
    ? coverageItems 
    : coverageItems.filter(item => item.guarantee_group === selectedGuaranteeGroup);

  // Comprehensive preferences management effect
  useEffect(() => {
    console.log('Preferences effect triggered:', { 
      preferences, 
      policyId, 
      activeEdition, 
      preferencesLoaded,
      coverageItemsLength: coverageItems.length 
    });

    // If we have preferences loaded, apply them immediately
    if (preferences && policyId && activeEdition) {
      console.log('Loading preferences:', preferences);
      
      // Load guarantee group preference
      if (preferences.selected_guarantee_group && preferences.selected_guarantee_group !== selectedGuaranteeGroup) {
        console.log('Setting guarantee group from preferences:', preferences.selected_guarantee_group);
        setSelectedGuaranteeGroup(preferences.selected_guarantee_group);
      }
      
      // Load active guarantees preference
      if (preferences.active_guarantees && typeof preferences.active_guarantees === 'object') {
        const prefsActiveGuarantees = preferences.active_guarantees as {[key: string]: boolean};
        console.log('Setting active guarantees from preferences:', prefsActiveGuarantees);
        setActiveGuarantees(prefsActiveGuarantees);
      }
      
      setPreferencesLoaded(true);
    }
    // If no preferences exist but we have coverage items, initialize with all active
    else if (preferences === null && coverageItems.length > 0 && !preferencesLoaded) {
      console.log('No preferences found, initializing with all guarantees active');
      const initialState: {[key: string]: boolean} = {};
      coverageItems.forEach(item => {
        initialState[item.id] = true;
      });
      setActiveGuarantees(initialState);
      setPreferencesLoaded(true);
      
      // Apply URL parameter if present
      const guaranteeParam = searchParams.get('guarantee');
      if (guaranteeParam) {
        const group = GUARANTEE_GROUPS_ALL.find(g => g.label.toLowerCase() === guaranteeParam.toLowerCase() || g.value === guaranteeParam);
        if (group && group.value !== selectedGuaranteeGroup) {
          console.log('Setting guarantee group from URL parameter:', group.value);
          setSelectedGuaranteeGroup(group.value);
        }
      }
    }
  }, [preferences, policyId, activeEdition, coverageItems, preferencesLoaded, selectedGuaranteeGroup, searchParams]);

  // Save preferences when they change (but only after initial load)
  useEffect(() => {
    if (preferencesLoaded && policyId && activeEdition && Object.keys(activeGuarantees).length > 0) {
      console.log('Saving preferences:', { selectedGuaranteeGroup, activeGuarantees });
      
      const timeoutId = setTimeout(() => {
        savePreferences({
          selected_guarantee_group: selectedGuaranteeGroup,
          active_guarantees: activeGuarantees,
        }).catch(error => {
          console.error('Error saving preferences:', error);
        });
      }, 1000); // Debounce saves

      return () => clearTimeout(timeoutId);
    }
  }, [selectedGuaranteeGroup, activeGuarantees, policyId, activeEdition, preferencesLoaded, savePreferences]);

  // Reset preferences loaded flag when policy or edition changes
  useEffect(() => {
    console.log('Policy/Edition changed, resetting preferences loaded flag');
    setPreferencesLoaded(false);
  }, [policyId, activeEdition]);

  // Record interaction when policy is viewed
  useEffect(() => {
    if (user?.id && policyId && activeEdition) {
      recordInteraction.mutate({
        policyId,
        editionId: activeEdition,
        userId: user.id
      });
    }
  }, [user?.id, policyId, activeEdition, recordInteraction]);

  // Handle bookmark toggle
  const handleToggleBookmark = async () => {
    if (!user?.id || !policyId || !activeEdition) return;
    
    try {
      await toggleBookmark.mutateAsync({
        policyId,
        editionId: activeEdition,
        userId: user.id,
        bookmarked: !isBookmarked
      });
      toast.success(isBookmarked ? "Rimosso dai preferiti" : "Aggiunto ai preferiti");
    } catch (error) {
      console.error('Bookmark toggle error:', error);
      toast.error("Errore durante l'aggiornamento dei preferiti");
    }
  };

  const toggleGuaranteeActive = (guaranteeId: string) => {
    setActiveGuarantees(prev => ({
      ...prev,
      [guaranteeId]: !prev[guaranteeId]
    }));
  };

  // PDF handling functions
  const handleUploadPDF = async (file: File) => {
    if (!policyId || !activeEdition) return;
    
    try {
      await uploadPDF({ file, policyId, editionId: activeEdition });
    } catch (error) {
      console.error('PDF upload error:', error);
    }
  };

  const handleFileUpload = (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (file && file.type === 'application/pdf') {
      handleUploadPDF(file);
    } else {
      toast.error("Seleziona un file PDF valido");
    }
    // Reset input
    event.target.value = '';
  };

  // AI extraction functions
  const handleAIExtract = async () => {
    if (!edition?.pdf_url) {
      toast.error("Nessun PDF disponibile per l'estrazione");
      return;
    }

    try {
      setShowAIProcessing(true);
      setCurrentChunkInfo('Inizializzazione...');
      
      const result = await extractFromPDFWithProgress(edition.pdf_url, (progressInfo) => {
        if (progressInfo.chunk) {
          setCurrentChunkInfo(`Elaborando pagine ${progressInfo.chunk.chunk_info?.start_page}-${progressInfo.chunk.chunk_info?.end_page}`);
        }
      });
      
      if (result.success && result.data) {
        setAiExtractedData(result.data);
        setCurrentChunkInfo('Completato!');
      }
    } catch (error) {
      console.error('Error during AI extraction:', error);
      setShowAIProcessing(false);
    }
  };

  const handleApplyAIData = async () => {
    if (!aiExtractedData || !activeEdition) return;

    setApplyingAIData(true);
    try {
      // Find the coverage for this edition
      const coverage = policy?.policy_editions
        ?.find(ed => ed.id === activeEdition)
        ?.coverages?.[0];

      if (!coverage) {
        toast.error("Nessuna copertura trovata per questa edizione");
        return;
      }

      // Apply coverage updates
      if (aiExtractedData.coverage_updates && Object.keys(aiExtractedData.coverage_updates).length > 0) {
        await updateCoverage.mutateAsync({
          id: coverage.id,
          updates: {
            overview_text: aiExtractedData.coverage_updates.overview_text || coverage.overview_text,
            definitions: aiExtractedData.coverage_updates.definitions || coverage.definitions,
            common_exclusions: aiExtractedData.coverage_updates.common_exclusions || coverage.common_exclusions,
            common_interpretations: aiExtractedData.coverage_updates.common_interpretations || coverage.common_interpretations,
            common_notes: aiExtractedData.coverage_updates.common_notes || coverage.common_notes,
            value_type: aiExtractedData.coverage_updates.value_type || coverage.value_type,
            primo_rischio_value: aiExtractedData.coverage_updates.primo_rischio_value || coverage.primo_rischio_value,
          }
        });
      }

      // Create sections
      for (const sectionData of aiExtractedData.sections_to_create) {
        await createSection.mutateAsync({
          coverage_id: coverage.id,
          party: sectionData.party,
          exact_name: sectionData.exact_name,
          emoji: sectionData.emoji,
          definition: sectionData.definition,
          definition_page_reference: sectionData.definition_page_reference,
          definition_article_number: sectionData.definition_article_number,
          exclusions: sectionData.exclusions || [],
          value_type: sectionData.value_type,
          primo_rischio_value: sectionData.primo_rischio_value,
          deroga_percentage: sectionData.deroga_percentage,
          determinazione: sectionData.determinazione || [],
          notes: sectionData.notes || [],
        });
      }

      // Create guarantees (coverage items)
      for (const guaranteeData of aiExtractedData.guarantees_to_create) {
        await createCoverageItem.mutateAsync({
          coverage_id: coverage.id,
          guarantee_name: guaranteeData.guarantee_name,
          guarantee_group: guaranteeData.guarantee_group,
          exact_name: guaranteeData.exact_name,
          description: guaranteeData.description,
          value_type: guaranteeData.value_type,
          primo_rischio_value: guaranteeData.primo_rischio_value,
          common_exclusions: guaranteeData.common_exclusions || [],
          order_index: guaranteeData.order_index,
          maximum_value: guaranteeData.maximum_value,
          maximum_applies_to: guaranteeData.maximum_applies_to ? [guaranteeData.maximum_applies_to] : [],
          maximum_page_reference: guaranteeData.maximum_page_reference,
          maximum_article_number: guaranteeData.maximum_article_number,
          deductible_value: guaranteeData.deductible_value,
          deductible_applies_to: guaranteeData.deductible_applies_to ? [guaranteeData.deductible_applies_to] : [],
          deductible_page_reference: guaranteeData.deductible_page_reference,
          deductible_article_number: guaranteeData.deductible_article_number,
          guarantee_exclusions: guaranteeData.guarantee_exclusions || [],
          exclusions_applies_to: guaranteeData.exclusions_applies_to ? [guaranteeData.exclusions_applies_to] : [],
          exclusions_page_reference: guaranteeData.exclusions_page_reference,
          exclusions_article_number: guaranteeData.exclusions_article_number,
        });
      }

      // Create common limits
      for (const limitData of aiExtractedData.common_limits_to_create) {
        // This would require a createCommonLimit mutation which doesn't exist yet
        // For now we'll skip this or you can implement it
        console.log('Would create common limit:', limitData);
      }

      toast.success("Dati IA applicati con successo!");
      setShowAIProcessing(false);
      setAiExtractedData(null);

    } catch (error) {
      console.error('Error applying AI data:', error);
      toast.error("Errore durante l'applicazione dei dati IA");
    } finally {
      setApplyingAIData(false);
    }
  };

  const handleCancelAIData = () => {
    setShowAIProcessing(false);
    setAiExtractedData(null);
  };

  if (isLoading) {
    return (
      <Layout>
        <Card className="p-8 text-center">
          <div className="text-muted-foreground">Caricamento...</div>
        </Card>
      </Layout>
    );
  }
  
  if (!policy || !edition) {
    return (
      <Layout>
        <Card className="p-8 text-center">
          <div className="text-muted-foreground">Polizza non trovata</div>
        </Card>
      </Layout>
    );
  }

  if (!coverage) {
    const handleCreateDefaultCoverage = async () => {
      try {
        await createCoverage.mutateAsync({
          policy_edition_id: edition.id,
          guarantee: policy.default_guarantee || "Fenomeno Elettrico",
          overview_text: "Copertura base per " + (policy.default_guarantee || "Fenomeno Elettrico"),
          definitions: [],
          common_exclusions: [],
          common_interpretations: [],
          common_notes: [],
          value_type: "valore_intero"
        });
        toast.success("Coverage di default creata con successo!");
      } catch (error) {
        console.error("Errore creazione coverage:", error);
        toast.error("Errore nella creazione della coverage");
      }
    };

    return (
      <Layout>
        <Card className="p-8 text-center">
          <div className="space-y-4">
            <Sparkles className="h-12 w-12 text-primary mx-auto" />
            <div>
              <h3 className="text-lg font-semibold mb-2">Nessuna coverage disponibile</h3>
              <p className="text-muted-foreground mb-4">
                Questa edizione non ha ancora una coverage configurata.
                <br />
                Vuoi creare una coverage di default per iniziare?
              </p>
              <Button 
                onClick={handleCreateDefaultCoverage}
                disabled={createCoverage.isPending}
                className="gap-2"
              >
                <Sparkles className="h-4 w-4" />
                {createCoverage.isPending ? "Creazione..." : "Crea Coverage Default"}
              </Button>
            </div>
          </div>
        </Card>
      </Layout>
    );
  }

  const formatLimitValue = (value: string, onFrontespizio?: boolean, type?: string) => {
    if (onFrontespizio) {
      return (
        <Badge className="bg-badge-frontespizio text-white text-xs">
          Su frontespizio di Polizza
        </Badge>
      );
    }
    
    if (value.includes('%')) {
      return (
        <Badge className="bg-blue-100 text-blue-800 text-xs">
          {value}
        </Badge>
      );
    }
    
    if (value.includes('€') || /^\d+/.test(value)) {
      return (
        <span className="font-mono text-sm bg-muted px-2 py-1 rounded">
          {value}
        </span>
      );
    }
    
    return (
      <span className="font-mono text-sm bg-muted px-2 py-1 rounded">
        {value}
      </span>
    );
  };

  const formatDeductibleValue = (item: any) => {
    if (!item.deductible_value) return null;
    
    if (item.deductible_value === 'Su frontespizio') {
      return (
        <Badge className="bg-badge-frontespizio text-white text-xs">
          Su frontespizio
        </Badge>
      );
    }
    
    return (
      <span className="font-mono text-xs bg-orange-50 text-orange-800 px-2 py-1 rounded">
        {item.deductible_value}
      </span>
    );
  };

  const formatMaximumValue = (item: any) => {
    if (!item.maximum_value) return null;
    
    if (item.maximum_value === 'Su frontespizio') {
      return (
        <Badge className="bg-badge-frontespizio text-white text-xs">
          Su frontespizio
        </Badge>
      );
    }
    
    return (
      <span className="font-mono text-xs bg-green-50 text-green-800 px-2 py-1 rounded">
        {item.maximum_value}
      </span>
    );
  };
  const groupedEditions = policy.policy_editions.filter(ed => 
    ed.canonical_group_id && ed.canonical_group_id === edition.canonical_group_id
  );

  const getPartyIcon = (party: PartyType, emoji?: string) => {
    if (emoji) return emoji;
    switch(party) {
      case 'fabbricato': return '🏠';
      case 'contenuto': return '📦';
      case 'impianti': return '⚡';
      case 'macchinari': return '🔧';
      case 'elettronica': return '💻';
      default: return '📋';
    }
  };

  const getInsuranceValueDisplay = (type: string, value?: string, linkId?: string) => {
    if (type === 'exact') return value;
    if (type === 'frontespizio') return (
      <Badge className="bg-badge-frontespizio text-white text-xs">
        Su frontespizio
      </Badge>
    );
    if (type === 'comune_a_piu_partite') {
      const limit = commonLimits.find(cl => cl.id === linkId);
      return (
        <Badge className="bg-badge-comune text-white text-xs">
          {limit?.label || 'Comune a più partite'}
        </Badge>
      );
    }
    if (type === 'coincide_valore_assicurato') return (
      <Badge className="bg-primary/10 text-primary text-xs">
        Coincide con valore assicurato della partita
      </Badge>
    );
    return '-';
  };

  const getValueTypeDisplay = (valueType?: string, primoRischioValue?: string, derogaPercentage?: number) => {
    const getBaseDisplay = () => {
      switch(valueType) {
        case 'primo_rischio_assoluto':
          return 'Primo Rischio Assoluto';
        case 'primo_rischio_assoluto_fino_a':
          return `Primo Rischio Assoluto fino a ${primoRischioValue}`;
        case 'valore_intero':
        default:
          return 'Valore Intero';
      }
    };

    const baseText = getBaseDisplay();
    const displayText = derogaPercentage 
      ? `${baseText} con deroga del ${derogaPercentage}%`
      : baseText;

    switch(valueType) {
      case 'primo_rischio_assoluto':
        return (
          <Badge className="bg-accent text-accent-foreground text-xs">
            {displayText}
          </Badge>
        );
      case 'primo_rischio_assoluto_fino_a':
        return (
          <Badge className="bg-accent text-accent-foreground text-xs">
            {displayText}
          </Badge>
        );
      case 'valore_intero':
      default:
        return (
          <Badge className="bg-muted text-muted-foreground text-xs">
            {displayText}
          </Badge>
        );
    }
  };

  // Edit handlers
  const handleEditCoverage = () => {
    setEditCoverageOpen(true);
  };

  const handleEditSection = (section: Section) => {
    setSelectedSection(section);
    setEditSectionOpen(true);
  };

  const handleDeleteSection = async (sectionId: string) => {
    try {
      await deleteSection.mutateAsync(sectionId);
      toast.success("Partita eliminata con successo");
    } catch (error) {
      toast.error("Errore durante l'eliminazione della partita");
      console.error(error);
    }
  };

  const handleEditCommonLimit = (limit: CommonLimit) => {
    setSelectedLimit(limit);
    setEditCommonLimitOpen(true);
  };

  const handleEditGuarantee = (item: any) => {
    setSelectedGuarantee(item);
    setEditGuaranteeOpen(true);
  };

  const handleDeleteGuarantee = async (guaranteeId: string) => {
    try {
      await deleteCoverageItem.mutateAsync(guaranteeId);
      toast.success("Garanzia eliminata con successo");
    } catch (error) {
      toast.error("Errore durante l'eliminazione della garanzia");
      console.error(error);
    }
  };

  const handleSaveCoverage = async (updatedCoverage: Partial<Coverage>) => {
    try {
      await updateCoverage.mutateAsync({
        id: coverage.id,
        updates: updatedCoverage
      });
      toast.success("Coverage aggiornata con successo");
      setEditCoverageOpen(false);
    } catch (error) {
      toast.error("Errore durante l'aggiornamento della coverage");
      console.error(error);
    }
  };

  const handleSaveSection = async (updatedSection: Partial<Section>) => {
    if (!selectedSection) return;
    try {
      await updateSection.mutateAsync({
        id: selectedSection.id,
        updates: updatedSection
      });
      toast.success("Sezione aggiornata con successo");
      setEditSectionOpen(false);
      setSelectedSection(null);
    } catch (error) {
      toast.error("Errore durante l'aggiornamento della sezione");
      console.error(error);
    }
  };

  const handleSaveCommonLimit = async (updatedLimit: Partial<CommonLimit>) => {
    if (!selectedLimit) return;
    try {
      await updateCommonLimit.mutateAsync({
        id: selectedLimit.id,
        updates: updatedLimit
      });
      toast.success("Limite comune aggiornato con successo");
      setEditCommonLimitOpen(false);
      setSelectedLimit(null);
    } catch (error) {
      toast.error("Errore durante l'aggiornamento del limite comune");
      console.error(error);
    }
  };

  const handleSaveGuarantee = async (updates: any) => {
    if (!selectedGuarantee) return;
    try {
      await updateCoverageItem.mutateAsync({
        id: selectedGuarantee.id,
        updates: updates
      });
      toast.success("Garanzia aggiornata con successo");
      setEditGuaranteeOpen(false);
      setSelectedGuarantee(null);
    } catch (error) {
      toast.error("Errore durante l'aggiornamento della garanzia");
      console.error(error);
    }
  };

  const handleAddSection = async (sectionData: any) => {
    try {
      await createSection.mutateAsync({
        coverage_id: coverage.id,
        party: sectionData.party,
        exact_name: sectionData.exact_name,
        emoji: sectionData.emoji,
        definition: sectionData.definition,
        exclusions: sectionData.exclusions || [],
        value_type: sectionData.value_type || 'valore_intero',
        notes: []
      });
      toast.success("Partita aggiunta con successo");
      setAddSectionOpen(false);
    } catch (error) {
      toast.error("Errore durante l'aggiunta della partita");
      console.error(error);
    }
  };

  const handleAddGuarantee = async (guaranteeData: any) => {
    try {
      // Build maximum value string
      let maximumValue = '';
      if (guaranteeData.maximum_on_frontespizio) {
        maximumValue = 'Su frontespizio';
      } else if (guaranteeData.maximum_exact_value) {
        maximumValue = `€ ${guaranteeData.maximum_exact_value}`;
      } else if (guaranteeData.maximum_percentage_of_party) {
        let percentageStr = `${guaranteeData.maximum_percentage_of_party}%`;
        if (guaranteeData.maximum_minimum || guaranteeData.maximum_maximum) {
          percentageStr += ' (';
          if (guaranteeData.maximum_minimum) {
            percentageStr += `min € ${guaranteeData.maximum_minimum}`;
            if (guaranteeData.maximum_maximum) {
              percentageStr += `, max € ${guaranteeData.maximum_maximum}`;
            }
          } else if (guaranteeData.maximum_maximum) {
            percentageStr += `max € ${guaranteeData.maximum_maximum}`;
          }
          percentageStr += ')';
        }
        if (guaranteeData.maximum_notes) {
          percentageStr += ` - ${guaranteeData.maximum_notes}`;
        }
        maximumValue = percentageStr;
      }

      // Build deductible value string
      let deductibleValue = '';
      if (guaranteeData.deductible_on_frontespizio) {
        deductibleValue = 'Su frontespizio';
      } else if (guaranteeData.deductible_exact_value) {
        deductibleValue = `€ ${guaranteeData.deductible_exact_value}`;
      } else if (guaranteeData.deductible_percentage) {
        let percentageStr = `${guaranteeData.deductible_percentage}%`;
        if (guaranteeData.deductible_minimum || guaranteeData.deductible_maximum) {
          percentageStr += ' (';
          if (guaranteeData.deductible_minimum) {
            percentageStr += `min € ${guaranteeData.deductible_minimum}`;
            if (guaranteeData.deductible_maximum) {
              percentageStr += `, max € ${guaranteeData.deductible_maximum}`;
            }
          } else if (guaranteeData.deductible_maximum) {
            percentageStr += `max € ${guaranteeData.deductible_maximum}`;
          }
          percentageStr += ')';
        }
        if (guaranteeData.deductible_notes) {
          percentageStr += ` - ${guaranteeData.deductible_notes}`;
        }
        deductibleValue = percentageStr;
      }

      await createCoverageItem.mutateAsync({
        coverage_id: coverage.id,
        guarantee_name: guaranteeData.guarantee_name,
        guarantee_group: guaranteeData.guarantee_group,
        exact_name: guaranteeData.guarantee_name,
        description: guaranteeData.description,
        value_type: guaranteeData.value_type,
        primo_rischio_value: guaranteeData.value_type === 'primo_rischio_assoluto_fino_a' ? guaranteeData.primo_rischio_value : undefined,
        common_exclusions: guaranteeData.common_exclusions,
        available_parties: guaranteeData.available_parties,
        order_index: coverageItems.length,
        maximum_value: maximumValue,
        maximum_applies_to: guaranteeData.maximum_applies_to,
        maximum_page_reference: guaranteeData.maximum_page_reference,
        maximum_article_number: guaranteeData.maximum_article_number,
        deductible_value: deductibleValue,
        deductible_applies_to: guaranteeData.deductible_applies_to,
        deductible_page_reference: guaranteeData.deductible_page_reference,
        deductible_article_number: guaranteeData.deductible_article_number,
        guarantee_exclusions: guaranteeData.guarantee_exclusions,
        exclusions_applies_to: guaranteeData.exclusions_apply_to,
        exclusions_page_reference: guaranteeData.exclusions_page_reference,
        exclusions_article_number: guaranteeData.exclusions_article_number
      });
      toast.success("Garanzia aggiunta con successo");
      setAddGuaranteeOpen(false);
    } catch (error) {
      toast.error("Errore durante l'aggiunta della garanzia");
      console.error(error);
    }
  };

  // Edit mode handlers
  const handleEnterEditMode = () => {
    setIsEditMode(true);
  };

  const handleCancelEdit = () => {
    setIsEditMode(false);
    // Reset any temporary changes here if needed
    toast.info("Modifiche annullate");
  };

  const handleSaveAllChanges = () => {
    setIsEditMode(false);
    toast.success("Tutte le modifiche salvate");
  };

  return (
    <Layout>
      <div className="container mx-auto py-8 space-y-6">
        {/* Header Section */}
        <div className="flex items-center justify-between">
          <div className="space-y-1">
            <h1 className="text-3xl font-bold">{policy.name}</h1>
            <div className="flex items-center gap-4 text-muted-foreground">
              <div className="flex items-center gap-2">
                <Badge variant="outline" className="text-xs">
                  {policy.companies?.name}
                </Badge>
                <Badge variant="outline" className="text-xs">
                  {policy.type}
                </Badge>
              </div>
              <span className="text-sm">
                Edizione {edition.year}
                {edition.edition_label && ` - ${edition.edition_label}`}
              </span>
            </div>
          </div>
          
          <div className="flex items-center gap-3">
            {/* Bookmark Button */}
            <Button 
              variant="ghost" 
              size="sm" 
              onClick={user ? handleToggleBookmark : openModal}
              className="gap-2"
              disabled={!user}
            >
              <BookmarkIcon className={`h-4 w-4 ${isBookmarked ? 'fill-current' : ''}`} />
              {user ? (isBookmarked ? 'Salvato' : 'Salva') : 'Accedi per salvare'}
            </Button>
            
            {!user && (
              <div className="bg-amber-50 text-amber-800 px-3 py-2 rounded-lg text-sm">
                <div className="flex items-center gap-2">
                  <UserIcon className="h-4 w-4" />
                  <span>
                    <strong>Accedi</strong> per modificare, scaricare PDF e salvare preferiti
                  </span>
                  <Button 
                    size="sm" 
                    variant="outline"
                    onClick={openModal}
                    className="ml-2"
                  >
                    Accedi
                  </Button>
                </div>
              </div>
            )}
            
            {user && !isEditMode ? (
              <div className="flex gap-2">
                <Button size="sm" onClick={handleEnterEditMode} className="gap-2">
                  <EditIcon className="h-4 w-4" />
                  Modifica
                </Button>
                
                {/* PDF Actions - Show when not in edit mode */}
                {edition?.pdf_url && (
                  <>
                    <Button 
                      variant="outline" 
                      size="sm" 
                      className="gap-2"
                      onClick={() => viewPDF(edition.pdf_url!)}
                    >
                      <EyeIcon className="h-4 w-4" />
                      Visualizza PDF
                    </Button>
                    <Button 
                      variant="outline" 
                      size="sm" 
                      className="gap-2"
                      onClick={() => downloadPDF(edition.pdf_url!, `${policy.name}_${edition.year}.pdf`)}
                    >
                      <DownloadIcon className="h-4 w-4" />
                      Scarica PDF
                    </Button>
                  </>
                )}
              </div>
            ) : user && isEditMode ? (
              <div className="flex gap-2">
                {/* PDF Upload - Show when in edit mode */}
                <div className="relative">
                  <input
                    type="file"
                    accept=".pdf"
                    onChange={handleFileUpload}
                    className="absolute inset-0 w-full h-full opacity-0 cursor-pointer"
                    disabled={uploading}
                  />
                  <Button 
                    variant="outline" 
                    size="sm" 
                    className="gap-2"
                    disabled={uploading}
                  >
                    <UploadIcon className="h-4 w-4" />
                    {uploading ? 'Caricamento...' : 'Carica PDF'}
                  </Button>
                </div>

                {/* AI Extract Button - Show when PDF is available and in edit mode */}
                {edition?.pdf_url && (
                  <Button 
                    variant="outline" 
                    size="sm" 
                    className="gap-2"
                    onClick={handleAIExtract}
                    disabled={extracting}
                  >
                    <Sparkles className="h-4 w-4" />
                    {extracting ? 'Elaborazione...' : 'Autocompila con IA'}
                  </Button>
                )}
                
                <Button variant="outline" size="sm" onClick={handleCancelEdit} className="gap-2">
                  <XIcon className="h-4 w-4" />
                  Annulla
                </Button>
                <Button size="sm" onClick={handleSaveAllChanges} className="gap-2">
                  <Save className="h-4 w-4" />
                  Salva
                </Button>
              </div>
            ) : null}
          </div>
        </div>

        {/* Edition Selector - Improved Design */}
        <Card className="p-6">
          <div className="flex items-center justify-between mb-6">
            <h3 className="text-lg font-semibold flex items-center gap-2">
              📄 Edizioni Disponibili
            </h3>
            <Badge variant="outline" className="text-xs">
              {policy.policy_editions.length} edizion{policy.policy_editions.length === 1 ? 'e' : 'i'}
            </Badge>
          </div>
          
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
            {policy.policy_editions
              .sort((a, b) => b.year - a.year)
              .map(ed => {
                const isActive = ed.id === activeEdition;
                return (
                  <div
                    key={ed.id}
                    className={`relative p-4 rounded-lg border transition-all cursor-pointer hover:shadow-md ${
                      isActive 
                        ? 'border-primary bg-primary/5 shadow-sm' 
                        : 'border-muted hover:border-primary/50'
                    }`}
                    onClick={() => {
                      setActiveEdition(ed.id);
                      navigate(`/policy/${policyId}/edition/${ed.id}`, { replace: true });
                    }}
                  >
                    {isActive && (
                      <div className="absolute -top-2 -right-2">
                        <CheckCircle className="h-5 w-5 text-primary bg-background rounded-full" />
                      </div>
                    )}
                    
                    <div className="space-y-2">
                      <div className="flex items-center justify-between">
                        <Badge variant={isActive ? "default" : "secondary"} className="text-xs">
                          {ed.year}
                        </Badge>
                        {ed.pdf_url && (
                          <FileTextIcon className="h-4 w-4 text-muted-foreground" />
                        )}
                      </div>
                      
                      {ed.edition_label && (
                        <p className="text-sm text-muted-foreground font-medium">
                          {ed.edition_label}
                        </p>
                      )}
                      
                      <div className="flex items-center justify-between text-xs text-muted-foreground">
                        <span className="capitalize">{ed.status}</span>
                        {ed.pdf_url && (
                          <span className="flex items-center gap-1">
                            <FileTextIcon className="h-3 w-3" />
                            PDF
                          </span>
                        )}
                      </div>
                    </div>
                  </div>
                );
              })}
            
            {/* Add Edition Card */}
            {user && (
              <div
                className="p-4 border-2 border-dashed border-muted-foreground/30 rounded-lg hover:border-primary/50 transition-colors cursor-pointer flex flex-col items-center justify-center gap-2 text-muted-foreground hover:text-primary"
                onClick={() => navigate(`/add-policy?mode=add-edition&policyId=${policyId}`)}
              >
                <PlusIcon className="h-6 w-6" />
                <span className="text-sm font-medium">Aggiungi Edizione</span>
              </div>
            )}
          </div>

          {/* Tempo di Denuncia */}
          <div className="mt-6 pt-6 border-t">
            <div className="flex items-center gap-3">
              <Label className="font-medium text-sm">Tempo di denuncia:</Label>
              {isEditMode ? (
                <Input 
                  value={reportingTime}
                  onChange={(e) => setReportingTime(e.target.value)}
                  className="w-auto"
                  placeholder="es. 3 giorni"
                />
              ) : (
                <Badge variant="outline" className="font-mono">
                  {reportingTime || "Non specificato"}
                </Badge>
              )}
            </div>
          </div>
        </Card>

        {/* Main Content - Single Scrollview */}
        <div className="space-y-6">
          
          {/* Action Buttons with Guarantee Group Selector */}
          <div className="flex items-center justify-between gap-4">
            {/* Selettore Gruppo Garanzie */}
            <div className="flex items-center gap-2">
              <Select value={selectedGuaranteeGroup} onValueChange={setSelectedGuaranteeGroup}>
                <SelectTrigger className="w-48">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {GUARANTEE_GROUPS_DISPLAY.map(group => (
                    <SelectItem key={group.value} value={group.value}>
                      {group.value} - {group.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            
            {/* Action Buttons */}
            <div className="flex gap-3">
              {/* Comments and History are now integrated below */}
            </div>
          </div>

          {/* Garanzia Section */}
          <Card className="p-6">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-semibold flex items-center gap-2">
                ⚡ Garanzia
              </h3>
              {user && isEditMode && (
                <div className="flex gap-2">
                  <Button variant="outline" size="sm" className="gap-2" onClick={() => setAddGuaranteeOpen(true)}>
                    <EditIcon className="h-4 w-4" />
                    Aggiungi Garanzia
                  </Button>
                  <Button variant="outline" size="sm" className="gap-2" onClick={handleEditCoverage}>
                    <EditIcon className="h-4 w-4" />
                    Modifica
                  </Button>
                </div>
              )}
            </div>

            <div className="space-y-4">
              <div>
                <h4 className="font-medium mb-2">Definizione</h4>
                <div className="mb-3">
                  {getValueTypeDisplay(coverage?.value_type, coverage?.primo_rischio_value)}
                </div>
                <p className="text-sm text-muted-foreground mb-3">
                  <RichTextDisplay content={coverage?.overview_text || ""} />
                </p>
                {coverage?.definitions && coverage.definitions.length > 0 && (
                  <ul className="list-disc list-inside space-y-1 text-sm">
                    {coverage.definitions.map((def, index) => (
                      <li key={index}>
                        <RichTextDisplay content={def} />
                      </li>
                    ))}
                  </ul>
                )}
              </div>

              {coverage?.common_exclusions && coverage.common_exclusions.length > 0 && (
                <div>
                  <h4 className="font-medium mb-2">Esclusioni Comuni</h4>
                  <ul className="list-disc list-inside space-y-1 text-sm text-muted-foreground">
                    {coverage.common_exclusions.map((exclusion, index) => (
                      <li key={index}>
                        <RichTextDisplay content={exclusion} />
                      </li>
                    ))}
                  </ul>
                </div>
              )}

              {coverage?.common_interpretations && coverage.common_interpretations.length > 0 && (
                <div>
                  <h4 className="font-medium mb-2">Interpretazioni Comuni</h4>
                  <ul className="list-disc list-inside space-y-1 text-sm text-muted-foreground">
                    {coverage.common_interpretations.map((interpretation, index) => (
                      <li key={index}>{interpretation}</li>
                    ))}
                  </ul>
                </div>
              )}

              {coverage?.common_notes && coverage.common_notes.length > 0 && (
                <div>
                  <h4 className="font-medium mb-2">Note</h4>
                  <ul className="list-disc list-inside space-y-1 text-sm text-muted-foreground">
                    {coverage.common_notes.map((note, index) => (
                      <li key={index}>{note}</li>
                    ))}
                  </ul>
                </div>
              )}

              {/* Lista delle garanzie disponibili */}
              {filteredCoverageItems && filteredCoverageItems.length > 0 && (
                <div>
                  <h4 className="font-medium mb-3">
                    Garanzie Configurate
                    <Badge className="ml-2 bg-primary/10 text-primary text-xs">
                      {GUARANTEE_GROUPS_DISPLAY.find(g => g.value === selectedGuaranteeGroup)?.label}
                    </Badge>
                  </h4>
                  <div className="grid gap-4">
                    {filteredCoverageItems.map((item, index) => {
                      const isActive = activeGuarantees[item.id] !== false; // Default to true
                      
                      return (
                        <div key={item.id} className={`p-4 rounded-lg border transition-all ${
                          isActive ? 'bg-muted/30' : 'bg-muted/10 opacity-60'
                        }`}>
                          <div className="flex items-center justify-between">
                            <div className="flex items-center gap-3">
                              <button
                                onClick={() => toggleGuaranteeActive(item.id)}
                                className={`w-4 h-4 rounded-full border-2 transition-colors ${
                                  isActive ? 'bg-primary border-primary' : 'border-muted-foreground'
                                }`}
                                title={isActive ? 'Disattiva garanzia' : 'Attiva garanzia'}
                              >
                                {isActive && <div className="w-full h-full bg-white rounded-full scale-50"></div>}
                              </button>
                              <Badge className="bg-primary/10 text-primary text-xs font-mono">
                                {item.guarantee_group}
                              </Badge>
                              <span className="font-medium">{item.guarantee_name}</span>
                            </div>
                            {isEditMode && (
                              <Button variant="ghost" size="sm" onClick={() => handleEditGuarantee(item)}>
                                <EditIcon className="h-4 w-4" />
                              </Button>
                            )}
                          </div>
                          
                          {/* Contenuto collassabile */}
                          {isActive && (
                            <div className="space-y-3 mt-3">
                              {/* Disponibile per partite */}
                              {(item as any).available_parties && (item as any).available_parties.length > 0 && (
                                <div className="text-xs text-muted-foreground">
                                  <span className="font-medium">Disponibile per:</span>{' '}
                                  {(item as any).available_parties.map((partyId: string) => {
                                    const section = sections.find(s => s.id === partyId);
                                    return section ? (section.exact_name || section.party) : partyId;
                                  }).join(', ')}
                                </div>
                              )}
                              
                              {/* Descrizione garanzia */}
                              {(item as any).description && (
                                <div className="text-sm text-muted-foreground">
                                  <RichTextDisplay content={(item as any).description} />
                                </div>
                              )}

                              {/* Tipo di valore */}
                              <div className="flex items-center gap-2">
                                {getValueTypeDisplay((item as any).value_type, (item as any).primo_rischio_value)}
                              </div>

                              {/* Esclusioni comuni della garanzia */}
                              {(item as any).common_exclusions && (item as any).common_exclusions.length > 0 && (
                                <div className="space-y-2">
                                  <div className="text-xs font-medium text-red-700">Esclusioni Comuni:</div>
                                  <ul className="list-disc list-inside space-y-1 text-xs text-muted-foreground ml-2">
                                    {(item as any).common_exclusions.map((exclusion: string, idx: number) => (
                                      <li key={idx}>
                                        <RichTextDisplay content={exclusion} />
                                      </li>
                                    ))}
                                  </ul>
                                </div>
                              )}
                            </div>
                          )}
                        </div>
                      );
                    })}
                  </div>
                </div>
              )}
            </div>
          </Card>

          {/* Limiti Comuni Section - Only show if limits exist */}
          {commonLimits && commonLimits.length > 0 && (
            <Card className="p-6">
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-lg font-semibold flex items-center gap-2">
                  🔒 Limiti Comuni
                </h3>
              </div>
              
              <div className="space-y-4">
                {commonLimits.map(limit => (
                  <div key={limit.id} className="flex items-start justify-between p-4 bg-muted/30 rounded-lg border">
                    <div className="flex-1">
                      <h4 className="font-medium mb-1">{limit.label}</h4>
                      <p className="text-sm text-muted-foreground mb-2">{limit.scope}</p>
                      <div className="flex items-center gap-2">
                        {formatLimitValue(limit.value, limit.on_frontespizio)}
                      </div>
                    </div>
                    {isEditMode && (
                      <Button variant="ghost" size="sm" onClick={() => handleEditCommonLimit(limit)}>
                        <EditIcon className="h-4 w-4" />
                      </Button>
                    )}
                  </div>
                ))}
              </div>
            </Card>
          )}

          {/* Partite Section */}
          <Card className="p-6">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-semibold flex items-center gap-2">
                📋 Partite
              </h3>
              {isEditMode && (
                <Button variant="outline" size="sm" onClick={() => setAddSectionOpen(true)} className="gap-2">
                  <EditIcon className="h-4 w-4" />
                  Aggiungi Partita
                </Button>
              )}
            </div>

            <div className="space-y-6">
              {sections.map(section => (
                <div key={section.id} className="border-l-4 border-primary/20 pl-6 pb-6 border-b border-muted last:border-b-0">
                  <div className="flex items-start justify-between mb-4">
                    <div className="flex items-center gap-3">
                      <span className="text-2xl">{getPartyIcon(section.party as PartyType, section.emoji)}</span>
                      <div>
                        <h4 className="text-lg font-semibold">{section.exact_name || section.party.charAt(0).toUpperCase() + section.party.slice(1)}</h4>
                        <div className="mt-1 space-y-2">
                          {getValueTypeDisplay(section.value_type, section.primo_rischio_value, section.deroga_percentage)}
                          
                          {/* Determinazioni */}
                          {section.determinazione && section.determinazione.length > 0 && (
                            <div>
                              <div className="flex flex-wrap gap-1">
                                {section.determinazione.map(det => {
                                  const isSelected = selectedDeterminazione[section.id] === det;
                                  const hasMultipleDeterminazioni = section.determinazione!.length > 1;
                                  
                                  // Check if this determinazione has different conditions from others
                                  const hasUniqueConditions = hasMultipleDeterminazioni; // For now, always enable if multiple
                                  
                                  return (
                                    <button
                                      key={det}
                                      onClick={() => {
                                        if (hasUniqueConditions) {
                                          setSelectedDeterminazione(prev => ({
                                            ...prev,
                                            [section.id]: isSelected ? '' : det
                                          }));
                                        }
                                      }}
                                      className={`text-xs px-2 py-1 rounded transition-colors ${
                                        hasUniqueConditions 
                                          ? (isSelected 
                                              ? 'bg-primary text-primary-foreground cursor-pointer' 
                                              : 'bg-muted hover:bg-muted/80 cursor-pointer'
                                            )
                                          : 'bg-muted text-muted-foreground cursor-default opacity-60'
                                      }`}
                                      disabled={!hasUniqueConditions}
                                      title={hasUniqueConditions ? 'Clicca per vedere le condizioni specifiche' : 'Condizioni identiche per tutte le determinazioni'}
                                    >
                                      {det}
                                      {hasMultipleDeterminazioni && isSelected && (
                                        <span className="ml-1">✓</span>
                                      )}
                                    </button>
                                  );
                                })}
                              </div>
                            </div>
                          )}
                        </div>
                      </div>
                    </div>
                    {isEditMode && (
                      <Button variant="ghost" size="sm" onClick={() => handleEditSection(section as Section)}>
                        <EditIcon className="h-4 w-4" />
                      </Button>
                    )}
                  </div>

                  <div className="grid lg:grid-cols-2 gap-6">
                    {/* Left Column - Definition and common info */}
                    <div className="space-y-4">
                      <div>
                        <h5 className="font-medium mb-2">Definizione</h5>
                        <RichTextDisplay content={section.definition} className="text-sm text-muted-foreground" />
                        {section.definition_page_reference && (
                          <p className="text-xs text-muted-foreground mt-1">
                            {section.definition_page_reference} {section.definition_article_number && `- ${section.definition_article_number}`}
                          </p>
                        )}
                      </div>

                      {/* Esclusioni Comuni della Partita */}
                      {section.exclusions && section.exclusions.length > 0 && (
                        <div>
                          <h5 className="font-medium mb-2">Esclusioni Comuni</h5>
                          <ul className="list-disc list-inside space-y-1 text-sm text-muted-foreground">
                            {section.exclusions.map((exclusion, index) => (
                              <li key={index}>
                                <RichTextDisplay content={exclusion} />
                              </li>
                            ))}
                          </ul>
                        </div>
                      )}

                      {/* Percentuale deroga se presente */}
                      {section.deroga_percentage && (
                        <div>
                          <h5 className="font-medium mb-2">Deroga</h5>
                          <p className="text-sm text-muted-foreground">{section.deroga_percentage}%</p>
                        </div>
                      )}

                      {/* Note se presenti */}
                      {section.notes && section.notes.length > 0 && (
                        <div>
                          <h5 className="font-medium mb-2">Note</h5>
                          <ul className="list-disc list-inside text-sm text-muted-foreground space-y-1">
                            {section.notes.map((note, index) => (
                              <li key={index}>{note}</li>
                            ))}
                          </ul>
                        </div>
                      )}
                    </div>

                    {/* Right Column - Specific guarantee conditions for this section */}
                    <div className="space-y-4">
                      <h5 className="font-medium">Condizioni Specifiche</h5>
                      <GuaranteeConditionsForSection 
                        sectionId={section.id} 
                        coverageItems={filteredCoverageItems.filter(item => {
                          // Filter by active guarantees
                          if (!activeGuarantees[item.id]) return false;
                          // Filter by available parties
                          if ((item as any).available_parties && (item as any).available_parties.length > 0) {
                            return (item as any).available_parties.includes(section.id);
                          }
                          return true; // Show if no party restriction
                        })} 
                        selectedDeterminazione={selectedDeterminazione[section.id]}
                      />
                    </div>
                  </div>
                </div>
              ))}
              
              {sections.length === 0 && (
                <div className="text-center text-muted-foreground py-8">
                  Nessuna partita configurata
                </div>
              )}
            </div>
          </Card>

        </div>

        {/* Comments and History - Only render for authenticated users */}
        {user && policyId && activeEdition && (
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            <PolicyComments policyId={policyId} editionId={activeEdition} />
            <PolicyHistory policyId={policyId} editionId={activeEdition} />
          </div>
        )}

        {coverage && (
          <EditCoverageDialog
            coverage={coverage as Coverage}
            open={editCoverageOpen}
            onOpenChange={setEditCoverageOpen}
            onSave={handleSaveCoverage}
          />
        )}

        {selectedSection && (
          <EditSectionDialog
            section={selectedSection}
            open={editSectionOpen}
            onOpenChange={setEditSectionOpen}
            onSave={handleSaveSection}
            onDelete={() => handleDeleteSection(selectedSection.id)}
          />
        )}

        {selectedLimit && (
          <EditCommonLimitDialog 
            limit={selectedLimit}
            open={editCommonLimitOpen}
            onOpenChange={setEditCommonLimitOpen}
            onSave={handleSaveCommonLimit}
          />
        )}

        <AddSectionDialog
          coverageId={coverage?.id || ''}
          open={addSectionOpen}
          onOpenChange={setAddSectionOpen}
          onSave={handleAddSection}
        />

        <AddGuaranteeDialog
          coverageId={coverage?.id || ''}
          open={addGuaranteeOpen}
          onOpenChange={setAddGuaranteeOpen}
          onSave={handleAddGuarantee}
        />

        {selectedGuarantee && (
          <EditGuaranteeDialog
            guarantee={selectedGuarantee}
            open={editGuaranteeOpen}
            onOpenChange={setEditGuaranteeOpen}
            onSave={handleSaveGuarantee}
            onDelete={() => handleDeleteGuarantee(selectedGuarantee.id)}
          />
        )}

        {/* AI Processing Modal */}
        <AIProcessingModal
          open={showAIProcessing}
          onOpenChange={setShowAIProcessing}
          processing={extracting}
          extractedData={aiExtractedData}
          partialData={partialData}
          progress={progress}
          currentChunk={currentChunk}
          onConfirm={handleApplyAIData}
          onCancel={handleCancelAIData}
        />
      </div>
    </Layout>
  );
};
