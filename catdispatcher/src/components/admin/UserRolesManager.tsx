import { useState, useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { toast } from 'sonner';
import { Shield, User, Loader2, RefreshCw, Ban, Circle, CircleOff, MoreHorizontal, LogOut, UserX } from 'lucide-react';
import { getMapKeysSession, clearMapKeysSession } from '@/lib/mapKeysSession';
import { deobfuscateMapData } from '@/lib/deobfuscateMapData';

interface UserWithRole {
  user_id: string;
  role: string;
  email: string | null;
  last_sign_in_at?: string | null;
  last_activity?: string | null;
  is_online?: boolean;
}

function formatLastAccess(iso: string | null | undefined): string {
  if (!iso) return '—';
  try {
    const d = new Date(iso);
    return new Intl.DateTimeFormat('it-IT', {
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    }).format(d);
  } catch {
    return '—';
  }
}

interface UserRolesManagerProps {
  isSiteAdmin?: boolean;
  currentUserId?: string | null;
}

const UserRolesManager = ({ isSiteAdmin = false, currentUserId = null }: UserRolesManagerProps) => {
  const [users, setUsers] = useState<UserWithRole[]>([]);
  const [loading, setLoading] = useState(true);
  const [updating, setUpdating] = useState<string | null>(null);
  const [actioning, setActioning] = useState<string | null>(null);
  const [deleteConfirm, setDeleteConfirm] = useState<UserWithRole | null>(null);

  useEffect(() => {
    fetchUsers();
  }, []);

  const fetchUsers = async (retryCount = 0) => {
    setLoading(true);
    try {
      const { data: sessionData } = await supabase.auth.getSession();
      const token = sessionData?.session?.access_token;
      if (!token) {
        toast.error('Devi effettuare l\'accesso per vedere gli utenti');
        setLoading(false);
        return;
      }
      const mapKeys = await getMapKeysSession();
      const body = mapKeys?.sessionKey ? { sessionKey: mapKeys.sessionKey } : {};
      const { data, error } = await supabase.functions.invoke('get-users-with-emails', {
        method: 'POST',
        body,
        headers: { Authorization: `Bearer ${token}` },
      });

      if (error) {
        const isNetworkFailure = /failed to send a request|edge function|network/i.test(error.message);
        const msg = (data as { error?: string } | null)?.error ?? error.message ?? 'Errore nel caricamento utenti';
        if (isNetworkFailure && retryCount < 1) {
          await new Promise((r) => setTimeout(r, 1500));
          return fetchUsers(retryCount + 1);
        }
        if (isNetworkFailure) {
          toast.error(
            'Impossibile contattare il server. Verifica che l\'Edge Function "get-users-with-emails" sia deployata (supabase functions deploy get-users-with-emails) e la connessione.'
          );
        } else {
          toast.error(msg);
        }
        setUsers([]);
        return;
      }
      if ((data as { code?: string })?.code === 'NEED_MAP_KEYS') {
        clearMapKeysSession();
        if (retryCount < 1) return fetchUsers(retryCount + 1);
        setUsers([]);
        return;
      }
      const decoded = mapKeys?.keys && Array.isArray(data)
        ? (deobfuscateMapData(data, mapKeys.keys) as UserWithRole[])
        : (Array.isArray(data) ? data : []) as UserWithRole[];
      setUsers(decoded);
    } catch (err) {
      console.error('Error fetching users:', err);
      toast.error('Errore nel caricamento utenti');
    } finally {
      setLoading(false);
    }
  };

  const updateUserRole = async (userId: string, newRole: string) => {
    setUpdating(userId);
    try {
      const { data: updated, error: updateError } = await supabase
        .from('user_roles')
        .update({ role: newRole })
        .eq('user_id', userId)
        .select('user_id');

      if (updateError) throw updateError;

      if (updated && updated.length > 0) {
        toast.success('Ruolo aggiornato');
        setUsers(prev => prev.map(u => 
          u.user_id === userId ? { ...u, role: newRole } : u
        ));
        return;
      }

      const { error: insertError } = await supabase
        .from('user_roles')
        .insert({ user_id: userId, role: newRole });

      if (insertError) throw insertError;

      toast.success('Ruolo aggiornato');
      setUsers(prev => prev.map(u => 
        u.user_id === userId ? { ...u, role: newRole } : u
      ));
    } catch (error: unknown) {
      console.error('Error updating role:', error);
      const msg = error && typeof error === 'object' && 'message' in error
        ? String((error as { message: string }).message)
        : 'Errore nell\'aggiornamento';
      toast.error(msg);
    } finally {
      setUpdating(null);
    }
  };

  const revokeSessions = async (userId: string) => {
    setActioning(userId);
    try {
      const { data: sessionData } = await supabase.auth.getSession();
      const token = sessionData?.session?.access_token;
      if (!token) {
        toast.error('Sessione scaduta');
        return;
      }
      const { data, error } = await supabase.functions.invoke('revoke-user-sessions', {
        headers: { Authorization: `Bearer ${token}` },
        body: { user_id: userId },
      });
      if (error) throw error;
      const err = (data as { error?: string })?.error;
      if (err) throw new Error(err);
      toast.success('Sessioni revocate. L\'utente dovrà riaccedere.');
      fetchUsers();
    } catch (e) {
      console.error(e);
      toast.error((e as Error)?.message ?? 'Errore revoca sessioni');
    } finally {
      setActioning(null);
    }
  };

  const deleteUser = async (userId: string) => {
    setDeleteConfirm(null);
    setActioning(userId);
    try {
      const { data: sessionData } = await supabase.auth.getSession();
      const token = sessionData?.session?.access_token;
      if (!token) {
        toast.error('Sessione scaduta');
        return;
      }
      const { data, error } = await supabase.functions.invoke('admin-delete-user', {
        headers: { Authorization: `Bearer ${token}` },
        body: { user_id: userId },
      });
      if (error) throw error;
      const err = (data as { error?: string })?.error;
      if (err) throw new Error(err);
      toast.success('Utente rimosso dalla lista.');
      setUsers(prev => prev.filter(u => u.user_id !== userId));
    } catch (e) {
      console.error(e);
      toast.error((e as Error)?.message ?? 'Errore rimozione utente');
    } finally {
      setActioning(null);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-8">
        <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex justify-between items-center">
        <p className="text-sm text-muted-foreground">
           Utenti connessi. Gestisci ruoli: Admin, Utente, Bloccato.
        </p>
        <Button variant="outline" size="sm" onClick={() => fetchUsers()}>
          <RefreshCw className="h-4 w-4 mr-2" />
          Aggiorna
        </Button>
      </div>

      {users.length === 0 ? (
        <div className="text-center py-8 text-muted-foreground">
          Nessun utente trovato
        </div>
      ) : (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Email</TableHead>
              <TableHead>Ruolo</TableHead>
              {isSiteAdmin && (
                <>
                  <TableHead>Ultimo accesso</TableHead>
                  <TableHead>Stato</TableHead>
                </>
              )}
              <TableHead>Modifica</TableHead>
              <TableHead className="w-10">Azioni</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {users.map((user) => (
              <TableRow key={user.user_id}>
                <TableCell>
                  <div className="flex items-center gap-2">
                    {user.role === 'site_admin'
                      ? <Shield className="h-4 w-4 text-amber-600 shrink-0" />
                      : user.role === 'admin'
                        ? <Shield className="h-4 w-4 text-purple-500 shrink-0" />
                        : user.role === 'blocked'
                          ? <Ban className="h-4 w-4 text-red-500 shrink-0" />
                          : <User className="h-4 w-4 text-gray-500 shrink-0" />
                    }
                    <span className="text-sm">
                      {user.email ?? user.user_id.slice(0, 12) + '...'}
                    </span>
                  </div>
                </TableCell>
                <TableCell>
                  {user.role === 'site_admin'
                    ? <Badge className="bg-amber-100 text-amber-800">Site Admin</Badge>
                    : user.role === 'admin'
                      ? <Badge className="bg-purple-100 text-purple-800">Admin</Badge>
                      : user.role === 'blocked'
                        ? <span className="text-sm text-red-600">Bloccato</span>
                        : <Badge variant="secondary">Utente</Badge>
                  }
                </TableCell>
                {isSiteAdmin && (
                  <>
                    <TableCell className="text-sm text-muted-foreground whitespace-nowrap">
                      {formatLastAccess(user.last_sign_in_at)}
                    </TableCell>
                    <TableCell>
                      {user.is_online ? (
                        <span className="inline-flex items-center gap-1.5 text-sm text-green-600">
                          <Circle className="h-3 w-3 fill-current" />
                          Connesso
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1.5 text-sm text-muted-foreground">
                          <CircleOff className="h-3 w-3" />
                          {user.last_activity ? formatLastAccess(user.last_activity) : 'Non connesso'}
                        </span>
                      )}
                    </TableCell>
                  </>
                )}
                <TableCell>
                  {user.role === 'site_admin' ? (
                    <span className="text-sm text-muted-foreground">—</span>
                  ) : (
                    <Select
                      value={user.role}
                      onValueChange={(value) => updateUserRole(user.user_id, value)}
                      disabled={updating === user.user_id}
                    >
                      <SelectTrigger className="w-28">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="admin">Admin</SelectItem>
                        <SelectItem value="user">Utente</SelectItem>
                        <SelectItem value="blocked" className="text-red-600">Bloccato</SelectItem>
                      </SelectContent>
                    </Select>
                  )}
                </TableCell>
                <TableCell>
                  {currentUserId && user.user_id !== currentUserId && (
                    <DropdownMenu>
                      <DropdownMenuTrigger asChild>
                        <Button variant="ghost" size="icon" className="h-8 w-8" disabled={!!actioning}>
                          {actioning === user.user_id ? (
                            <Loader2 className="h-4 w-4 animate-spin" />
                          ) : (
                            <MoreHorizontal className="h-4 w-4" />
                          )}
                        </Button>
                      </DropdownMenuTrigger>
                      <DropdownMenuContent align="end">
                        <DropdownMenuItem
                          onClick={() => revokeSessions(user.user_id)}
                          disabled={actioning === user.user_id}
                        >
                          <LogOut className="h-4 w-4 mr-2" />
                          Forza logout
                        </DropdownMenuItem>
                        {isSiteAdmin && (
                          <DropdownMenuItem
                            className="text-red-600 focus:text-red-600"
                            onClick={() => setDeleteConfirm(user)}
                            disabled={actioning === user.user_id}
                          >
                            <UserX className="h-4 w-4 mr-2" />
                            Rimuovi utente
                          </DropdownMenuItem>
                        )}
                      </DropdownMenuContent>
                    </DropdownMenu>
                  )}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}

      <AlertDialog open={!!deleteConfirm} onOpenChange={(open) => !open && setDeleteConfirm(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Rimuovere utente?</AlertDialogTitle>
            <AlertDialogDescription>
              L&apos;utente <strong>{deleteConfirm?.email ?? deleteConfirm?.user_id}</strong> verrà eliminato dal sistema e non potrà più accedere. Questa azione non si può annullare.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Annulla</AlertDialogCancel>
            <AlertDialogAction
              className="bg-destructive text-destructive-foreground hover:bg-destructive/90"
              onClick={() => deleteConfirm && deleteUser(deleteConfirm.user_id)}
            >
              Rimuovi
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
};

export default UserRolesManager;
