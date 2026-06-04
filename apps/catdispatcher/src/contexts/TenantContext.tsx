import { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import { supabase } from '@/integrations/supabase/client';

// Tipi
export type UserRole = 'site_admin' | 'tenant_admin' | 'user';

export interface Tenant {
  id: string;
  code: string;
  name: string;
  is_default: boolean;
  is_active: boolean;
}

export interface UserRoleInfo {
  role: UserRole;
  tenant_id: string | null;
  tenant_code: string | null;
}

interface TenantContextType {
  // Tenant corrente
  currentTenant: Tenant | null;
  setCurrentTenant: (tenant: Tenant) => void;
  
  // Lista tenant disponibili per l'utente
  availableTenants: Tenant[];
  
  // Ruoli utente
  userRoles: UserRoleInfo[];
  isSiteAdmin: boolean;
  isTenantAdmin: boolean;
  isUser: boolean;
  
  // Loading state
  loading: boolean;
  
  // Helper functions
  hasRole: (role: UserRole, tenantId?: string) => boolean;
  canManageTenant: (tenantId: string) => boolean;
  
  // Refresh
  refreshTenantData: () => Promise<void>;
}

const TenantContext = createContext<TenantContextType | undefined>(undefined);

export function TenantProvider({ children }: { children: ReactNode }) {
  const [currentTenant, setCurrentTenantState] = useState<Tenant | null>(null);
  const [availableTenants, setAvailableTenants] = useState<Tenant[]>([]);
  const [userRoles, setUserRoles] = useState<UserRoleInfo[]>([]);
  const [loading, setLoading] = useState(true);

  // Calcola i permessi
  const isSiteAdmin = userRoles.some(r => r.role === 'site_admin');
  const isTenantAdmin = userRoles.some(r => r.role === 'tenant_admin' || r.role === 'site_admin');
  const isUser = userRoles.length > 0;

  // Helper per verificare ruolo
  const hasRole = (role: UserRole, tenantId?: string): boolean => {
    if (role === 'site_admin') {
      return isSiteAdmin;
    }
    
    return userRoles.some(r => {
      if (r.role === 'site_admin') return true; // site_admin ha tutti i ruoli
      if (r.role !== role) return false;
      if (tenantId && r.tenant_id !== tenantId) return false;
      return true;
    });
  };

  // Helper per verificare se può gestire un tenant
  const canManageTenant = (tenantId: string): boolean => {
    if (isSiteAdmin) return true;
    return userRoles.some(r => r.role === 'tenant_admin' && r.tenant_id === tenantId);
  };

  // Imposta il tenant corrente e salva in localStorage
  const setCurrentTenant = (tenant: Tenant) => {
    setCurrentTenantState(tenant);
    localStorage.setItem('catDispatcher_currentTenantId', tenant.id);
  };

  // Carica i dati del tenant
  const refreshTenantData = async () => {
    setLoading(true);
    
    try {
      const { data: { user } } = await supabase.auth.getUser();
      
      if (!user) {
        setUserRoles([]);
        setAvailableTenants([]);
        setCurrentTenantState(null);
        return;
      }

      // Carica i ruoli dell'utente
      const { data: roles, error: rolesError } = await supabase
        .rpc('get_user_role', { check_user_id: user.id });

      if (rolesError) {
        console.error('Error fetching user roles:', rolesError);
      }
      
      // Mappa i ruoli al tipo corretto
      const mappedRoles: UserRoleInfo[] = (roles || []).map((r: { role: string; tenant_id: string; tenant_code: string }) => ({
        role: r.role as UserRole,
        tenant_id: r.tenant_id,
        tenant_code: r.tenant_code
      }));
      
      setUserRoles(mappedRoles);

      // Carica i tenant disponibili
      // Se è site_admin, mostra tutti i tenant
      // Altrimenti mostra solo i tenant a cui appartiene
      const isSiteAdminCheck = mappedRoles.some((r: UserRoleInfo) => r.role === 'site_admin');
      
      let tenantsQuery = supabase
        .from('tenants')
        .select('*')
        .eq('is_active', true);

      if (!isSiteAdminCheck) {
        // Filtra per tenant dell'utente
        const { data: userTenants } = await supabase
          .from('user_tenants')
          .select('tenant_id')
          .eq('user_id', user.id);
        
        const tenantIds = userTenants?.map(ut => ut.tenant_id) || [];
        
        // Aggiungi anche i tenant dai ruoli
        mappedRoles.forEach((r: UserRoleInfo) => {
          if (r.tenant_id && !tenantIds.includes(r.tenant_id)) {
            tenantIds.push(r.tenant_id);
          }
        });
        
        if (tenantIds.length > 0) {
          tenantsQuery = tenantsQuery.in('id', tenantIds);
        }
      }

      const { data: tenants, error: tenantsError } = await tenantsQuery.order('name');

      if (tenantsError) {
        console.error('Error fetching tenants:', tenantsError);
      } else {
        setAvailableTenants(tenants || []);
        
        // Imposta il tenant corrente
        const savedTenantId = localStorage.getItem('catDispatcher_currentTenantId');
        const savedTenant = tenants?.find(t => t.id === savedTenantId);
        
        if (savedTenant) {
          setCurrentTenantState(savedTenant);
        } else {
          // Usa il tenant default o il primo disponibile
          const defaultTenant = tenants?.find(t => t.is_default) || tenants?.[0];
          if (defaultTenant) {
            setCurrentTenantState(defaultTenant);
          }
        }
      }
    } catch (error) {
      console.error('Error loading tenant data:', error);
    } finally {
      setLoading(false);
    }
  };

  // Carica i dati all'avvio e quando cambia l'auth
  useEffect(() => {
    refreshTenantData();

    const { data: { subscription } } = supabase.auth.onAuthStateChange(() => {
      refreshTenantData();
    });

    return () => subscription.unsubscribe();
  }, []);

  return (
    <TenantContext.Provider
      value={{
        currentTenant,
        setCurrentTenant,
        availableTenants,
        userRoles,
        isSiteAdmin,
        isTenantAdmin,
        isUser,
        loading,
        hasRole,
        canManageTenant,
        refreshTenantData,
      }}
    >
      {children}
    </TenantContext.Provider>
  );
}

export function useTenant() {
  const context = useContext(TenantContext);
  if (context === undefined) {
    throw new Error('useTenant must be used within a TenantProvider');
  }
  return context;
}

export default TenantContext;
