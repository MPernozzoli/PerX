import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Layout } from "@/components/Layout";
import { Edit, MapPin, Calendar, Users, FileText, Award, Plus } from "lucide-react";
import { Input } from "@/components/ui/input";

export const Profile = () => {
  // Mock user data - in real app this would come from auth/database
  const user = {
    id: "1",
    name: "Marco Rossi",
    email: "marco.rossi@email.com",
    auth_provider: "email",
    created_at: "2024-01-15",
    bio: "Perito assicurativo specializzato in danni domestici e aziendali. 15 anni di esperienza nel settore.",
    location: "Milano, Italia",
    avatar: "",
    specializations: ["Danni Domestici", "RC Generale", "Fenomeni Elettrici"],
    stats: {
      policies: 142,
      studios: 3,
      reviews: 89
    }
  };

  const recentActivity = [
    { id: 1, type: "policy", action: "Aggiunta nuova polizza", item: "AXA - Casa Sicura 2024", date: "2 ore fa" },
    { id: 2, type: "studio", action: "Entrato nello studio", item: "Studio Legale Bianchi", date: "1 giorno fa" },
    { id: 3, type: "review", action: "Ricevuta recensione", item: "Valutazione danni RC Auto", date: "3 giorni fa" },
  ];

  return (
    <Layout>
      <div className="container mx-auto px-4 py-8 max-w-4xl">
        {/* Header Profile */}
        <Card className="mb-8">
          <CardContent className="pt-6">
            <div className="flex flex-col md:flex-row gap-6">
              <div className="flex flex-col items-center md:items-start">
                <Avatar className="w-32 h-32">
                  <AvatarImage src={user.avatar} />
                  <AvatarFallback className="text-2xl">
                    {user.name.split(' ').map(n => n[0]).join('')}
                  </AvatarFallback>
                </Avatar>
                <Button variant="outline" className="mt-4" size="sm">
                  <Edit className="w-4 h-4 mr-2" />
                  Modifica Profilo
                </Button>
              </div>
              
              <div className="flex-1 space-y-4">
                <div>
                  <h1 className="text-3xl font-bold">{user.name}</h1>
                  <p className="text-muted-foreground flex items-center mt-1">
                    <MapPin className="w-4 h-4 mr-1" />
                    {user.location}
                  </p>
                  <p className="text-muted-foreground flex items-center mt-1">
                    <Calendar className="w-4 h-4 mr-1" />
                    Iscritto dal {new Date(user.created_at).toLocaleDateString('it-IT')}
                  </p>
                </div>
                
                <p className="text-sm">{user.bio}</p>
                
                <div className="flex flex-wrap gap-2">
                  {user.specializations.map((spec) => (
                    <Badge key={spec} variant="secondary">
                      {spec}
                    </Badge>
                  ))}
                </div>
                
                <div className="grid grid-cols-3 gap-4 pt-4">
                  <div className="text-center">
                    <div className="text-2xl font-bold text-primary">{user.stats.policies}</div>
                    <div className="text-sm text-muted-foreground">Polizze</div>
                  </div>
                  <div className="text-center">
                    <div className="text-2xl font-bold text-primary">{user.stats.studios}</div>
                    <div className="text-sm text-muted-foreground">Studi</div>
                  </div>
                  <div className="text-center">
                    <div className="text-2xl font-bold text-primary">{user.stats.reviews}</div>
                    <div className="text-sm text-muted-foreground">Recensioni</div>
                  </div>
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Tabs Content */}
        <Tabs defaultValue="activity" className="space-y-6">
          <TabsList className="grid w-full grid-cols-4">
            <TabsTrigger value="activity">Attività</TabsTrigger>
            <TabsTrigger value="policies">Polizze</TabsTrigger>
            <TabsTrigger value="studios">Studi</TabsTrigger>
            <TabsTrigger value="reviews">Recensioni</TabsTrigger>
          </TabsList>
          
          <TabsContent value="activity">
            <Card>
              <CardHeader>
                <h3 className="text-lg font-semibold">Attività Recente</h3>
              </CardHeader>
              <CardContent className="space-y-4">
                {recentActivity.map((activity) => (
                  <div key={activity.id} className="flex items-start space-x-3 p-3 rounded-lg hover:bg-muted/50">
                    <div className="w-8 h-8 rounded-full bg-primary/10 flex items-center justify-center">
                      {activity.type === 'policy' && <FileText className="w-4 h-4 text-primary" />}
                      {activity.type === 'studio' && <Users className="w-4 h-4 text-primary" />}
                      {activity.type === 'review' && <Award className="w-4 h-4 text-primary" />}
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm">
                        <span className="font-medium">{activity.action}</span>: {activity.item}
                      </p>
                      <p className="text-xs text-muted-foreground">{activity.date}</p>
                    </div>
                  </div>
                ))}
              </CardContent>
            </Card>
          </TabsContent>
          
          <TabsContent value="policies">
            <Card>
              <CardHeader>
                <h3 className="text-lg font-semibold">Le Mie Polizze</h3>
              </CardHeader>
              <CardContent>
                <p className="text-muted-foreground">Elenco delle polizze gestite dall'utente</p>
              </CardContent>
            </Card>
          </TabsContent>
          
          <TabsContent value="studios">
            <div className="space-y-6">
              {/* Current Studio */}
              <Card>
                <CardHeader>
                  <h3 className="text-lg font-semibold">Il Mio Studio</h3>
                </CardHeader>
                <CardContent className="space-y-4">
                  <div className="flex items-center justify-between p-4 bg-muted rounded-lg">
                    <div>
                      <h4 className="font-medium">Studio Legale Bianchi & Associati</h4>
                      <p className="text-sm text-muted-foreground">Membro dal 15/06/2023 • Ruolo: Perito</p>
                    </div>
                    <Badge variant="secondary">Attivo</Badge>
                  </div>
                  <Button variant="outline" className="w-full">
                    <Users className="w-4 h-4 mr-2" />
                    Visualizza Il Mio Studio
                  </Button>
                </CardContent>
              </Card>
              
              {/* Join Studio */}
              <Card>
                <CardHeader>
                  <h3 className="text-lg font-semibold">Unisciti ad uno Studio</h3>
                </CardHeader>
                <CardContent className="space-y-4">
                  <p className="text-sm text-muted-foreground">
                    Inserisci il codice invito per unirti ad uno studio professionale
                  </p>
                  <div className="flex gap-2">
                    <Input 
                      placeholder="Inserisci codice invito studio..." 
                      className="flex-1"
                    />
                    <Button>Unisciti</Button>
                  </div>
                </CardContent>
              </Card>
              
              {/* Create Studio */}
              <Card>
                <CardHeader>
                  <h3 className="text-lg font-semibold">Crea Nuovo Studio</h3>
                </CardHeader>
                <CardContent className="space-y-4">
                  <p className="text-sm text-muted-foreground">
                    Crea il tuo studio professionale e invita altri periti a collaborare
                  </p>
                  <Button variant="outline" className="w-full">
                    <Plus className="w-4 h-4 mr-2" />
                    Crea Nuovo Studio
                  </Button>
                </CardContent>
              </Card>
            </div>
          </TabsContent>
          
          <TabsContent value="reviews">
            <Card>
              <CardHeader>
                <h3 className="text-lg font-semibold">Recensioni</h3>
              </CardHeader>
              <CardContent>
                <p className="text-muted-foreground">Recensioni ricevute dai colleghi</p>
              </CardContent>
            </Card>
          </TabsContent>
        </Tabs>
      </div>
    </Layout>
  );
};