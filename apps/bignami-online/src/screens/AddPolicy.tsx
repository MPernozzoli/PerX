import { useState } from "react";
import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { Layout } from "@/components/Layout";
import { Card } from "@perx/ui/components/ui/card";
import { Button } from "@perx/ui/components/ui/button";
import { Input } from "@perx/ui/components/ui/input";
import { Textarea } from "@perx/ui/components/ui/textarea";
import { Label } from "@perx/ui/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@perx/ui/components/ui/select";
import {
  Command,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@perx/ui/components/ui/command";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@perx/ui/components/ui/popover";
import {
  Form,
  FormControl,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from "@perx/ui/components/ui/form";
import { ArrowLeftIcon, PlusIcon, CheckIcon, ChevronsUpDownIcon } from "lucide-react";
import { useNavigate } from "react-router-dom";
import { PolicyType } from "@/types";
import { toast } from "@/hooks/use-toast";
import { RadioGroup, RadioGroupItem } from "@perx/ui/components/ui/radio-group";
import { useCompanies, useCreateCompany } from "@/hooks/useCompanies";
import { usePolicies, useCreatePolicy, useCreatePolicyEdition } from "@/hooks/usePolicies";

const policySchema = z.object({
  action_type: z.enum(["new_policy", "new_edition"] as const, {
    errorMap: () => ({ message: "Seleziona un'azione" })
  }),
  existing_policy_id: z.string().optional(),
  name: z.string().optional(),
  company_id: z.string().optional(),
  new_company_name: z.string().optional(),
  type: z.enum(["domestica", "azienda", "agricola"] as const).optional(),
  description: z.string().optional(), // Sempre opzionale
  tags: z.string().optional(),
  year: z.number().min(2000, "Anno non valido").max(2030, "Anno non valido"),
  edition_label: z.string().min(1, "L'etichetta edizione è obbligatoria"),
  default_guarantee: z.string().optional(),
}).refine((data) => {
  // Validazioni condizionali per nuova polizza
  if (data.action_type === "new_policy") {
    if (!data.name?.trim()) return false;
    if (!data.company_id) return false;
    if (!data.type) return false;
    if (!data.default_guarantee?.trim()) return false;
    if (data.company_id === "new_company" && !data.new_company_name?.trim()) return false;
  }
  
  // Validazioni condizionali per nuova edizione
  if (data.action_type === "new_edition") {
    if (!data.existing_policy_id) return false;
  }
  
  return true;
}, {
  message: "Completa tutti i campi obbligatori",
  path: [], // Il path verrà determinato dalla logica specifica
}).refine((data) => {
  if (data.action_type === "new_policy" && !data.name?.trim()) {
    return false;
  }
  return true;
}, {
  message: "Il nome della polizza è obbligatorio",
  path: ["name"],
}).refine((data) => {
  if (data.action_type === "new_policy" && !data.company_id) {
    return false;
  }
  return true;
}, {
  message: "Seleziona una compagnia",
  path: ["company_id"],
}).refine((data) => {
  if (data.action_type === "new_policy" && !data.type) {
    return false;
  }
  return true;
}, {
  message: "Seleziona un tipo di polizza",
  path: ["type"],
}).refine((data) => {
  if (data.action_type === "new_policy" && !data.default_guarantee?.trim()) {
    return false;
  }
  return true;
}, {
  message: "La garanzia di default è obbligatoria",
  path: ["default_guarantee"],
}).refine((data) => {
  if (data.action_type === "new_edition" && !data.existing_policy_id) {
    return false;
  }
  return true;
}, {
  message: "Seleziona una polizza esistente",
  path: ["existing_policy_id"],
}).refine((data) => {
  if (data.company_id === "new_company" && !data.new_company_name?.trim()) {
    return false;
  }
  return true;
}, {
  message: "Il nome della nuova compagnia è obbligatorio",
  path: ["new_company_name"],
});

type PolicyFormData = z.infer<typeof policySchema>;

export const AddPolicy = () => {
  const navigate = useNavigate();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [companyOpen, setCompanyOpen] = useState(false);
  const [policyOpen, setPolicyOpen] = useState(false);
  
  const { data: companies = [], isLoading: companiesLoading } = useCompanies();
  const { data: allPolicies = [], isLoading: policiesLoading } = usePolicies();
  const createCompanyMutation = useCreateCompany();
  const createPolicyMutation = useCreatePolicy();
  const createPolicyEditionMutation = useCreatePolicyEdition();

  const form = useForm<PolicyFormData>({
    resolver: zodResolver(policySchema),
    defaultValues: {
      action_type: "new_policy",
      existing_policy_id: "",
      name: "",
      company_id: "",
      new_company_name: "",
      type: "domestica",
      description: "",
      tags: "",
      year: new Date().getFullYear(),
      edition_label: "",
      default_guarantee: "Fenomeno Elettrico",
    },
  });

  const actionType = form.watch("action_type");
  const companyId = form.watch("company_id");

  const onSubmit = async (data: PolicyFormData) => {
    setIsSubmitting(true);
    
    try {
      let companyId = data.company_id;
      
      // Create new company if needed
      if (data.company_id === "new_company" && data.new_company_name) {
        const newCompany = await createCompanyMutation.mutateAsync({
          name: data.new_company_name,
          code: data.new_company_name.substring(0, 3).toUpperCase(),
          aliases: []
        });
        companyId = newCompany.id;
      }

      if (data.action_type === "new_policy") {
        // Controllo per polizze duplicate
        const existingPolicy = allPolicies.find(p => 
          p.name.toLowerCase() === data.name.toLowerCase() && 
          p.company_id === companyId
        );

        if (existingPolicy) {
          // Controlla se esiste già un'edizione per l'anno specificato
          const existingEdition = existingPolicy.policy_editions?.find(e => 
            e.year === data.year && e.edition_label === data.edition_label
          );

          if (existingEdition) {
            toast({
              title: "Edizione già esistente",
              description: `La polizza "${data.name}" ha già un'edizione "${data.edition_label}" per l'anno ${data.year}. Modifica l'etichetta o l'anno.`,
              variant: "destructive",
            });
            return;
          }

          // Polizza esiste ma non l'edizione - suggerisci di aggiungere l'edizione
          toast({
            title: "Polizza già esistente",
            description: `La polizza "${data.name}" esiste già. Vuoi aggiungere una nuova edizione invece?`,
            variant: "destructive",
          });
          
          // Auto-switch to add edition mode
          form.setValue("action_type", "new_edition");
          form.setValue("existing_policy_id", existingPolicy.id);
          return;
        }

        // Create new policy
        const newPolicy = await createPolicyMutation.mutateAsync({
          name: data.name,
          code: Math.random().toString(36).substr(2, 8).toUpperCase(),
          company_id: companyId,
          type: data.type,
          description: data.description,
          tags: data.tags ? data.tags.split(",").map(tag => tag.trim()) : [],
          default_guarantee: data.default_guarantee,
        });

        // Create policy edition
        await createPolicyEditionMutation.mutateAsync({
          policy_id: newPolicy.id,
          year: data.year,
          code: `ED${data.year}A`,
          edition_label: data.edition_label,
          status: "draft",
        });

        toast({
          title: "Polizza creata con successo",
          description: `La polizza "${data.name}" è stata creata. Ora puoi aggiungere le coperture.`,
        });

        // Navigate to policy detail to continue configuration
        navigate(`/policy/${newPolicy.id}`);
      } else {
        // Add new edition to existing policy
        const selectedPolicy = allPolicies.find(p => p.id === data.existing_policy_id);
        
        if (!selectedPolicy) {
          toast({
            title: "Errore",
            description: "Polizza non trovata. Riprova.",
            variant: "destructive",
          });
          return;
        }

        // Controllo per edizioni duplicate
        const existingEdition = selectedPolicy.policy_editions?.find(e => 
          e.year === data.year && e.edition_label === data.edition_label
        );

        if (existingEdition) {
          toast({
            title: "Edizione già esistente",
            description: `La polizza "${selectedPolicy.name}" ha già un'edizione "${data.edition_label}" per l'anno ${data.year}. Modifica l'etichetta o l'anno.`,
            variant: "destructive",
          });
          return;
        }
        
        const newEdition = await createPolicyEditionMutation.mutateAsync({
          policy_id: data.existing_policy_id!,
          year: data.year,
          code: `ED${data.year}A`,
          edition_label: data.edition_label,
          status: "draft",
        });

        toast({
          title: "Edizione aggiunta con successo",
          description: `Nuova edizione "${data.edition_label}" aggiunta alla polizza "${selectedPolicy?.name}".`,
        });

        navigate(`/policy/${data.existing_policy_id}/edition/${newEdition.id}`);
      }
    } catch (error) {
      console.error("Errore durante la creazione:", error);
      toast({
        title: "Errore",
        description: "Si è verificato un errore durante l'operazione. Riprova.",
        variant: "destructive",
      });
    } finally {
      setIsSubmitting(false);
    }
  };

  const typeOptions: { value: PolicyType; label: string }[] = [
    { value: "domestica", label: "Domestica" },
    { value: "azienda", label: "Azienda" },
    { value: "agricola", label: "Agricola" },
  ];

  return (
    <Layout>
      <div className="max-w-2xl mx-auto space-y-6">
        {/* Header */}
        <div className="flex items-center gap-4">
          <Button
            variant="ghost"
            onClick={() => navigate("/")}
            className="gap-2"
          >
            <ArrowLeftIcon className="h-4 w-4" />
            Torna alla Home
          </Button>
        </div>
        
        <div className="space-y-2">
          <h1 className="text-2xl font-bold">Gestione Polizze</h1>
          <p className="text-muted-foreground">
            Crea una nuova polizza o aggiungi una nuova edizione a una polizza esistente.
          </p>
        </div>

        {/* Form */}
        <Card className="p-6">
          <Form {...form}>
            <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-6">
              {/* Scelta azione */}
              <FormField
                control={form.control}
                name="action_type"
                render={({ field }) => (
                  <FormItem className="space-y-3">
                    <FormLabel>Cosa vuoi fare?</FormLabel>
                    <FormControl>
                      <RadioGroup
                        onValueChange={field.onChange}
                        defaultValue={field.value}
                        className="flex flex-col space-y-2"
                      >
                        <div className="flex items-center space-x-2">
                          <RadioGroupItem value="new_policy" id="new_policy" />
                          <Label htmlFor="new_policy">Aggiungere una nuova polizza</Label>
                        </div>
                        <div className="flex items-center space-x-2">
                          <RadioGroupItem value="new_edition" id="new_edition" />
                          <Label htmlFor="new_edition">Aggiungere una nuova edizione a una polizza esistente</Label>
                        </div>
                      </RadioGroup>
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />

              {/* Selezione polizza esistente se si aggiunge edizione */}
              {actionType === "new_edition" && (
                <FormField
                  control={form.control}
                  name="existing_policy_id"
                  render={({ field }) => (
                    <FormItem className="flex flex-col">
                      <FormLabel>Polizza Esistente</FormLabel>
                      <Popover open={policyOpen} onOpenChange={setPolicyOpen}>
                        <PopoverTrigger asChild>
                          <FormControl>
                            <Button
                              variant="outline"
                              role="combobox"
                              className="justify-between"
                            >
                              {field.value
                                 ? allPolicies.find((policy) => policy.id === field.value)?.name + 
                                   " - " + allPolicies.find((policy) => policy.id === field.value)?.companies.name
                                : "Cerca polizza..."}
                              <ChevronsUpDownIcon className="ml-2 h-4 w-4 shrink-0 opacity-50" />
                            </Button>
                          </FormControl>
                        </PopoverTrigger>
                        <PopoverContent className="w-full p-0 bg-background border shadow-md z-50">
                          <Command>
                            <CommandInput placeholder="Cerca polizza..." />
                            <CommandList>
                              <CommandEmpty>Nessuna polizza trovata.</CommandEmpty>
                              <CommandGroup>
                                {allPolicies.map((policy) => (
                                  <CommandItem
                                    value={`${policy.name} ${policy.companies.name}`}
                                    key={policy.id}
                                    onSelect={() => {
                                      field.onChange(policy.id);
                                      setPolicyOpen(false);
                                    }}
                                  >
                                    <CheckIcon
                                      className={`mr-2 h-4 w-4 ${
                                        policy.id === field.value ? "opacity-100" : "opacity-0"
                                      }`}
                                    />
                                    {policy.name} - {policy.companies.name}
                                  </CommandItem>
                                ))}
                              </CommandGroup>
                            </CommandList>
                          </Command>
                        </PopoverContent>
                      </Popover>
                      <FormMessage />
                    </FormItem>
                  )}
                />
              )}

              {/* Nome Polizza - solo per nuove polizze */}
              {actionType === "new_policy" && (
              <FormField
                control={form.control}
                name="name"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Nome Polizza</FormLabel>
                    <FormControl>
                      <Input 
                        placeholder="es. Casa&Persona, Business Protection"
                        {...field}
                      />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />
              )}

              {/* Compagnia - solo per nuove polizze */}
              {actionType === "new_policy" && (
              <FormField
                control={form.control}
                name="company_id"
                render={({ field }) => (
                  <FormItem className="flex flex-col">
                    <FormLabel>Compagnia Assicurativa</FormLabel>
                    <Popover open={companyOpen} onOpenChange={setCompanyOpen}>
                      <PopoverTrigger asChild>
                        <FormControl>
                          <Button
                            variant="outline"
                            role="combobox"
                            className="justify-between"
                          >
                            {field.value === "new_company" 
                              ? "+ Aggiungi nuova compagnia"
                              : field.value
                              ? companies.find((company) => company.id === field.value)?.name
                              : "Cerca compagnia..."}
                            <ChevronsUpDownIcon className="ml-2 h-4 w-4 shrink-0 opacity-50" />
                          </Button>
                        </FormControl>
                      </PopoverTrigger>
                      <PopoverContent className="w-full p-0 bg-background border shadow-md z-50">
                        <Command>
                          <CommandInput placeholder="Cerca compagnia..." />
                          <CommandList>
                            <CommandEmpty>Nessuna compagnia trovata.</CommandEmpty>
                            <CommandGroup>
                              {companies.map((company) => (
                                <CommandItem
                                  value={company.name}
                                  key={company.id}
                                  onSelect={() => {
                                    field.onChange(company.id);
                                    setCompanyOpen(false);
                                  }}
                                >
                                  <CheckIcon
                                    className={`mr-2 h-4 w-4 ${
                                      company.id === field.value ? "opacity-100" : "opacity-0"
                                    }`}
                                  />
                                  {company.name}
                                </CommandItem>
                              ))}
                              <CommandItem
                                value="+ Aggiungi nuova compagnia"
                                onSelect={() => {
                                  field.onChange("new_company");
                                  setCompanyOpen(false);
                                }}
                              >
                                <PlusIcon className="mr-2 h-4 w-4" />
                                Aggiungi nuova compagnia
                              </CommandItem>
                            </CommandGroup>
                          </CommandList>
                        </Command>
                      </PopoverContent>
                    </Popover>
                    <FormMessage />
                  </FormItem>
                )}
              />
              )}

              {/* Campo per nuova compagnia */}
              {actionType === "new_policy" && companyId === "new_company" && (
                <FormField
                  control={form.control}
                  name="new_company_name"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Nome Nuova Compagnia</FormLabel>
                      <FormControl>
                        <Input 
                          placeholder="es. Generali Assicurazioni"
                          {...field}
                        />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
              )}

              {/* Tipo Polizza - solo per nuove polizze */}
              {actionType === "new_policy" && (
              <FormField
                control={form.control}
                name="type"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Tipo di Polizza</FormLabel>
                    <Select onValueChange={field.onChange} defaultValue={field.value}>
                      <FormControl>
                        <SelectTrigger>
                          <SelectValue placeholder="Seleziona il tipo" />
                        </SelectTrigger>
                      </FormControl>
                      <SelectContent>
                        {typeOptions.map((option) => (
                          <SelectItem key={option.value} value={option.value}>
                            {option.label}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    <FormMessage />
                  </FormItem>
                )}
              />
              )}

              {/* Anno e Edizione */}
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <FormField
                  control={form.control}
                  name="year"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Anno</FormLabel>
                      <FormControl>
                        <Input 
                          type="number"
                          min="2000"
                          max="2030"
                          {...field}
                          onChange={(e) => field.onChange(parseInt(e.target.value) || new Date().getFullYear())}
                        />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />

                <FormField
                  control={form.control}
                  name="edition_label"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Edizione</FormLabel>
                      <FormControl>
                        <Input 
                          placeholder="es. Ed. 01/2024"
                          {...field}
                        />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
              </div>

              {/* Descrizione - solo per nuove polizze */}
              {actionType === "new_policy" && (
              <FormField
                control={form.control}
                name="description"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Descrizione</FormLabel>
                    <FormControl>
                      <Textarea 
                        placeholder="Descrivi brevemente la polizza e le sue caratteristiche principali..."
                        className="min-h-[100px]"
                        {...field}
                      />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />
               )}

              {/* Tags - solo per nuove polizze */}
              {actionType === "new_policy" && (
              <FormField
                control={form.control}
                name="tags"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Tag (opzionale)</FormLabel>
                    <FormControl>
                      <Input 
                        placeholder="es. multirischi, famiglia, abitazione (separati da virgola)"
                        {...field}
                      />
                    </FormControl>
                    <p className="text-sm text-muted-foreground">
                      Inserisci i tag separati da virgola per facilitare la ricerca
                    </p>
                    <FormMessage />
                  </FormItem>
                )}
              />
              )}

              {/* Garanzia di Default - solo per nuove polizze */}
              {actionType === "new_policy" && (
              <FormField
                control={form.control}
                name="default_guarantee"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Garanzia di Default</FormLabel>
                    <FormControl>
                      <Input 
                        placeholder="es. Fenomeno Elettrico"
                        {...field}
                      />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />
              )}

              {/* Buttons */}
              <div className="flex gap-4 pt-4">
                <Button
                  type="button"
                  variant="outline"
                  onClick={() => navigate("/")}
                  disabled={isSubmitting}
                >
                  Annulla
                </Button>
                <Button
                  type="submit"
                  disabled={isSubmitting}
                  className="gap-2"
                >
                  <PlusIcon className="h-4 w-4" />
                  {isSubmitting 
                    ? (actionType === "new_policy" ? "Aggiunta..." : "Aggiunta...") 
                    : (actionType === "new_policy" ? "Aggiungi Polizza" : "Aggiungi Edizione")
                  }
                </Button>
              </div>
            </form>
          </Form>
        </Card>

        {/* Info Card */}
        <Card className="p-4 bg-muted/30">
          <h3 className="font-medium mb-2">Informazioni</h3>
          <p className="text-sm text-muted-foreground">
            {actionType === "new_policy" 
              ? "Dopo aver creato la polizza, potrai aggiungere ulteriori edizioni e definire le condizioni di copertura."
              : "Stai aggiungendo una nuova edizione a una polizza esistente. Assicurati che i dati siano corretti."
            }
          </p>
        </Card>
      </div>
    </Layout>
  );
};