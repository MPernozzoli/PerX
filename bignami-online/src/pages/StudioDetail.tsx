import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Layout } from "@/components/Layout";
import { useParams, useNavigate } from "react-router-dom";
import { Textarea } from "@/components/ui/textarea";
import { Input } from "@/components/ui/input";
import { Separator } from "@/components/ui/separator";
import { 
  Users, 
  MapPin, 
  Calendar, 
  Mail, 
  Phone, 
  UserPlus,
  Settings,
  Activity,
  MessageSquare,
  Heart,
  Send,
  Hash,
  MessageCircle,
  Copy,
  Plus,
  AtSign,
  MoreVertical,
  Crown,
  Shield,
  Lock,
  Unlock
} from "lucide-react";
import { useToast } from "@/hooks/use-toast";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

export const StudioDetail = () => {
  const { studioId } = useParams();
  const navigate = useNavigate();
  const { toast } = useToast();
  
  // Mock data - in real app this would be fetched based on studioId
  const studio = {
    id: studioId,
    name: "Studio Bignami",
    description: "Studio professionale per periti assicurativi specializzati in fenomeni elettrici con oltre 20 anni di esperienza nel settore.",
    created_at: "2023-06-15",
    location: "Via Roma 123, Milano, Italia",
    email: "info@studiobignami.it",
    phone: "+39 02 1234567",
    website: "www.studiobignami.it",
    memberCount: 12,
    specializations: ["Fenomeni Elettrici", "RC Auto", "Danni Domestici", "RC Professionale", "Incendi"],
    isPublic: true,
    avatar: "",
    isOwner: true, // Current user is owner/admin
    isMember: true // Current user is member
  };

  const currentUser = {
    id: "current-user",
    name: "Mario Rossi", 
    role: "admin" // Can be: admin, team_leader, moderator, member
  };

  const members = [
    { id: 1, name: "Mario Rossi", role: "admin", avatar: "", specialization: "Fenomeni Elettrici", joinDate: "2023-06-15" },
    { id: 2, name: "Giuseppe Verdi", role: "team_leader", avatar: "", specialization: "RC Auto", joinDate: "2023-07-20" },
    { id: 3, name: "Anna Bianchi", role: "moderator", avatar: "", specialization: "Danni Domestici", joinDate: "2023-08-10" },
    { id: 4, name: "Luca Ferrari", role: "member", avatar: "", specialization: "Incendi", joinDate: "2023-09-05" },
  ];

  // Mock posts data
  const posts = [
    {
      id: 1,
      author: { name: "Giuseppe Verdi", role: "team_leader" },
      avatar: "",
      content: "Ciao team! Ho appena completato la revisione delle polizze Generali per questo mese. Ottimo lavoro da parte di tutti! @Mario Rossi grazie per il supporto! #RCAuto #Successo 🎉",
      timestamp: "2 ore fa",
      likes: 5,
      isLocked: false,
      comments: [
        { id: 1, author: "Mario Rossi", avatar: "", content: "Ottimo lavoro Giuseppe! Sempre un piacere collaborare con te.", timestamp: "1 ora fa" },
        { id: 2, author: "Anna Bianchi", avatar: "", content: "Complimenti per il risultato! 👏", timestamp: "30 min fa" }
      ],
      liked: false
    },
    {
      id: 2,
      author: { name: "Anna Bianchi", role: "moderator" },
      avatar: "",
      content: "Reminder: le nuove linee guida per i report fotografici sono ora disponibili nella sezione documenti. Si prega di prenderne visione per i prossimi incarichi.",
      timestamp: "5 ore fa",
      likes: 3,
      isLocked: false,
      comments: [],
      liked: true
    },
    {
      id: 3,
      author: { name: "Mario Rossi", role: "admin" },
      avatar: "",
      content: "Meeting mensile programmato per venerdì alle 14:00. Agenda: nuovi protocolli Allianz e aggiornamenti normativi. @Tutti partecipazione obbligatoria.",
      timestamp: "1 giorno fa",
      likes: 7,
      isLocked: false,
      comments: [
        { id: 1, author: "Luca Ferrari", avatar: "", content: "Perfetto, sarò presente", timestamp: "1 giorno fa" }
      ],
      liked: false
    }
  ];

  const communicationTemplates = [
    {
      category: "Email Clienti",
      templates: [
        {
          title: "Richiesta documentazione iniziale",
          content: "Gentile Cliente, in riferimento al sinistro del [DATA], La preghiamo di inviare la seguente documentazione: - Denuncia di sinistro - Fotografie del danno - Preventivi di riparazione. Rimaniamo a disposizione per chiarimenti."
        },
        {
          title: "Comunicazione esito perizia positivo",
          content: "Gentile Cliente, siamo lieti di comunicarLe che la perizia tecnica effettuata ha dato esito positivo. L'importo riconosciuto è di € [IMPORTO]. La liquidazione seguirà nei tempi standard della compagnia."
        }
      ]
    },
    {
      category: "WhatsApp",
      templates: [
        {
          title: "Conferma appuntamento",
          content: "Buongiorno, Le confermiamo l'appuntamento per la perizia di domani alle ore [ORA] presso [INDIRIZZO]. Può contattarci al numero [NUMERO] per qualsiasi necessità."
        },
        {
          title: "Richiesta foto urgenti",
          content: "Buongiorno, per completare la perizia abbiamo bisogno di alcune foto aggiuntive del danno. Può inviarle su questo numero? Grazie"
        }
      ]
    },
    {
      category: "Interlocutorie Legali",
      templates: [
        {
          title: "Istanza di CTU",
          content: "Eccellenza, la scrivente parte, nell'interesse come sopra rappresentato, chiede che codesto Ecc.mo Tribunale voglia nominare un Consulente Tecnico d'Ufficio per..."
        },
        {
          title: "Richiesta di proroga termini",
          content: "Alla cortese attenzione del Tribunale di [CITTÀ], con la presente si chiede la concessione di una proroga di [GIORNI] giorni per il deposito della documentazione richiesta..."
        }
      ]
    }
  ];

  const getRoleLabel = (role: string) => {
    switch (role) {
      case "admin": return "Amministratore";
      case "team_leader": return "Capo Team";
      case "moderator": return "Moderatore";
      default: return "Membro";
    }
  };

  const getRoleIcon = (role: string) => {
    switch (role) {
      case "admin": return <Crown className="h-3 w-3" />;
      case "team_leader": return <Shield className="h-3 w-3" />;
      case "moderator": return <Users className="h-3 w-3" />;
      default: return null;
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

  const canModeratePost = (post: any) => {
    return currentUser.role === "admin" || 
           currentUser.role === "moderator" || 
           post.author.name === currentUser.name;
  };

  const canAccessSettings = () => {
    return currentUser.role === "admin";
  };

  const togglePostLock = (postId: string) => {
    // In real implementation, this would update Supabase
    toast({
      title: "Post aggiornato",
      description: "Lo stato di blocco del post è stato modificato."
    });
  };

  const copyTemplate = (text: string) => {
    navigator.clipboard.writeText(text);
    toast({
      title: "Copiato!",
      description: "Il template è stato copiato negli appunti."
    });
  };

  return (
    <Layout>
      <div className="container mx-auto px-4 py-8 max-w-6xl">
        {/* Studio Header */}
        <Card className="mb-8">
          <CardContent className="pt-6">
            <div className="flex flex-col md:flex-row gap-6">
              <div className="flex flex-col items-center md:items-start">
                <Avatar className="w-32 h-32">
                  <AvatarImage src={studio.avatar} />
                  <AvatarFallback className="text-2xl">
                    {studio.name.split(' ').map(n => n[0]).join('').substring(0, 2)}
                  </AvatarFallback>
                </Avatar>
                
                <div className="flex gap-2 mt-4">
                  {!studio.isMember && (
                    <Button className="w-full">
                      <UserPlus className="w-4 h-4 mr-2" />
                      Unisciti
                    </Button>
                  )}
                  {canAccessSettings() && (
                    <Button 
                      variant="outline" 
                      size="icon"
                      onClick={() => navigate(`/studio/${studioId}/settings`)}
                    >
                      <Settings className="w-4 h-4" />
                    </Button>
                  )}
                </div>
              </div>
              
              <div className="flex-1 space-y-4">
                <div>
                  <div className="flex items-center gap-2 mb-2">
                    <h1 className="text-3xl font-bold">{studio.name}</h1>
                    <Badge variant={studio.isPublic ? "default" : "secondary"}>
                      {studio.isPublic ? "Pubblico" : "Privato"}
                    </Badge>
                  </div>
                  
                  <div className="space-y-1 text-muted-foreground">
                    <p className="flex items-center">
                      <MapPin className="w-4 h-4 mr-2" />
                      {studio.location}
                    </p>
                    <p className="flex items-center">
                      <Mail className="w-4 h-4 mr-2" />
                      {studio.email}
                    </p>
                    <p className="flex items-center">
                      <Phone className="w-4 h-4 mr-2" />
                      {studio.phone}
                    </p>
                    <p className="flex items-center">
                      <Calendar className="w-4 h-4 mr-2" />
                      Fondato il {new Date(studio.created_at).toLocaleDateString('it-IT')}
                    </p>
                  </div>
                </div>
                
                <p className="text-sm">{studio.description}</p>
                
                <div className="flex flex-wrap gap-2">
                  {studio.specializations.map((spec) => (
                    <Badge key={spec} variant="secondary">
                      {spec}
                    </Badge>
                  ))}
                </div>
                
                <div className="flex items-center gap-6 pt-2">
                  <div className="flex items-center text-sm text-muted-foreground">
                    <Users className="w-4 h-4 mr-1" />
                    {studio.memberCount} membri
                  </div>
                  <div className="flex items-center text-sm text-muted-foreground">
                    <Activity className="w-4 h-4 mr-1" />
                    {posts.length} post questa settimana
                  </div>
                  <div className="flex items-center text-sm text-muted-foreground">
                    <MessageSquare className="w-4 h-4 mr-1" />
                    24 discussioni attive
                  </div>
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* Check if user is member */}
        {!studio.isMember ? (
          <Card>
            <CardContent className="pt-6 text-center">
              <h2 className="text-2xl font-semibold mb-4">Accesso Riservato</h2>
              <p className="text-muted-foreground mb-6">
                Questa sezione è riservata ai membri dello studio. Unisciti per accedere alla bacheca e agli strumenti di comunicazione.
              </p>
              <Button>
                <UserPlus className="w-4 h-4 mr-2" />
                Richiedi di Unirti
              </Button>
            </CardContent>
          </Card>
        ) : (
          /* Tabs */
          <Tabs defaultValue="feed" className="space-y-6">
            <TabsList className="grid w-full grid-cols-3">
              <TabsTrigger value="feed">Bacheca</TabsTrigger>
              <TabsTrigger value="templates">Format Comunicativi</TabsTrigger>
              <TabsTrigger value="members">Membri ({members.length})</TabsTrigger>
            </TabsList>

            {/* Feed Tab */}
            <TabsContent value="feed" className="space-y-6">
              {/* New Post */}
              <Card>
                <CardContent className="pt-6">
                  <div className="flex space-x-3">
                    <Avatar className="w-10 h-10">
                      <AvatarImage src="" />
                      <AvatarFallback>MB</AvatarFallback>
                    </Avatar>
                    <div className="flex-1 space-y-3">
                      <Textarea 
                        placeholder="Condividi un aggiornamento con il team... Usa @ per taggare qualcuno"
                        className="min-h-20 resize-none"
                      />
                      <div className="flex justify-between items-center">
                        <div className="flex gap-2">
                          <Button variant="ghost" size="sm">
                            <Hash className="w-4 h-4 mr-1" />
                            Tag
                          </Button>
                          <Button variant="ghost" size="sm">
                            <AtSign className="w-4 h-4 mr-1" />
                            Menziona
                          </Button>
                        </div>
                        <Button>
                          <Send className="w-4 h-4 mr-2" />
                          Pubblica
                        </Button>
                      </div>
                    </div>
                  </div>
                </CardContent>
              </Card>

              {/* Posts Feed */}
              <div className="space-y-4">
                {posts.map((post) => (
                  <Card key={post.id}>
                    <CardContent className="pt-6">
                      {/* Post Header */}
                      <div className="flex space-x-3 mb-4">
                        <Avatar className="w-10 h-10">
                          <AvatarImage src={post.avatar} />
                          <AvatarFallback>
                            {post.author.name.split(' ').map(n => n[0]).join('')}
                          </AvatarFallback>
                        </Avatar>
                        <div className="flex-1">
                          <div className="flex items-center gap-2">
                            <p className="font-semibold">{post.author.name}</p>
                            <Badge variant={getRoleBadgeVariant(post.author.role)} className="text-xs gap-1">
                              {getRoleIcon(post.author.role)}
                              {getRoleLabel(post.author.role)}
                            </Badge>
                            {post.isLocked && (
                              <Lock className="h-3 w-3 text-muted-foreground" />
                            )}
                          </div>
                          <p className="text-sm text-muted-foreground">{post.timestamp}</p>
                        </div>
                        
                        {canModeratePost(post) && (
                          <DropdownMenu>
                            <DropdownMenuTrigger asChild>
                              <Button variant="ghost" size="sm">
                                <MoreVertical className="h-4 w-4" />
                              </Button>
                            </DropdownMenuTrigger>
                            <DropdownMenuContent>
                              <DropdownMenuItem onClick={() => togglePostLock(post.id.toString())}>
                                {post.isLocked ? (
                                  <>
                                    <Unlock className="h-4 w-4 mr-2" />
                                    Sblocca commenti
                                  </>
                                ) : (
                                  <>
                                    <Lock className="h-4 w-4 mr-2" />
                                    Blocca commenti
                                  </>
                                )}
                              </DropdownMenuItem>
                              <DropdownMenuItem className="text-destructive">
                                Elimina post
                              </DropdownMenuItem>
                            </DropdownMenuContent>
                          </DropdownMenu>
                        )}
                      </div>
                      
                      {/* Post Content */}
                      <div className="mb-4">
                        <p className="text-sm whitespace-pre-wrap">{post.content}</p>
                      </div>
                      
                      {/* Post Actions */}
                      <div className="flex items-center gap-4 pb-4">
                        <Button 
                          variant="ghost" 
                          size="sm" 
                          className={`gap-2 ${post.liked ? 'text-red-500' : ''}`}
                        >
                          <Heart className={`w-4 h-4 ${post.liked ? 'fill-current' : ''}`} />
                          {post.likes}
                        </Button>
                        <Button variant="ghost" size="sm" className="gap-2" disabled={post.isLocked}>
                          <MessageCircle className="w-4 h-4" />
                          {post.comments.length}
                          {post.isLocked && <Lock className="h-3 w-3 ml-1" />}
                        </Button>
                      </div>
                      
                      {/* Comments */}
                      {post.comments.length > 0 && (
                        <>
                          <Separator className="mb-4" />
                          <div className="space-y-3">
                            {post.comments.map((comment) => (
                              <div key={comment.id} className="flex space-x-3">
                                <Avatar className="w-8 h-8">
                                  <AvatarImage src={comment.avatar} />
                                  <AvatarFallback className="text-xs">
                                    {comment.author.split(' ').map(n => n[0]).join('')}
                                  </AvatarFallback>
                                </Avatar>
                                <div className="flex-1 bg-muted rounded-lg p-3">
                                  <p className="font-semibold text-sm">{comment.author}</p>
                                  <p className="text-sm">{comment.content}</p>
                                  <p className="text-xs text-muted-foreground mt-1">{comment.timestamp}</p>
                                </div>
                              </div>
                            ))}
                          </div>
                        </>
                      )}
                      
                      {/* Add Comment */}
                      <Separator className="my-4" />
                      <div className="flex space-x-3">
                        <Avatar className="w-8 h-8">
                          <AvatarImage src="" />
                          <AvatarFallback className="text-xs">MR</AvatarFallback>
                        </Avatar>
                        <div className="flex-1 flex gap-2">
                          <Input 
                            placeholder={post.isLocked ? "Commenti bloccati" : "Scrivi un commento..."} 
                            className="flex-1" 
                            disabled={post.isLocked}
                          />
                          <Button size="sm" disabled={post.isLocked}>
                            <Send className="w-4 h-4" />
                          </Button>
                        </div>
                      </div>
                    </CardContent>
                  </Card>
                ))}
              </div>
            </TabsContent>

            {/* Templates Tab */}
            <TabsContent value="templates" className="space-y-6">
              <Card>
                <CardHeader>
                  <CardTitle>Format Comunicativi</CardTitle>
                  <p className="text-sm text-muted-foreground">
                    Frasi preimpostate per email, messaggi WhatsApp e documenti legali
                  </p>
                </CardHeader>
              </Card>
              
              <div className="space-y-6">
                {communicationTemplates.map((category, idx) => (
                  <Card key={idx}>
                    <CardHeader>
                      <CardTitle className="text-lg">{category.category}</CardTitle>
                    </CardHeader>
                    <CardContent className="space-y-4">
                      {category.templates.map((template, templateIdx) => (
                        <div key={templateIdx} className="border rounded-lg p-4 space-y-3">
                          <div className="flex items-center justify-between">
                            <h4 className="font-medium">{template.title}</h4>
                            <Button variant="outline" size="sm" onClick={() => copyTemplate(template.content)}>
                              <Copy className="w-4 h-4 mr-2" />
                              Copia
                            </Button>
                          </div>
                          <p className="text-sm text-muted-foreground bg-muted/50 p-3 rounded">
                            {template.content}
                          </p>
                        </div>
                      ))}
                      <Button variant="outline" className="w-full">
                        <Plus className="w-4 h-4 mr-2" />
                        Aggiungi Nuovo Template
                      </Button>
                    </CardContent>
                  </Card>
                ))}
              </div>
            </TabsContent>
            
            {/* Members Tab */}
            <TabsContent value="members">
              <Card>
                <CardHeader>
                  <CardTitle>Membri dello Studio</CardTitle>
                </CardHeader>
                <CardContent>
                  <div className="space-y-4">
                    {members.map((member) => (
                      <div key={member.id} className="flex items-center justify-between p-4 border rounded-lg">
                        <div className="flex items-center space-x-3">
                          <Avatar className="w-12 h-12">
                            <AvatarImage src={member.avatar} />
                            <AvatarFallback>
                              {member.name.split(' ').map(n => n[0]).join('')}
                            </AvatarFallback>
                          </Avatar>
                          <div>
                            <p className="font-medium">{member.name}</p>
                            <p className="text-sm text-muted-foreground">{member.specialization}</p>
                            <p className="text-xs text-muted-foreground">
                              Membro dal {new Date(member.joinDate).toLocaleDateString('it-IT')}
                            </p>
                          </div>
                        </div>
                        <div className="flex items-center gap-2">
                          <Badge variant={member.role === 'admin' ? 'default' : 'secondary'}>
                            {member.role === 'admin' ? 'Amministratore' : 'Membro'}
                          </Badge>
                          <Button variant="outline" size="sm">Profilo</Button>
                          <Button variant="outline" size="sm">
                            <MessageSquare className="w-4 h-4" />
                          </Button>
                        </div>
                      </div>
                    ))}
                  </div>
                </CardContent>
              </Card>
            </TabsContent>
          </Tabs>
        )}
      </div>
    </Layout>
  );
};