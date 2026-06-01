"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";
import type { ReactNode } from "react";

type Tenant = {
  id: string;
  name: string;
  slug: string;
};

type AdminUser = {
  id: string;
  tenant_id: string;
  email: string;
  personal_email?: string | null;
  professional_email?: string | null;
  full_name: string;
  is_active: boolean;
  is_platform_admin: boolean;
};

type DomainRoute = {
  id: string;
  hostname: string;
  app: "catdispatcher" | "perx_admin" | "insured_portal";
  tenant_id?: string | null;
  tenant_name?: string | null;
  destination_url?: string | null;
  is_active: boolean;
  notes?: string | null;
};

type TenantSettings = {
  tenant_id: string;
  tenant_name: string;
  tenant_slug: string;
  portal_domains: string[];
  internal_domains: string[];
  internal_emails: string[];
  system_emails: string[];
  secretariat_emails: string[];
  claim_garanzie: string[];
  default_claim_garanzia: string;
  cat_settings: {
    enabled: boolean;
    planner: {
      route_generation_hour: number;
      route_review_window_minutes: number;
      availability_slot_minutes: number;
      availability_tolerance_percent: number;
      max_outside_zone_kilometers: number;
    };
    technicians: unknown[];
    municipalities: unknown[];
  };
  video_inspection_settings: {
    enabled: boolean;
    assignment_run_hour: number;
    first_slot_time: string;
    slot_minutes: number;
  };
  provider_settings?: {
    map_provider: string;
    maps_api_key: string;
    routing_provider: string;
    routing_api_key: string;
    geocoding_provider: string;
    geocoding_api_key: string;
    messaging_provider: string;
    messaging_api_key: string;
  } | null;
};

type Tab = "overview" | "tenants" | "domains" | "users";

const API_BASE = (process.env.NEXT_PUBLIC_PERX_API_BASE_URL ?? "http://localhost:8000/api/v1").replace(/\/$/, "");
const TOKEN_KEY = "perx_admin_token";

const emptyRouteForm = {
  hostname: "",
  app: "insured_portal" as DomainRoute["app"],
  tenant_id: "",
  destination_url: "",
  notes: "",
  is_active: true
};

async function api<T>(path: string, token: string, init: RequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers);
  headers.set("Content-Type", "application/json");
  headers.set("Authorization", `Bearer ${token}`);
  const response = await fetch(`${API_BASE}${path}`, { ...init, headers, cache: "no-store" });
  const payload = await response.json().catch(() => null);
  if (!response.ok) {
    throw new Error(payload?.detail ?? payload?.error ?? `HTTP ${response.status}`);
  }
  return payload as T;
}

function linesToList(value: string): string[] {
  return value
    .split(/\r?\n|,/)
    .map((item) => item.trim())
    .filter(Boolean);
}

function listToLines(value: string[]): string {
  return value.join("\n");
}

function tenantName(tenants: Tenant[], tenantId?: string | null): string {
  if (!tenantId) return "-";
  return tenants.find((tenant) => tenant.id === tenantId)?.name ?? tenantId;
}

export function AdminDomainRoutes() {
  const [token, setToken] = useState<string | null>(null);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [routes, setRoutes] = useState<DomainRoute[]>([]);
  const [tenants, setTenants] = useState<Tenant[]>([]);
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [selectedTenantId, setSelectedTenantId] = useState("");
  const [settings, setSettings] = useState<TenantSettings | null>(null);
  const [tab, setTab] = useState<Tab>("overview");
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [routeForm, setRouteForm] = useState(emptyRouteForm);
  const [tenantForm, setTenantForm] = useState({ name: "", slug: "" });

  const activeRoutes = useMemo(() => routes.filter((route) => route.is_active), [routes]);
  const insuredRoutes = useMemo(() => routes.filter((route) => route.app === "insured_portal"), [routes]);
  const tenantUsers = useMemo(
    () => users.filter((user) => !selectedTenantId || user.tenant_id === selectedTenantId),
    [selectedTenantId, users]
  );

  const load = async (accessToken: string, nextTenantId?: string) => {
    const [domainRoutes, tenantItems, userItems] = await Promise.all([
      api<DomainRoute[]>("/admin/domain-routes", accessToken),
      api<Tenant[]>("/admin/tenants", accessToken),
      api<AdminUser[]>("/admin/users", accessToken)
    ]);

    setRoutes(domainRoutes);
    setTenants(tenantItems);
    setUsers(userItems);

    const targetTenantId = nextTenantId || selectedTenantId || tenantItems[0]?.id || "";
    setSelectedTenantId(targetTenantId);
    if (targetTenantId) {
      const tenantSettings = await api<TenantSettings>(`/admin/tenants/${targetTenantId}/settings`, accessToken);
      setSettings(tenantSettings);
    } else {
      setSettings(null);
    }
  };

  useEffect(() => {
    const stored = localStorage.getItem(TOKEN_KEY);
    if (!stored) return;
    setToken(stored);
    load(stored).catch(() => {
      localStorage.removeItem(TOKEN_KEY);
      setToken(null);
    });
  }, []);

  const login = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setLoading(true);
    setError(null);
    try {
      const response = await fetch(`${API_BASE}/auth/login`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ username: email, password })
      });
      const payload = await response.json();
      if (!response.ok) throw new Error(payload?.detail ?? "Login non riuscito");
      localStorage.setItem(TOKEN_KEY, payload.access_token);
      setToken(payload.access_token);
      await load(payload.access_token);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Errore login");
    } finally {
      setLoading(false);
    }
  };

  const logout = () => {
    localStorage.removeItem(TOKEN_KEY);
    setToken(null);
    setRoutes([]);
    setTenants([]);
    setUsers([]);
    setSettings(null);
  };

  const selectTenant = async (tenantId: string) => {
    if (!token) return;
    setSelectedTenantId(tenantId);
    if (!tenantId) {
      setSettings(null);
      return;
    }
    setError(null);
    try {
      setSettings(await api<TenantSettings>(`/admin/tenants/${tenantId}/settings`, token));
    } catch (err) {
      setError(err instanceof Error ? err.message : "Errore caricamento tenant");
    }
  };

  const createTenant = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!token) return;
    setLoading(true);
    setError(null);
    setMessage(null);
    try {
      const tenant = await api<Tenant>("/admin/tenants", token, {
        method: "POST",
        body: JSON.stringify({ name: tenantForm.name, slug: tenantForm.slug, settings_json: {} })
      });
      setTenantForm({ name: "", slug: "" });
      setMessage("Tenant creato");
      await load(token, tenant.id);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Errore creazione tenant");
    } finally {
      setLoading(false);
    }
  };

  const saveSettings = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!token || !settings) return;
    setLoading(true);
    setError(null);
    setMessage(null);
    try {
      await api<TenantSettings>(`/admin/tenants/${settings.tenant_id}/settings`, token, {
        method: "PUT",
        body: JSON.stringify(settings)
      });
      setMessage("Impostazioni tenant salvate");
      await load(token, settings.tenant_id);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Errore salvataggio tenant");
    } finally {
      setLoading(false);
    }
  };

  const createRoute = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!token) return;
    setLoading(true);
    setError(null);
    setMessage(null);
    try {
      await api<DomainRoute>("/admin/domain-routes", token, {
        method: "POST",
        body: JSON.stringify({
          hostname: routeForm.hostname,
          app: routeForm.app,
          tenant_id: routeForm.tenant_id || null,
          destination_url: routeForm.destination_url || null,
          is_active: routeForm.is_active,
          notes: routeForm.notes || null
        })
      });
      setRouteForm(emptyRouteForm);
      setMessage("Route dominio creata");
      await load(token);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Errore salvataggio route");
    } finally {
      setLoading(false);
    }
  };

  const toggleRoute = async (route: DomainRoute) => {
    if (!token) return;
    setLoading(true);
    setError(null);
    try {
      await api<DomainRoute>(`/admin/domain-routes/${route.id}`, token, {
        method: "PUT",
        body: JSON.stringify({
          hostname: route.hostname,
          app: route.app,
          tenant_id: route.tenant_id ?? null,
          destination_url: route.destination_url ?? null,
          is_active: !route.is_active,
          notes: route.notes ?? null
        })
      });
      await load(token);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Errore aggiornamento route");
    } finally {
      setLoading(false);
    }
  };

  const deleteRoute = async (routeId: string) => {
    if (!token) return;
    setLoading(true);
    setError(null);
    try {
      await api<void>(`/admin/domain-routes/${routeId}`, token, { method: "DELETE" });
      await load(token);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Errore eliminazione route");
    } finally {
      setLoading(false);
    }
  };

  if (!token) {
    return (
      <form onSubmit={login} className="mt-10 max-w-md space-y-4 rounded border border-zinc-800 bg-zinc-900 p-5">
        <div>
          <h2 className="text-xl font-medium">Accesso admin</h2>
          <p className="mt-1 text-sm text-zinc-400">Usa un account PerX con privilegi platform admin.</p>
        </div>
        <input
          className="w-full rounded border border-zinc-700 bg-zinc-950 px-3 py-2 text-zinc-50"
          placeholder="Email PerX"
          type="email"
          value={email}
          onChange={(event) => setEmail(event.target.value)}
        />
        <input
          className="w-full rounded border border-zinc-700 bg-zinc-950 px-3 py-2 text-zinc-50"
          placeholder="Password"
          type="password"
          value={password}
          onChange={(event) => setPassword(event.target.value)}
        />
        {error ? <p className="text-sm text-red-300">{error}</p> : null}
        <button className="rounded bg-cyan-400 px-4 py-2 font-medium text-zinc-950 disabled:opacity-60" disabled={loading}>
          {loading ? "Accesso..." : "Accedi"}
        </button>
      </form>
    );
  }

  return (
    <div className="mt-10 space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex flex-wrap gap-2">
          {(["overview", "tenants", "domains", "users"] as Tab[]).map((item) => (
            <button
              key={item}
              className={`rounded border px-3 py-2 text-sm ${
                tab === item ? "border-cyan-400 bg-cyan-400 text-zinc-950" : "border-zinc-800 bg-zinc-900 text-zinc-300"
              }`}
              onClick={() => setTab(item)}
              type="button"
            >
              {item === "overview" ? "Vista" : item === "tenants" ? "Tenant" : item === "domains" ? "Domini" : "Utenti"}
            </button>
          ))}
        </div>
        <button className="rounded border border-zinc-700 px-3 py-2 text-sm text-zinc-300" onClick={logout} type="button">
          Esci
        </button>
      </div>

      {error ? <p className="rounded border border-red-500/40 bg-red-950/50 px-4 py-3 text-sm text-red-200">{error}</p> : null}
      {message ? <p className="rounded border border-emerald-500/40 bg-emerald-950/40 px-4 py-3 text-sm text-emerald-200">{message}</p> : null}

      {tab === "overview" ? (
        <section className="grid gap-4 md:grid-cols-3">
          <Metric label="Tenant" value={tenants.length} />
          <Metric label="Domini attivi" value={activeRoutes.length} />
          <Metric label="Portali assicurati" value={insuredRoutes.length} />
        </section>
      ) : null}

      {tab === "tenants" ? (
        <section className="grid gap-6 lg:grid-cols-[320px_1fr]">
          <div className="space-y-4">
            <form onSubmit={createTenant} className="space-y-3 rounded border border-zinc-800 bg-zinc-900 p-4">
              <h2 className="text-lg font-medium">Nuovo tenant</h2>
              <input
                className="w-full rounded border border-zinc-700 bg-zinc-950 px-3 py-2"
                placeholder="Nome tenant"
                value={tenantForm.name}
                onChange={(event) => setTenantForm({ ...tenantForm, name: event.target.value })}
                required
              />
              <input
                className="w-full rounded border border-zinc-700 bg-zinc-950 px-3 py-2"
                placeholder="slug"
                value={tenantForm.slug}
                onChange={(event) => setTenantForm({ ...tenantForm, slug: event.target.value })}
                required
              />
              <button className="rounded bg-cyan-400 px-4 py-2 font-medium text-zinc-950 disabled:opacity-60" disabled={loading}>
                Crea tenant
              </button>
            </form>

            <div className="overflow-hidden rounded border border-zinc-800">
              {tenants.map((tenant) => (
                <button
                  key={tenant.id}
                  className={`block w-full border-b border-zinc-800 px-4 py-3 text-left text-sm last:border-b-0 ${
                    selectedTenantId === tenant.id ? "bg-zinc-800 text-zinc-50" : "bg-zinc-950 text-zinc-300"
                  }`}
                  onClick={() => selectTenant(tenant.id)}
                  type="button"
                >
                  <span className="block font-medium">{tenant.name}</span>
                  <span className="text-xs text-zinc-500">{tenant.slug}</span>
                </button>
              ))}
            </div>
          </div>

          {settings ? (
            <form onSubmit={saveSettings} className="grid gap-4 rounded border border-zinc-800 bg-zinc-900 p-4 md:grid-cols-2">
              <Field label="Nome tenant">
                <input
                  className="w-full rounded border border-zinc-700 bg-zinc-950 px-3 py-2"
                  value={settings.tenant_name}
                  onChange={(event) => setSettings({ ...settings, tenant_name: event.target.value })}
                />
              </Field>
              <Field label="Slug tenant">
                <input
                  className="w-full rounded border border-zinc-700 bg-zinc-950 px-3 py-2"
                  value={settings.tenant_slug}
                  onChange={(event) => setSettings({ ...settings, tenant_slug: event.target.value })}
                />
              </Field>
              <Field label="Domini portale assicurati">
                <textarea
                  className="min-h-28 w-full rounded border border-zinc-700 bg-zinc-950 px-3 py-2"
                  value={listToLines(settings.portal_domains)}
                  onChange={(event) => setSettings({ ...settings, portal_domains: linesToList(event.target.value) })}
                />
              </Field>
              <Field label="Domini interni">
                <textarea
                  className="min-h-28 w-full rounded border border-zinc-700 bg-zinc-950 px-3 py-2"
                  value={listToLines(settings.internal_domains)}
                  onChange={(event) => setSettings({ ...settings, internal_domains: linesToList(event.target.value) })}
                />
              </Field>
              <Field label="Email sistema">
                <textarea
                  className="min-h-28 w-full rounded border border-zinc-700 bg-zinc-950 px-3 py-2"
                  value={listToLines(settings.system_emails)}
                  onChange={(event) => setSettings({ ...settings, system_emails: linesToList(event.target.value) })}
                />
              </Field>
              <Field label="Email segreteria">
                <textarea
                  className="min-h-28 w-full rounded border border-zinc-700 bg-zinc-950 px-3 py-2"
                  value={listToLines(settings.secretariat_emails)}
                  onChange={(event) => setSettings({ ...settings, secretariat_emails: linesToList(event.target.value) })}
                />
              </Field>
              <Field label="Garanzie sinistri">
                <textarea
                  className="min-h-28 w-full rounded border border-zinc-700 bg-zinc-950 px-3 py-2"
                  value={listToLines(settings.claim_garanzie)}
                  onChange={(event) => setSettings({ ...settings, claim_garanzie: linesToList(event.target.value) })}
                />
              </Field>
              <Field label="Garanzia default">
                <input
                  className="w-full rounded border border-zinc-700 bg-zinc-950 px-3 py-2"
                  value={settings.default_claim_garanzia}
                  onChange={(event) => setSettings({ ...settings, default_claim_garanzia: event.target.value })}
                />
              </Field>
              <Field label="Primo slot videoperizia">
                <input
                  className="w-full rounded border border-zinc-700 bg-zinc-950 px-3 py-2"
                  type="time"
                  value={settings.video_inspection_settings.first_slot_time}
                  onChange={(event) =>
                    setSettings({
                      ...settings,
                      video_inspection_settings: {
                        ...settings.video_inspection_settings,
                        first_slot_time: event.target.value
                      }
                    })
                  }
                />
              </Field>
              <div className="md:col-span-2">
                <button className="rounded bg-cyan-400 px-4 py-2 font-medium text-zinc-950 disabled:opacity-60" disabled={loading}>
                  Salva impostazioni tenant
                </button>
              </div>
            </form>
          ) : (
            <div className="rounded border border-zinc-800 bg-zinc-900 p-5 text-zinc-400">Seleziona o crea un tenant.</div>
          )}
        </section>
      ) : null}

      {tab === "domains" ? (
        <section className="grid gap-6 lg:grid-cols-[360px_1fr]">
          <form onSubmit={createRoute} className="space-y-4 rounded border border-zinc-800 bg-zinc-900 p-5">
            <h2 className="text-lg font-medium">Nuova route dominio</h2>
            <input
              className="w-full rounded border border-zinc-700 bg-zinc-950 px-3 py-2"
              placeholder="assicurati.cliente.it"
              value={routeForm.hostname}
              onChange={(event) => setRouteForm({ ...routeForm, hostname: event.target.value })}
              required
            />
            <select
              className="w-full rounded border border-zinc-700 bg-zinc-950 px-3 py-2"
              value={routeForm.app}
              onChange={(event) => setRouteForm({ ...routeForm, app: event.target.value as DomainRoute["app"] })}
            >
              <option value="insured_portal">Portale assicurati</option>
              <option value="catdispatcher">CatDispatcher</option>
              <option value="perx_admin">PerX Admin</option>
            </select>
            <select
              className="w-full rounded border border-zinc-700 bg-zinc-950 px-3 py-2"
              value={routeForm.tenant_id}
              onChange={(event) => setRouteForm({ ...routeForm, tenant_id: event.target.value })}
            >
              <option value="">Nessun tenant</option>
              {tenants.map((tenant) => (
                <option key={tenant.id} value={tenant.id}>{tenant.name}</option>
              ))}
            </select>
            <input
              className="w-full rounded border border-zinc-700 bg-zinc-950 px-3 py-2"
              placeholder="destination_url opzionale"
              value={routeForm.destination_url}
              onChange={(event) => setRouteForm({ ...routeForm, destination_url: event.target.value })}
            />
            <textarea
              className="min-h-24 w-full rounded border border-zinc-700 bg-zinc-950 px-3 py-2"
              placeholder="Note"
              value={routeForm.notes}
              onChange={(event) => setRouteForm({ ...routeForm, notes: event.target.value })}
            />
            <label className="flex items-center gap-2 text-sm text-zinc-300">
              <input
                checked={routeForm.is_active}
                onChange={(event) => setRouteForm({ ...routeForm, is_active: event.target.checked })}
                type="checkbox"
              />
              Attiva
            </label>
            <button className="rounded bg-cyan-400 px-4 py-2 font-medium text-zinc-950 disabled:opacity-60" disabled={loading}>
              Salva route
            </button>
          </form>

          <div className="overflow-hidden rounded border border-zinc-800">
            <table className="w-full text-left text-sm">
              <thead className="bg-zinc-900 text-zinc-300">
                <tr>
                  <th className="px-4 py-3">Host</th>
                  <th className="px-4 py-3">App</th>
                  <th className="px-4 py-3">Tenant</th>
                  <th className="px-4 py-3">Stato</th>
                  <th className="px-4 py-3">Azioni</th>
                </tr>
              </thead>
              <tbody>
                {routes.map((route) => (
                  <tr key={route.id} className="border-t border-zinc-800">
                    <td className="px-4 py-3 font-medium">{route.hostname}</td>
                    <td className="px-4 py-3">{route.app}</td>
                    <td className="px-4 py-3">{route.tenant_name ?? tenantName(tenants, route.tenant_id)}</td>
                    <td className="px-4 py-3">{route.is_active ? "Attiva" : "Disattiva"}</td>
                    <td className="space-x-2 px-4 py-3">
                      <button className="rounded border border-zinc-700 px-2 py-1" onClick={() => toggleRoute(route)} type="button">
                        {route.is_active ? "Disattiva" : "Attiva"}
                      </button>
                      <button className="rounded border border-red-500/60 px-2 py-1 text-red-200" onClick={() => deleteRoute(route.id)} type="button">
                        Elimina
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      ) : null}

      {tab === "users" ? (
        <section className="space-y-4">
          <select
            className="rounded border border-zinc-700 bg-zinc-950 px-3 py-2"
            value={selectedTenantId}
            onChange={(event) => selectTenant(event.target.value)}
          >
            <option value="">Tutti i tenant</option>
            {tenants.map((tenant) => (
              <option key={tenant.id} value={tenant.id}>{tenant.name}</option>
            ))}
          </select>
          <div className="overflow-hidden rounded border border-zinc-800">
            <table className="w-full text-left text-sm">
              <thead className="bg-zinc-900 text-zinc-300">
                <tr>
                  <th className="px-4 py-3">Utente</th>
                  <th className="px-4 py-3">Tenant</th>
                  <th className="px-4 py-3">Email</th>
                  <th className="px-4 py-3">Ruolo</th>
                  <th className="px-4 py-3">Stato</th>
                </tr>
              </thead>
              <tbody>
                {tenantUsers.map((user) => (
                  <tr key={user.id} className="border-t border-zinc-800">
                    <td className="px-4 py-3 font-medium">{user.full_name}</td>
                    <td className="px-4 py-3">{tenantName(tenants, user.tenant_id)}</td>
                    <td className="px-4 py-3 text-zinc-400">{user.professional_email ?? user.personal_email ?? user.email}</td>
                    <td className="px-4 py-3">{user.is_platform_admin ? "Platform admin" : "Tenant"}</td>
                    <td className="px-4 py-3">{user.is_active ? "Attivo" : "Disattivo"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      ) : null}
    </div>
  );
}

function Metric({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded border border-zinc-800 bg-zinc-900 p-5">
      <p className="text-sm text-zinc-400">{label}</p>
      <p className="mt-3 text-4xl font-semibold">{value}</p>
    </div>
  );
}

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <label className="space-y-2">
      <span className="block text-sm text-zinc-300">{label}</span>
      {children}
    </label>
  );
}
