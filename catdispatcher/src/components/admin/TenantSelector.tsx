import { useTenant } from '@/contexts/TenantContext';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import { Building2 } from 'lucide-react';

interface TenantSelectorProps {
  className?: string;
}

export function TenantSelector({ className }: TenantSelectorProps) {
  const { currentTenant, setCurrentTenant, availableTenants, isSiteAdmin, loading } = useTenant();

  // Se c'è solo un tenant, non mostrare il selettore
  if (availableTenants.length <= 1 && !isSiteAdmin) {
    return null;
  }

  if (loading) {
    return (
      <div className={`flex items-center gap-2 text-muted-foreground ${className}`}>
        <Building2 className="h-4 w-4" />
        <span className="text-sm">Caricamento...</span>
      </div>
    );
  }

  return (
    <div className={`flex items-center gap-2 ${className}`}>
      <Building2 className="h-4 w-4 text-muted-foreground" />
      <Select
        value={currentTenant?.id || ''}
        onValueChange={(value) => {
          const tenant = availableTenants.find(t => t.id === value);
          if (tenant) {
            setCurrentTenant(tenant);
          }
        }}
      >
        <SelectTrigger className="w-[180px] h-9">
          <SelectValue placeholder="Seleziona tenant" />
        </SelectTrigger>
        <SelectContent>
          {availableTenants.map((tenant) => (
            <SelectItem key={tenant.id} value={tenant.id}>
              <div className="flex items-center gap-2">
                <span>{tenant.name}</span>
                {tenant.is_default && (
                  <span className="text-xs text-muted-foreground">(default)</span>
                )}
              </div>
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
    </div>
  );
}

export default TenantSelector;
