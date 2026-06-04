import { ReactNode } from "react";
import { useNavigate, useLocation } from "react-router-dom";
import { Button } from "@perx/ui/components/ui/button";
import { Badge } from "@perx/ui/components/ui/badge";
import { 
  HomeIcon,
  PlusIcon,
  BookIcon,
  SettingsIcon,
  UserIcon,
  BookmarkIcon,
  Users,
  ChevronDownIcon,
  LogOutIcon
} from "lucide-react";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@perx/ui/components/ui/dropdown-menu";
import { cn } from "@/lib/utils";
import { useAuth } from "@/contexts/AuthContext";
import { useAuthModal } from "@/contexts/AuthModalContext";
import { useToast } from "@/hooks/use-toast";
import { useIsAdmin } from "@/hooks/useUserRoles";

interface LayoutProps {
  children: ReactNode;
  className?: string;
}

export const Layout = ({ children, className }: LayoutProps) => {
  const navigate = useNavigate();
  const location = useLocation();
  const { user, signOut } = useAuth();
  const { openModal } = useAuthModal();
  const { toast } = useToast();
  const isAdmin = useIsAdmin(user?.id);

  const handleSignOut = async () => {
    try {
      await signOut();
      toast({
        title: "Disconnesso",
        description: "Sei stato disconnesso con successo.",
      });
    } catch (error: any) {
      toast({
        title: "Errore",
        description: "Si è verificato un errore durante la disconnessione.",
        variant: "destructive",
      });
    }
  };
  return (
    <div className="min-h-screen bg-background">
      {/* Header */}
      <header className="sticky top-0 z-50 border-b bg-card/80 backdrop-blur-sm">
        <div className="container mx-auto px-4 h-16 flex items-center justify-between">
          <div className="flex items-center gap-6">
            <div className="flex items-center gap-2">
              <div 
                className="w-8 h-8 bg-primary rounded flex items-center justify-center cursor-pointer"
                onClick={() => navigate('/')}
              >
                <BookIcon className="h-5 w-5 text-primary-foreground" />
              </div>
              <h1 
                className="text-xl font-bold cursor-pointer" 
                onClick={() => navigate('/')}
              >
                Bignami Online
              </h1>
              <Badge variant="outline" className="text-xs">v1.0</Badge>
            </div>
            
        <nav className="hidden md:flex items-center gap-4">
          <Button 
            variant={location.pathname === '/' ? 'default' : 'ghost'} 
            size="sm" 
            className="gap-2"
            onClick={() => navigate('/')}
          >
            <HomeIcon className="h-4 w-4" />
            Home
          </Button>
          <Button 
            variant={location.pathname.startsWith('/studio/') ? 'default' : 'ghost'} 
            size="sm" 
            className="gap-2"
            onClick={() => navigate('/studio/1')} // TODO: Replace with actual user's studio ID
          >
            <Users className="h-4 w-4" />
            Studio
          </Button>
          {isAdmin && (
            <Button 
              variant={location.pathname === '/admin' ? 'default' : 'ghost'} 
              size="sm" 
              className="gap-2"
              onClick={() => navigate('/admin')}
            >
              <SettingsIcon className="h-4 w-4" />
              Admin
            </Button>
          )}
        </nav>
          </div>

          <div className="flex items-center gap-2">
            {user ? (
              <>
                <Button 
                  variant="outline" 
                  size="sm" 
                  className="gap-2"
                  onClick={() => navigate('/add-policy')}
                >
                  <PlusIcon className="h-4 w-4" />
                  <span className="hidden sm:inline">Aggiungi Polizza</span>
                </Button>
                
                <DropdownMenu>
                  <DropdownMenuTrigger asChild>
                    <Button 
                      variant="ghost" 
                      size="sm" 
                      className="gap-2"
                    >
                      <UserIcon className="h-4 w-4" />
                      <span className="hidden sm:inline">{user?.email?.split('@')[0] || 'Utente'}</span>
                      <ChevronDownIcon className="h-4 w-4" />
                    </Button>
                  </DropdownMenuTrigger>
                  <DropdownMenuContent align="end" className="w-48">
                    <DropdownMenuItem onClick={() => navigate('/profile')}>
                      <UserIcon className="h-4 w-4 mr-2" />
                      Profilo
                    </DropdownMenuItem>
                    <DropdownMenuItem onClick={() => navigate('/settings')}>
                      <SettingsIcon className="h-4 w-4 mr-2" />
                      Impostazioni
                    </DropdownMenuItem>
                    <DropdownMenuSeparator />
                    <DropdownMenuItem onClick={handleSignOut}>
                      <LogOutIcon className="h-4 w-4 mr-2" />
                      Disconnetti
                    </DropdownMenuItem>
                  </DropdownMenuContent>
                </DropdownMenu>
              </>
            ) : (
              <div className="flex items-center gap-2">
                <Button 
                  variant="outline" 
                  size="sm"
                  onClick={openModal}
                >
                  Accedi
                </Button>
                <Button 
                  size="sm"
                  onClick={openModal}
                >
                  Registrati
                </Button>
              </div>
            )}
          </div>
        </div>
      </header>

      {/* Breadcrumb */}
      <div className="border-b bg-muted/30">
        <div className="container mx-auto px-4 py-2">
          <div className="flex items-center gap-2 text-sm text-muted-foreground">
            <HomeIcon className="h-4 w-4" />
            <Button 
              variant="ghost" 
              size="sm" 
              className="h-auto p-0 text-sm text-muted-foreground hover:text-foreground"
              onClick={() => navigate('/')}
            >
              Home
            </Button>
            
            {location.pathname !== '/' && (
              <>
                <span>/</span>
                {location.pathname.includes('/policy/') && (
                  <span>Polizza</span>
                )}
              </>
            )}
          </div>
        </div>
      </div>

      {/* Main content */}
      <main className={cn("container mx-auto px-4 py-6", className)}>
        {children}
      </main>

      {/* Footer */}
      <footer className="border-t bg-muted/30 mt-auto">
        <div className="container mx-auto px-4 py-4">
          <div className="flex items-center justify-between text-sm text-muted-foreground">
            <div>© 2024 Bignami Online - Portale per Periti Property</div>
            <div className="flex items-center gap-4">
              <Badge variant="outline" className="text-xs">
                Beta
              </Badge>
            </div>
          </div>
        </div>
      </footer>
    </div>
  );
};