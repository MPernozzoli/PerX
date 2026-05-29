import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Layout } from "@/components/Layout";
import { Search, Plus, Users, MapPin, Calendar } from "lucide-react";
import { useState } from "react";
import { useNavigate } from "react-router-dom";

export const Studios = () => {
  const [searchQuery, setSearchQuery] = useState("");
  const navigate = useNavigate();
  
  // Mock data - in real app this would come from database
  const studios = [
    {
      id: "1",
      name: "Studio Legale Bianchi & Associati",
      description: "Studio specializzato in diritto assicurativo e responsabilità civile. Esperienza pluriennale nel settore.",
      created_at: "2023-06-15",
      location: "Milano, Italia",
      memberCount: 12,
      specializations: ["RC Auto", "Danni Domestici", "RC Professionale"],
      isPublic: true,
      avatar: ""
    },
    {
      id: "2", 
      name: "Periti Associati Roma",
      description: "Rete di periti esperti in valutazione danni per compagnie assicurative nazionali e internazionali.",
      created_at: "2023-03-20",
      location: "Roma, Italia",
      memberCount: 8,
      specializations: ["Fenomeni Elettrici", "Incendi", "Danni da Acqua"],
      isPublic: true,
      avatar: ""
    },
    {
      id: "3",
      name: "Studio Tecnico del Nord",
      description: "Consulenti tecnici specializzati in perizie industriali e commerciali.",
      created_at: "2023-09-10", 
      location: "Torino, Italia",
      memberCount: 5,
      specializations: ["RC Generale", "Danni Industriali"],
      isPublic: false,
      avatar: ""
    }
  ];

  const filteredStudios = studios.filter(studio =>
    studio.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
    studio.description.toLowerCase().includes(searchQuery.toLowerCase()) ||
    studio.specializations.some(spec => spec.toLowerCase().includes(searchQuery.toLowerCase()))
  );

  return (
    <Layout>
      <div className="container mx-auto px-4 py-8 max-w-6xl">
        {/* Header */}
        <div className="flex flex-col md:flex-row justify-between items-start md:items-center mb-8">
          <div>
            <h1 className="text-3xl font-bold mb-2">Studi Professionali</h1>
            <p className="text-muted-foreground">Scopri e unisciti agli studi di periti assicurativi</p>
          </div>
          <Button className="mt-4 md:mt-0">
            <Plus className="w-4 h-4 mr-2" />
            Crea Studio
          </Button>
        </div>

        {/* Search */}
        <div className="relative mb-8">
          <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-muted-foreground w-4 h-4" />
          <Input
            placeholder="Cerca studi per nome, descrizione o specializzazione..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="pl-10"
          />
        </div>

        {/* Studios Grid */}
        <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
          {filteredStudios.map((studio) => (
            <Card 
              key={studio.id} 
              className="cursor-pointer hover:shadow-lg transition-shadow"
              onClick={() => navigate(`/studio/${studio.id}`)}
            >
              <CardHeader className="pb-4">
                <div className="flex items-start space-x-3">
                  <Avatar className="w-12 h-12">
                    <AvatarImage src={studio.avatar} />
                    <AvatarFallback>
                      {studio.name.split(' ').map(n => n[0]).join('').substring(0, 2)}
                    </AvatarFallback>
                  </Avatar>
                  <div className="flex-1 min-w-0">
                    <CardTitle className="text-lg line-clamp-2">{studio.name}</CardTitle>
                    <div className="flex items-center text-sm text-muted-foreground mt-1">
                      <MapPin className="w-3 h-3 mr-1" />
                      {studio.location}
                    </div>
                  </div>
                </div>
              </CardHeader>
              
              <CardContent className="space-y-4">
                <p className="text-sm text-muted-foreground line-clamp-3">
                  {studio.description}
                </p>
                
                <div className="flex flex-wrap gap-1">
                  {studio.specializations.slice(0, 2).map((spec) => (
                    <Badge key={spec} variant="secondary" className="text-xs">
                      {spec}
                    </Badge>
                  ))}
                  {studio.specializations.length > 2 && (
                    <Badge variant="outline" className="text-xs">
                      +{studio.specializations.length - 2}
                    </Badge>
                  )}
                </div>
                
                <div className="flex items-center justify-between text-sm text-muted-foreground">
                  <div className="flex items-center">
                    <Users className="w-3 h-3 mr-1" />
                    {studio.memberCount} membri
                  </div>
                  <div className="flex items-center">
                    <Calendar className="w-3 h-3 mr-1" />
                    {new Date(studio.created_at).toLocaleDateString('it-IT', { 
                      year: 'numeric', 
                      month: 'short' 
                    })}
                  </div>
                </div>

                <div className="flex justify-between items-center pt-2">
                  <Badge variant={studio.isPublic ? "default" : "secondary"}>
                    {studio.isPublic ? "Pubblico" : "Privato"}
                  </Badge>
                  <Button variant="outline" size="sm" onClick={(e) => {
                    e.stopPropagation();
                    // Handle join studio
                  }}>
                    Unisciti
                  </Button>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>

        {filteredStudios.length === 0 && (
          <div className="text-center py-12">
            <Users className="w-12 h-12 mx-auto text-muted-foreground mb-4" />
            <h3 className="text-lg font-semibold mb-2">Nessuno studio trovato</h3>
            <p className="text-muted-foreground">
              Prova a modificare i tuoi criteri di ricerca o crea un nuovo studio.
            </p>
          </div>
        )}
      </div>
    </Layout>
  );
};