import { useState } from "react";
import { Layout } from "@/components/Layout";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Badge } from "@/components/ui/badge";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Separator } from "@/components/ui/separator";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { 
  Settings, 
  Users, 
  Shield, 
  Copy, 
  UserPlus, 
  UserMinus, 
  Crown,
  CheckCircle,
  AlertTriangle,
  Building
} from "lucide-react";
import { useToast } from "@/hooks/use-toast";

export const StudioSettings = () => {
  const { toast } = useToast();
  const [invitationCode, setInvitationCode] = useState("BIGNAMI1");
  
  // Mock data - in real implementation, fetch from Supabase
  const studio = {
    name: "Studio Bignami",
    description: "Studio professionale per periti assicurativi specializzati in fenomeni elettrici",
    membersCount: 12,
    createdAt: "2024-01-15"
  };

  const members = [
    {
      id: "1",
      name: "Mario Rossi",
      email: "mario.rossi@email.com",
      role: "admin" as const,
      joinedAt: "2024-01-15",
      companies: []
    },
    {
      id: "2", 
      name: "Giuseppe Verdi",
      email: "g.verdi@email.com",
      role: "team_leader" as const,
      joinedAt: "2024-02-01",
      companies: ["Generali", "Allianz"]
    },
    {
      id: "3",
      name: "Anna Bianchi",
      email: "a.bianchi@email.com", 
      role: "moderator" as const,
      joinedAt: "2024-02-15",
      companies: []
    },
    {
      id: "4",
      name: "Luca Ferrari", 
      email: "l.ferrari@email.com",
      role: "member" as const,
      joinedAt: "2024-03-01",
      companies: []
    }
  ];

  const companies = ["Generali", "Allianz", "AXA", "Zurich", "UnipolSai", "Reale Mutua"];

  const copyInvitationCode = () => {
    navigator.clipboard.writeText(invitationCode);
    toast({
      title: "Codice copiato!",
      description: "Il codice di invito è stato copiato negli appunti."
    });
  };

  const getRoleLabel = (role: string) => {
    switch (role) {
      case "admin": return "Amministratore";
      case "team_leader": return "Capo Team";
      case "moderator": return "Moderatore";
      default: return "Membro";
    }
  };

  const getRoleBadgeVariant = (role: string) => {
    switch (role) {
      case "admin": return "destructive" as const;
      case "team_leader": return "default" as const;
      case "moderator": return "secondary" as const;
      default: return "outline" as const;
    }
  };

  return (
    <Layout>
      <div className="max-w-6xl mx-auto space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-3xl font-bold tracking-tight flex items-center gap-2">
              <Settings className="h-8 w-8" />
              Impostazioni Studio
            </h1>
            <p className="text-muted-foreground">
              Gestisci le impostazioni, i membri e i ruoli del tuo studio
            </p>
          </div>
        </div>

        <Tabs defaultValue="general" className="space-y-6">
          <TabsList className="grid w-full grid-cols-4">
            <TabsTrigger value="general">Generali</TabsTrigger>
            <TabsTrigger value="members">Membri</TabsTrigger>
            <TabsTrigger value="companies">Compagnie</TabsTrigger>
            <TabsTrigger value="permissions">Permessi</TabsTrigger>
          </TabsList>

          <TabsContent value="general" className="space-y-6">
            <Card>
              <CardHeader>
                <CardTitle>Informazioni Studio</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="space-y-2">
                  <Label htmlFor="studioName">Nome Studio</Label>
                  <Input id="studioName" defaultValue={studio.name} />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="studioDescription">Descrizione</Label>
                  <Textarea 
                    id="studioDescription" 
                    defaultValue={studio.description}
                    rows={3}
                  />
                </div>
                <Button>Salva Modifiche</Button>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle>Codice di Invito</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="flex items-center gap-2">
                  <Input 
                    value={invitationCode} 
                    readOnly 
                    className="font-mono"
                  />
                  <Button variant="outline" size="icon" onClick={copyInvitationCode}>
                    <Copy className="h-4 w-4" />
                  </Button>
                </div>
                <p className="text-sm text-muted-foreground">
                  Condividi questo codice con i nuovi membri per farli unire allo studio.
                </p>
                <Button variant="outline" className="w-full">
                  Genera Nuovo Codice
                </Button>
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="members" className="space-y-6">
            <Card>
              <CardHeader>
                <CardTitle className="flex items-center justify-between">
                  <span className="flex items-center gap-2">
                    <Users className="h-5 w-5" />
                    Membri dello Studio ({members.length})
                  </span>
                  <Button size="sm" className="gap-2">
                    <UserPlus className="h-4 w-4" />
                    Invita Membro
                  </Button>
                </CardTitle>
              </CardHeader>
              <CardContent>
                <div className="space-y-4">
                  {members.map((member) => (
                    <div key={member.id} className="flex items-center justify-between p-4 border rounded-lg">
                      <div className="flex items-center gap-3">
                        <Avatar>
                          <AvatarImage src={`https://api.dicebear.com/7.x/avataaars/svg?seed=${member.name}`} />
                          <AvatarFallback>
                            {member.name.split(' ').map(n => n[0]).join('')}
                          </AvatarFallback>
                        </Avatar>
                        <div>
                          <div className="flex items-center gap-2">
                            <h4 className="font-medium">{member.name}</h4>
                            <Badge variant={getRoleBadgeVariant(member.role)}>
                              {member.role === "admin" && <Crown className="h-3 w-3 mr-1" />}
                              {member.role === "team_leader" && <Shield className="h-3 w-3 mr-1" />}
                              {getRoleLabel(member.role)}
                            </Badge>
                          </div>
                          <p className="text-sm text-muted-foreground">{member.email}</p>
                          {member.companies.length > 0 && (
                            <div className="flex items-center gap-1 mt-1">
                              <Building className="h-3 w-3 text-muted-foreground" />
                              <span className="text-xs text-muted-foreground">
                                {member.companies.join(", ")}
                              </span>
                            </div>
                          )}
                        </div>
                      </div>
                      <div className="flex items-center gap-2">
                        <Select defaultValue={member.role}>
                          <SelectTrigger className="w-40">
                            <SelectValue />
                          </SelectTrigger>
                          <SelectContent>
                            <SelectItem value="member">Membro</SelectItem>
                            <SelectItem value="moderator">Moderatore</SelectItem>
                            <SelectItem value="team_leader">Capo Team</SelectItem>
                            <SelectItem value="admin">Amministratore</SelectItem>
                          </SelectContent>
                        </Select>
                        <Button variant="outline" size="icon">
                          <UserMinus className="h-4 w-4" />
                        </Button>
                      </div>
                    </div>
                  ))}
                </div>
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="companies" className="space-y-6">
            <Card>
              <CardHeader>
                <CardTitle>Gestione Compagnie</CardTitle>
              </CardHeader>
              <CardContent className="space-y-4">
                <div className="space-y-2">
                  <Label>Compagnie Attive</Label>
                  <div className="flex flex-wrap gap-2">
                    {companies.map((company) => (
                      <Badge key={company} variant="outline" className="gap-1">
                        <Building className="h-3 w-3" />
                        {company}
                      </Badge>
                    ))}
                  </div>
                </div>
                
                <Separator />
                
                <div className="space-y-2">
                  <Label htmlFor="newCompany">Aggiungi Nuova Compagnia</Label>
                  <div className="flex gap-2">
                    <Input 
                      id="newCompany" 
                      placeholder="Nome della compagnia..."
                    />
                    <Button>Aggiungi</Button>
                  </div>
                </div>

                <Separator />

                <div className="space-y-4">
                  <h4 className="font-medium">Assegnazione Capi Team</h4>
                  {companies.map((company) => {
                    const teamLeader = members.find(m => 
                      m.role === "team_leader" && m.companies.includes(company)
                    );
                    
                    return (
                      <div key={company} className="flex items-center justify-between p-3 border rounded-lg">
                        <div className="flex items-center gap-2">
                          <Building className="h-4 w-4 text-muted-foreground" />
                          <span className="font-medium">{company}</span>
                        </div>
                        <div className="flex items-center gap-2">
                          {teamLeader ? (
                            <div className="flex items-center gap-2">
                              <CheckCircle className="h-4 w-4 text-green-500" />
                              <span className="text-sm">{teamLeader.name}</span>
                            </div>
                          ) : (
                            <div className="flex items-center gap-2">
                              <AlertTriangle className="h-4 w-4 text-orange-500" />
                              <span className="text-sm text-muted-foreground">Nessun capo team</span>
                            </div>
                          )}
                          <Select>
                            <SelectTrigger className="w-40">
                              <SelectValue placeholder="Assegna capo team" />
                            </SelectTrigger>
                            <SelectContent>
                              {members
                                .filter(m => m.role === "team_leader")
                                .map(leader => (
                                  <SelectItem key={leader.id} value={leader.id}>
                                    {leader.name}
                                  </SelectItem>
                                ))}
                            </SelectContent>
                          </Select>
                        </div>
                      </div>
                    );
                  })}
                </div>
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="permissions" className="space-y-6">
            <Card>
              <CardHeader>
                <CardTitle>Matrice dei Permessi</CardTitle>
              </CardHeader>
              <CardContent>
                <div className="overflow-x-auto">
                  <table className="w-full border-collapse">
                    <thead>
                      <tr className="border-b">
                        <th className="text-left p-3">Azione</th>
                        <th className="text-center p-3">Membro</th>
                        <th className="text-center p-3">Moderatore</th>
                        <th className="text-center p-3">Capo Team</th>
                        <th className="text-center p-3">Amministratore</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y">
                      <tr>
                        <td className="p-3 font-medium">Pubblicare post</td>
                        <td className="text-center p-3"><CheckCircle className="h-5 w-5 text-green-500 mx-auto" /></td>
                        <td className="text-center p-3"><CheckCircle className="h-5 w-5 text-green-500 mx-auto" /></td>
                        <td className="text-center p-3"><CheckCircle className="h-5 w-5 text-green-500 mx-auto" /></td>
                        <td className="text-center p-3"><CheckCircle className="h-5 w-5 text-green-500 mx-auto" /></td>
                      </tr>
                      <tr>
                        <td className="p-3 font-medium">Moderare post e commenti</td>
                        <td className="text-center p-3">-</td>
                        <td className="text-center p-3"><CheckCircle className="h-5 w-5 text-green-500 mx-auto" /></td>
                        <td className="text-center p-3">-</td>
                        <td className="text-center p-3"><CheckCircle className="h-5 w-5 text-green-500 mx-auto" /></td>
                      </tr>
                      <tr>
                        <td className="p-3 font-medium">Revisione polizze (compagnie assegnate)</td>
                        <td className="text-center p-3">-</td>
                        <td className="text-center p-3">-</td>
                        <td className="text-center p-3"><CheckCircle className="h-5 w-5 text-green-500 mx-auto" /></td>
                        <td className="text-center p-3"><CheckCircle className="h-5 w-5 text-green-500 mx-auto" /></td>
                      </tr>
                      <tr>
                        <td className="p-3 font-medium">Gestire membri e ruoli</td>
                        <td className="text-center p-3">-</td>
                        <td className="text-center p-3">-</td>
                        <td className="text-center p-3">-</td>
                        <td className="text-center p-3"><CheckCircle className="h-5 w-5 text-green-500 mx-auto" /></td>
                      </tr>
                      <tr>
                        <td className="p-3 font-medium">Impostazioni studio</td>
                        <td className="text-center p-3">-</td>
                        <td className="text-center p-3">-</td>
                        <td className="text-center p-3">-</td>
                        <td className="text-center p-3"><CheckCircle className="h-5 w-5 text-green-500 mx-auto" /></td>
                      </tr>
                    </tbody>
                  </table>
                </div>
              </CardContent>
            </Card>
          </TabsContent>
        </Tabs>
      </div>
    </Layout>
  );
};