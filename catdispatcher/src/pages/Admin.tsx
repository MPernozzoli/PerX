import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { ArrowLeft, MapPin, Palette, Shield, UserCog, FileUp, Database, LogOut } from 'lucide-react';
import { toast } from 'sonner';
import { cn } from '@/lib/utils';
import GeoJSONUpload from '@/components/admin/GeoJSONUpload';
import BoundaryUpload from '@/components/admin/BoundaryUpload';
import CommuneManager from '@/components/admin/CommuneManager';
import CATManager from '@/components/admin/CATManager';
import CATImport from '@/components/admin/CATImport';
import { DiagnosticPanel } from '@/components/admin/DiagnosticPanel';
import { AdminDiagnosticRunner } from '@/components/admin/AdminDiagnosticRunner';
import { GeoJSONBackupManager } from '@/components/admin/GeoJSONBackupManager';
import RegionManager from '@/components/admin/RegionManager';
import { RegionFilter } from '@/components/RegionFilter';
import { Badge } from '@/components/ui/badge';
import UserRolesManager from '@/components/admin/UserRolesManager';
import { useQuery } from '@tanstack/react-query';
import { getMapKeysSession, clearMapKeysSession } from '@/lib/mapKeysSession';
import { deobfuscateMapData } from '@/lib/deobfuscateMapData';

const Admin = () => {
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [isAdmin, setIsAdmin] = useState(false);
  const [isSiteAdmin, setIsSiteAdmin] = useState(false);
  const [selectedRegions, setSelectedRegions] = useState<string[]>([]);
  const [userEmail, setUserEmail] = useState<string | null>(null);
  const [currentUserId, setCurrentUserId] = useState<string | null>(null);

  const { data: provinceCount = 0, refetch: refetchProvinces } = useQuery({
    queryKey: ['admin-provinces-count'],
    queryFn: async () => {
      const mapKeys = await getMapKeysSession();
      const body = mapKeys?.sessionKey ? { resource: 'provinces', sessionKey: mapKeys.sessionKey } : { resource: 'provinces' };
      const { data, error } = await supabase.functions.invoke('get-admin-data', {
        method: 'POST',
        body,
        headers: { Authorization: `Bearer ${(await supabase.auth.getSession()).data.session?.access_token ?? ''}` },
      });
      if (error || (data as { code?: string })?.code) {
        if ((data as { code?: string })?.code === 'NEED_MAP_KEYS') clearMapKeysSession();
        return 0;
      }
      const payload = mapKeys?.keys && data ? (deobfuscateMapData(data, mapKeys.keys) as { data: unknown[] }) : (data as { data: unknown[] });
      return Array.isArray(payload?.data) ? payload.data.length : 0;
    }
  });

  const { data: regionCount = 0, refetch: refetchRegions } = useQuery({
    queryKey: ['admin-regions-count'],
    queryFn: async () => {
      const mapKeys = await getMapKeysSession();
      const body = mapKeys?.sessionKey ? { resource: 'regions', sessionKey: mapKeys.sessionKey } : { resource: 'regions' };
      const { data, error } = await supabase.functions.invoke('get-admin-data', {
        method: 'POST',
        body,
        headers: { Authorization: `Bearer ${(await supabase.auth.getSession()).data.session?.access_token ?? ''}` },
      });
      if (error || (data as { code?: string })?.code) {
        if ((data as { code?: string })?.code === 'NEED_MAP_KEYS') clearMapKeysSession();
        return 0;
      }
      const payload = mapKeys?.keys && data ? (deobfuscateMapData(data, mapKeys.keys) as { data: unknown[] }) : (data as { data: unknown[] });
      return Array.isArray(payload?.data) ? payload.data.length : 0;
    }
  });

  const handleBoundaryRefresh = () => {
    refetchProvinces();
    refetchRegions();
  };

  useEffect(() => {
    checkAdminStatus();
  }, []);

  const checkAdminStatus = async () => {
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) {
        toast.error('Devi effettuare il login');
        navigate('/login');
        return;
      }
      setUserEmail(user.email || null);
      setCurrentUserId(user.id);

      const token = (await supabase.auth.getSession()).data.session?.access_token ?? '';
      const headers = { Authorization: `Bearer ${token}` };
      const mapKeys = await getMapKeysSession();
      let body: { resource: string; sessionKey?: string } = { resource: 'my_roles' };
      if (mapKeys?.sessionKey) body.sessionKey = mapKeys.sessionKey;

      let { data, error } = await supabase.functions.invoke('get-admin-data', {
        method: 'POST',
        body,
        headers,
      });

      let usedPlainResponse = false;
      if (error || (data as { code?: string })?.code === 'NEED_MAP_KEYS') {
        clearMapKeysSession();
        if (body.sessionKey) {
          const retry = await supabase.functions.invoke('get-admin-data', {
            method: 'POST',
            body: { resource: 'my_roles' },
            headers,
          });
          data = retry.data;
          error = retry.error;
          usedPlainResponse = true;
        }
      }

      if (error) {
        toast.error('Accesso negato: permessi insufficienti');
        navigate('/');
        return;
      }
      const payload = !usedPlainResponse && mapKeys?.keys && data && !(data as { code?: string })?.code
        ? (deobfuscateMapData(data, mapKeys.keys) as { data: { role: string }[] })
        : (data as { data: { role: string }[] });
      const roles = Array.isArray(payload?.data) ? payload.data : [];
      if (roles.length === 0) {
        toast.error('Accesso negato: permessi insufficienti');
        navigate('/');
        return;
      }
      const siteAdmin = roles.some((r) => r.role === 'site_admin');
      setIsAdmin(true);
      setIsSiteAdmin(siteAdmin);
      setLoading(false);
    } catch (error) {
      console.error('Error checking admin status:', error);
      navigate('/');
    }
  };

  const handleLogout = async () => {
    await supabase.auth.signOut();
    toast.success('Logout effettuato');
    navigate('/login');
  };

  type TabId = 'diagnostics' | 'communes' | 'cats' | 'cat-import' | 'upload' | 'access';
  const [activeTab, setActiveTab] = useState<TabId>('communes');
  useEffect(() => {
    if (isSiteAdmin && activeTab === 'communes') setActiveTab('diagnostics');
  }, [isSiteAdmin]);

  const allNavItems: { id: TabId; icon: React.ReactNode; label: string }[] = [
    { id: 'diagnostics', icon: <Shield className="h-4 w-4" />, label: 'Diagnostica' },
    { id: 'communes', icon: <MapPin className="h-4 w-4" />, label: 'Comuni' },
    { id: 'cats', icon: <Palette className="h-4 w-4" />, label: 'CAT' },
    { id: 'cat-import', icon: <Database className="h-4 w-4" />, label: 'CAT Import' },
    { id: 'upload', icon: <FileUp className="h-4 w-4" />, label: 'Comuni Import' },
    { id: 'access', icon: <UserCog className="h-4 w-4" />, label: 'Ruoli' },
  ];
  const navItems = isSiteAdmin
    ? allNavItems
    : allNavItems.filter((item) => !['diagnostics', 'cat-import', 'upload'].includes(item.id));

  if (loading) {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center">
        <div className="flex flex-col items-center gap-3">
          <div className="h-8 w-8 animate-spin rounded-full border-2 border-primary border-t-transparent" />
          <p className="text-sm text-muted-foreground">Verifica permessi...</p>
        </div>
      </div>
    );
  }

  if (!isAdmin) {
    return null;
  }

  return (
    <div className="min-h-screen bg-muted/30 flex">
      <AdminDiagnosticRunner />
      {/* Sidebar */}
      <aside className="w-56 shrink-0 border-r border-border bg-card flex flex-col">
        <div className="p-4 border-b border-border">
          <Button
            variant="ghost"
            size="sm"
            className="w-full justify-start text-muted-foreground hover:text-foreground"
            onClick={() => navigate('/')}
          >
            <ArrowLeft className="h-4 w-4 mr-2" />
            Mappa
          </Button>
        </div>
        <nav className="flex-1 p-2 space-y-1 overflow-y-auto">
          {navItems.map((item) => (
            <button
              key={item.id}
              onClick={() => setActiveTab(item.id)}
              className={cn(
                "w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-colors",
                activeTab === item.id
                  ? "bg-primary text-primary-foreground shadow-sm"
                  : "text-muted-foreground hover:bg-muted hover:text-foreground"
              )}
            >
              {item.icon}
              {item.label}
            </button>
          ))}
        </nav>
        <div className="p-3 border-t border-border">
          <div className="px-3 py-2 text-xs text-muted-foreground truncate" title={userEmail ?? ''}>
            {userEmail}
          </div>
          <Button
            variant="ghost"
            size="sm"
            className="w-full justify-start text-muted-foreground hover:text-destructive"
            onClick={handleLogout}
          >
            <LogOut className="h-4 w-4 mr-2" />
            Esci
          </Button>
        </div>
      </aside>

      {/* Main content */}
      <div className="flex-1 flex flex-col min-w-0">
        <header className="h-14 shrink-0 border-b border-border bg-card/80 backdrop-blur flex items-center px-6">
          <h1 className="text-lg font-semibold text-foreground">
            {navItems.find(n => n.id === activeTab)?.label ?? 'Admin'}
          </h1>
          <Badge variant="secondary" className="ml-3 text-xs">
            <Shield className="h-3 w-3 mr-1" />
            {isSiteAdmin ? 'Site Admin' : 'Admin'}
          </Badge>
        </header>

        <main className="flex-1 overflow-auto p-6">
          <div className="max-w-4xl space-y-6">
            {isSiteAdmin && activeTab === 'diagnostics' && (
              <>
                <RegionFilter selectedRegions={selectedRegions} onRegionsChange={setSelectedRegions} />
                <DiagnosticPanel selectedRegions={selectedRegions} />
                <RegionManager />
                <GeoJSONBackupManager />
              </>
            )}

            {activeTab === 'communes' && (
              <Card className="border shadow-sm">
                <div className="p-6">
                  <h2 className="text-lg font-semibold mb-1">Gestione Comuni</h2>
                  <p className="text-sm text-muted-foreground mb-6">
                    Visualizza e gestisci tutti i comuni caricati nel sistema.
                  </p>
                  <CommuneManager isSiteAdmin={isSiteAdmin} />
                </div>
              </Card>
            )}

            {activeTab === 'cats' && (
              <Card className="border shadow-sm">
                <div className="p-6">
                  <h2 className="text-lg font-semibold mb-1">Gestione CAT</h2>
                  <p className="text-sm text-muted-foreground mb-6">
                    Crea e modifica i Centri di Assistenza Territoriale (CAT).
                  </p>
                  <CATManager />
                </div>
              </Card>
            )}

            {isSiteAdmin && activeTab === 'cat-import' && (
              <Card className="border shadow-sm">
                <div className="p-6">
                  <h2 className="text-lg font-semibold mb-1">Importa Associazioni CAT-Comuni</h2>
                  <p className="text-sm text-muted-foreground mb-6">
                    Carica un file CSV. Colonne: comune, provincia, CAT 1, CAT 2, CAT 3, NOTE.
                  </p>
                  <CATImport />
                </div>
              </Card>
            )}

            {isSiteAdmin && activeTab === 'upload' && (
              <div className="space-y-6">
                <Card className="border shadow-sm">
                  <div className="p-6">
                    <h2 className="text-lg font-semibold mb-1">Importa Comuni da GeoJSON</h2>
                    <p className="text-sm text-muted-foreground mb-6">
                      FeatureCollection con geometrie MultiPolygon o Polygon.
                    </p>
                    <GeoJSONUpload />
                  </div>
                </Card>
                <BoundaryUpload
                  provinceCount={provinceCount}
                  regionCount={regionCount}
                  onRefresh={handleBoundaryRefresh}
                />
              </div>
            )}

            {activeTab === 'access' && (
              <Card className="border shadow-sm">
                <div className="p-6">
                  <h2 className="text-lg font-semibold mb-1 flex items-center gap-2">
                    <UserCog className="h-5 w-5" />
                    Gestione Ruoli Utenti
                  </h2>
                  <p className="text-sm text-muted-foreground mb-6">
                    Assegna ruoli admin o utente agli utenti del sistema.
                  </p>
                  <UserRolesManager isSiteAdmin={isSiteAdmin} currentUserId={currentUserId} />
                </div>
              </Card>
            )}
          </div>
        </main>
      </div>
    </div>
  );
};

export default Admin;
