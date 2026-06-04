import { useState, useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Card } from '@/components/ui/card';
import { toast } from 'sonner';
import { Trash2, Plus, Globe, Building2 } from 'lucide-react';
import { useTenant } from '@/contexts/TenantContext';
import { Badge } from '@/components/ui/badge';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';

interface AllowedDomain {
  id: string;
  domain: string;
  tenant_id: string;
  default_role: string;
  is_active: boolean;
  notes: string | null;
  created_at: string;
  tenant?: {
    code: string;
    name: string;
  };
}

const AllowedDomainsManager = () => {
  const { availableTenants, isSiteAdmin } = useTenant();
  const [domains, setDomains] = useState<AllowedDomain[]>([]);
  const [newDomain, setNewDomain] = useState('');
  const [selectedTenantId, setSelectedTenantId] = useState('');
  const [defaultRole, setDefaultRole] = useState('user');
  const [notes, setNotes] = useState('');
  const [loading, setLoading] = useState(false);

  const fetchDomains = async () => {
    const { data, error } = await supabase
      .from('allowed_domains')
      .select(`
        *,
        tenant:tenants(code, name)
      `)
      .order('domain') as any;

    if (error) {
      toast.error('Errore nel caricamento dei domini');
      return;
    }

    setDomains(data || []);
  };

  useEffect(() => {
    if (isSiteAdmin) {
      fetchDomains();
    }
  }, [isSiteAdmin]);

  useEffect(() => {
    if (availableTenants.length > 0 && !selectedTenantId) {
      setSelectedTenantId(availableTenants[0].id);
    }
  }, [availableTenants]);

  const handleAdd = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newDomain.trim() || !selectedTenantId) return;

    setLoading(true);
    
    // Pulisci il dominio (rimuovi @ se presente)
    const cleanDomain = newDomain.toLowerCase().trim().replace('@', '');
    
    const { error } = await (supabase
      .from('allowed_domains') as any)
      .insert({ 
        domain: cleanDomain,
        tenant_id: selectedTenantId,
        default_role: defaultRole,
        notes: notes.trim() || null,
        is_active: true
      });

    if (error) {
      if (error.code === '23505') {
        toast.error('Dominio già presente per questo tenant');
      } else {
        toast.error('Errore nell\'aggiunta del dominio');
      }
    } else {
      toast.success(`Dominio @${cleanDomain} aggiunto con successo`);
      setNewDomain('');
      setNotes('');
      fetchDomains();
    }
    setLoading(false);
  };

  const handleDelete = async (id: string, domain: string) => {
    if (!confirm(`Rimuovere @${domain} dalla lista?`)) return;

    const { error } = await (supabase
      .from('allowed_domains') as any)
      .delete()
      .eq('id', id);

    if (error) {
      toast.error('Errore nella rimozione');
    } else {
      toast.success('Dominio rimosso');
      fetchDomains();
    }
  };

  const handleToggleActive = async (id: string, currentActive: boolean) => {
    const { error } = await (supabase
      .from('allowed_domains') as any)
      .update({ is_active: !currentActive })
      .eq('id', id);

    if (error) {
      toast.error('Errore nell\'aggiornamento');
    } else {
      fetchDomains();
    }
  };

  if (!isSiteAdmin) {
    return (
      <Card className="p-6">
        <p className="text-muted-foreground">
          Solo i Site Admin possono gestire i domini autorizzati.
        </p>
      </Card>
    );
  }

  return (
    <Card className="p-6">
      <h2 className="text-xl font-semibold mb-4 flex items-center gap-2">
        <Globe className="h-5 w-5" />
        Domini Autorizzati
      </h2>
      <p className="text-sm text-muted-foreground mb-4">
        Gli utenti con email di questi domini possono accedere automaticamente
        senza bisogno di invito. Verranno assegnati al tenant e ruolo specificati.
      </p>
      
      <form onSubmit={handleAdd} className="flex flex-wrap gap-2 mb-6">
        <div className="flex items-center gap-1">
          <span className="text-muted-foreground">@</span>
          <Input
            type="text"
            placeholder="dominio.it"
            value={newDomain}
            onChange={(e) => setNewDomain(e.target.value)}
            required
            className="w-40"
          />
        </div>
        
        <Select value={selectedTenantId} onValueChange={setSelectedTenantId}>
          <SelectTrigger className="w-40">
            <SelectValue placeholder="Tenant" />
          </SelectTrigger>
          <SelectContent>
            {availableTenants.map((tenant) => (
              <SelectItem key={tenant.id} value={tenant.id}>
                {tenant.name}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        
        <Select value={defaultRole} onValueChange={setDefaultRole}>
          <SelectTrigger className="w-36">
            <SelectValue placeholder="Ruolo" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="user">User</SelectItem>
            <SelectItem value="tenant_admin">Tenant Admin</SelectItem>
          </SelectContent>
        </Select>
        
        <Input
          type="text"
          placeholder="Note (opzionale)"
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
          className="w-48"
        />
        
        <Button type="submit" disabled={loading}>
          <Plus className="h-4 w-4 mr-1" />
          Aggiungi
        </Button>
      </form>

      <div className="space-y-2 max-h-96 overflow-y-auto">
        {domains.length === 0 ? (
          <p className="text-muted-foreground text-center py-4">
            Nessun dominio autorizzato. Aggiungi un dominio per permettere l'accesso automatico.
          </p>
        ) : (
          domains.map((item) => (
            <div
              key={item.id}
              className={`flex items-center justify-between p-3 rounded-lg ${
                item.is_active ? 'bg-muted/50' : 'bg-muted/20 opacity-60'
              }`}
            >
              <div className="flex-1">
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="font-medium">@{item.domain}</span>
                  {item.tenant && (
                    <Badge variant="secondary" className="text-xs">
                      <Building2 className="h-3 w-3 mr-1" />
                      {item.tenant.code}
                    </Badge>
                  )}
                  <Badge 
                    variant={item.default_role === 'tenant_admin' ? 'default' : 'outline'}
                    className="text-xs"
                  >
                    {item.default_role}
                  </Badge>
                  {!item.is_active && (
                    <Badge variant="destructive" className="text-xs">
                      Disattivo
                    </Badge>
                  )}
                </div>
                {item.notes && (
                  <span className="text-sm text-muted-foreground">
                    {item.notes}
                  </span>
                )}
              </div>
              <div className="flex gap-1">
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => handleToggleActive(item.id, item.is_active)}
                  title={item.is_active ? 'Disattiva' : 'Attiva'}
                >
                  {item.is_active ? '🟢' : '🔴'}
                </Button>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => handleDelete(item.id, item.domain)}
                >
                  <Trash2 className="h-4 w-4 text-destructive" />
                </Button>
              </div>
            </div>
          ))
        )}
      </div>
    </Card>
  );
};

export default AllowedDomainsManager;
