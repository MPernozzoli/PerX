import { FormEvent, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { toast } from 'sonner';
import { loginWithPerX } from '@/lib/perxApi';

const Login = () => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const navigate = useNavigate();

  const handleLogin = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setLoading(true);
    setError(null);

    try {
      const session = await loginWithPerX(email, password);
      const canAccessCatDispatcher = session.user.is_platform_admin || session.user.roles.some((role) => (
        ['admin', 'site_admin', 'cat_dispatcher', 'perito'].includes(role)
      ));

      if (!canAccessCatDispatcher) {
        throw new Error('Utente PerX valido ma non abilitato a CatDispatcher.');
      }

      toast.success('Accesso effettuato');
      navigate('/', { replace: true });
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Errore durante l accesso';
      setError(message);
      toast.error(message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-50 via-blue-50 to-slate-100 flex flex-col">
      <div className="flex-1 flex items-center justify-center p-6">
        <div className="w-full max-w-md">
          <div className="bg-white/80 backdrop-blur-sm rounded-2xl shadow-xl border border-white/50 p-8 md:p-10">
            <div className="text-center mb-10">
              <div className="flex flex-col items-center gap-4 mb-6">
                <img src="/logo-icon.png" alt="CAT Dispatcher Icon" className="h-32 w-auto" />
                <img src="/logo-text.png" alt="CAT Dispatcher" className="h-12 w-auto" />
              </div>
            </div>

            {error && (
              <div className="mb-6 p-4 bg-red-50 border border-red-200 rounded-xl">
                <p className="text-sm text-red-600 text-center font-medium">{error}</p>
              </div>
            )}

            <form className="space-y-5" onSubmit={handleLogin}>
              <div className="text-center">
                <h2 className="text-lg font-semibold text-slate-700 mb-1">Accedi con PerX</h2>
                <p className="text-sm text-slate-500">Usa le credenziali del backend PerX.</p>
              </div>

              <div className="space-y-2">
                <Label htmlFor="email">Email</Label>
                <Input
                  id="email"
                  type="email"
                  autoComplete="email"
                  value={email}
                  onChange={(event) => setEmail(event.target.value)}
                  required
                />
              </div>

              <div className="space-y-2">
                <Label htmlFor="password">Password</Label>
                <Input
                  id="password"
                  type="password"
                  autoComplete="current-password"
                  value={password}
                  onChange={(event) => setPassword(event.target.value)}
                  required
                />
              </div>

              <Button type="submit" className="w-full h-12 rounded-xl" disabled={loading}>
                {loading ? 'Accesso in corso...' : 'Entra'}
              </Button>
            </form>

            <div className="mt-8 pt-6 border-t border-slate-200">
              <p className="text-xs text-center text-slate-400">
                L'accesso e riservato agli utenti PerX autorizzati.
              </p>
            </div>
          </div>

          <div className="mt-6 text-center">
            <p className="text-xs text-slate-400">© {new Date().getFullYear()} CAT Dispatcher</p>
          </div>
        </div>
      </div>
    </div>
  );
};

export default Login;
