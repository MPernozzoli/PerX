import { useState } from "react";
import { Layout } from "@/components/Layout";
import { Card, CardContent, CardHeader, CardTitle } from "@perx/ui/components/ui/card";
import { Button } from "@perx/ui/components/ui/button";
import { Input } from "@perx/ui/components/ui/input";
import { Label } from "@perx/ui/components/ui/label";
import { Switch } from "@perx/ui/components/ui/switch";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@perx/ui/components/ui/select";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@perx/ui/components/ui/tabs";
import { Separator } from "@perx/ui/components/ui/separator";
import { Badge } from "@perx/ui/components/ui/badge";
import { useUserPreferences } from "@/hooks/useUserPreferences";
import { useGuaranteeGroups, GuaranteeGroup } from "@/hooks/useGuaranteeGroups";
import { useCompanies } from "@/hooks/useCompanies";
import { toast } from "sonner";

export const Settings = () => {
  const [emailNotifications, setEmailNotifications] = useState(true);
  const [pushNotifications, setPushNotifications] = useState(false);
  const [darkMode, setDarkMode] = useState(false);
  
  const { preferences, updatePreferences } = useUserPreferences();
  const { data: guaranteeGroups = [] } = useGuaranteeGroups();
  const { data: companies = [] } = useCompanies();

  const handleUpdatePreference = async (key: string, value: string | undefined) => {
    try {
      await updatePreferences({ [key]: value });
      toast.success("Preferenza aggiornata");
    } catch (error) {
      toast.error("Errore nell'aggiornamento");
    }
  };

  return (
    <Layout>
      <div className="max-w-4xl mx-auto space-y-6">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Impostazioni</h1>
          <p className="text-muted-foreground">
            Gestisci le tue preferenze e impostazioni account
          </p>
        </div>

        <Tabs defaultValue="account" className="space-y-6">
          <TabsList className="grid w-full grid-cols-5">
            <TabsTrigger value="account">Account</TabsTrigger>
            <TabsTrigger value="preferences">Preferenze</TabsTrigger>
            <TabsTrigger value="notifications">Notifiche</TabsTrigger>
            <TabsTrigger value="appearance">Aspetto</TabsTrigger>
            <TabsTrigger value="privacy">Privacy</TabsTrigger>
          </TabsList>

          <TabsContent value="account" className="space-y-6">
            <Card>
              <CardHeader>
                <CardTitle>Informazioni Account</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="grid grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <Label htmlFor="firstName">Nome</Label>
                    <Input id="firstName" defaultValue="Mario" />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="lastName">Cognome</Label>
                    <Input id="lastName" defaultValue="Rossi" />
                  </div>
                </div>
                <div className="space-y-2">
                  <Label htmlFor="email">Email</Label>
                  <Input id="email" type="email" defaultValue="mario.rossi@email.com" />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="phone">Telefono</Label>
                  <Input id="phone" defaultValue="+39 123 456 7890" />
                </div>
                <Button>Salva Modifiche</Button>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle>Password</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="currentPassword">Password Attuale</Label>
                  <Input id="currentPassword" type="password" />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="newPassword">Nuova Password</Label>
                  <Input id="newPassword" type="password" />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="confirmPassword">Conferma Password</Label>
                  <Input id="confirmPassword" type="password" />
                </div>
                <Button variant="outline">Cambia Password</Button>
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="preferences" className="space-y-6">
            <Card>
              <CardHeader>
                <CardTitle>Preferenze di Ricerca</CardTitle>
              </CardHeader>
              <CardContent className="space-y-6">
                <div className="space-y-2">
                  <Label>Garanzia di Default</Label>
                  <Select 
                    value={preferences?.default_guarantee || ''} 
                    onValueChange={(value) => handleUpdatePreference('default_guarantee', value)}
                  >
                    <SelectTrigger className="w-full">
                      <SelectValue placeholder="Seleziona garanzia di default..." />
                    </SelectTrigger>
                    <SelectContent>
                      {guaranteeGroups.map(group => (
                        <SelectItem key={group.id} value={group.code}>{group.name}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <p className="text-sm text-muted-foreground">
                    La garanzia che verrà preselezionata nelle ricerche
                  </p>
                </div>
                
                <Separator />
                
                <div className="space-y-2">
                  <Label>Compagnia di Default</Label>
                  <Select 
                    value={preferences?.default_company || ''} 
                    onValueChange={(value) => handleUpdatePreference('default_company', value || undefined)}
                  >
                    <SelectTrigger className="w-full">
                      <SelectValue placeholder="Tutte le compagnie" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="">Tutte le compagnie</SelectItem>
                      {companies.map(company => (
                        <SelectItem key={company.id} value={company.name}>{company.name}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <p className="text-sm text-muted-foreground">
                    La compagnia che verrà preselezionata nelle ricerche (opzionale)
                  </p>
                </div>
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="notifications" className="space-y-6">
            <Card>
              <CardHeader>
                <CardTitle>Preferenze Notifiche</CardTitle>
              </CardHeader>
              <CardContent className="space-y-6">
                <div className="flex items-center justify-between">
                  <div className="space-y-1">
                    <Label>Notifiche Email</Label>
                    <p className="text-sm text-muted-foreground">
                      Ricevi aggiornamenti via email
                    </p>
                  </div>
                  <Switch
                    checked={emailNotifications}
                    onCheckedChange={setEmailNotifications}
                  />
                </div>
                <Separator />
                <div className="flex items-center justify-between">
                  <div className="space-y-1">
                    <Label>Notifiche Push</Label>
                    <p className="text-sm text-muted-foreground">
                      Ricevi notifiche push nel browser
                    </p>
                  </div>
                  <Switch
                    checked={pushNotifications}
                    onCheckedChange={setPushNotifications}
                  />
                </div>
                <Separator />
                <div className="space-y-2">
                  <Label>Frequenza Email</Label>
                  <Select defaultValue="daily">
                    <SelectTrigger className="w-full">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="immediate">Immediata</SelectItem>
                      <SelectItem value="daily">Giornaliera</SelectItem>
                      <SelectItem value="weekly">Settimanale</SelectItem>
                      <SelectItem value="never">Mai</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="appearance" className="space-y-6">
            <Card>
              <CardHeader>
                <CardTitle>Aspetto</CardTitle>
              </CardHeader>
              <CardContent className="space-y-6">
                <div className="flex items-center justify-between">
                  <div className="space-y-1">
                    <Label>Modalità Scura</Label>
                    <p className="text-sm text-muted-foreground">
                      Attiva il tema scuro
                    </p>
                  </div>
                  <Switch
                    checked={darkMode}
                    onCheckedChange={setDarkMode}
                  />
                </div>
                <Separator />
                <div className="space-y-2">
                  <Label>Lingua</Label>
                  <Select defaultValue="it">
                    <SelectTrigger className="w-full">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="it">Italiano</SelectItem>
                      <SelectItem value="en">English</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-2">
                  <Label>Fuso Orario</Label>
                  <Select defaultValue="europe/rome">
                    <SelectTrigger className="w-full">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="europe/rome">Europa/Roma (GMT+1)</SelectItem>
                      <SelectItem value="europe/london">Europa/Londra (GMT+0)</SelectItem>
                      <SelectItem value="america/new_york">America/New York (GMT-5)</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="privacy" className="space-y-6">
            <Card>
              <CardHeader>
                <CardTitle>Privacy e Sicurezza</CardTitle>
              </CardHeader>
              <CardContent className="space-y-6">
                <div className="space-y-4">
                  <div className="flex items-center justify-between">
                    <div className="space-y-1">
                      <Label>Profilo Pubblico</Label>
                      <p className="text-sm text-muted-foreground">
                        Il tuo profilo è visibile agli altri utenti
                      </p>
                    </div>
                    <Switch defaultChecked />
                  </div>
                  <Separator />
                  <div className="flex items-center justify-between">
                    <div className="space-y-1">
                      <Label>Attività Visibile</Label>
                      <p className="text-sm text-muted-foreground">
                        Mostra la tua attività agli altri membri dello studio
                      </p>
                    </div>
                    <Switch defaultChecked />
                  </div>
                </div>
                
                <Separator />
                
                <div className="space-y-4">
                  <h4 className="text-sm font-medium">Gestione Dati</h4>
                  <div className="space-y-2">
                    <Button variant="outline" className="w-full justify-start">
                      Esporta i tuoi dati
                    </Button>
                    <Button variant="outline" className="w-full justify-start">
                      Elimina account
                      <Badge variant="destructive" className="ml-2">
                        Pericoloso
                      </Badge>
                    </Button>
                  </div>
                </div>
              </CardContent>
            </Card>
          </TabsContent>
        </Tabs>
      </div>
    </Layout>
  );
};