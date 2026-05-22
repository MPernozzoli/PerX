"use client";

import { FormEvent, useEffect, useState } from "react";

type Tenant = {
  id: string;
  name: string;
  slug: string;
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

const API_BASE = (process.env.NEXT_PUBLIC_PERX_API_BASE_URL ?? "http://localhost:8000/api/v1").replace(/\/$/, "");
const TOKEN_KEY = "perx_admin_token";

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

export function AdminDomainRoutes() {
  const [token, setToken] = useState<string | null>(null);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [routes, setRoutes] = useState<DomainRoute[]>([]);
  const [tenants, setTenants] = useState<Tenant[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [form, setForm] = useState({
    hostname: "",
    app: "insured_portal" as DomainRoute["app"],
    tenant_id: "",
    destination_url: "",
    notes: ""
  });

  const load = async (accessToken: string) => {
    const [domainRoutes, tenantItems] = await Promise.all([
      api<DomainRoute[]>("/admin/domain-routes", accessToken),
      api<Tenant[]>("/admin/tenants", accessToken)
    ]);
    setRoutes(domainRoutes);
    setTenants(tenantItems);
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

  const createRoute = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!token) return;
    setLoading(true);
    setError(null);
    try {
      await api<DomainRoute>("/admin/domain-routes", token, {
        method: "POST",
        body: JSON.stringify({
          hostname: form.hostname,
          app: form.app,
          tenant_id: form.tenant_id || null,
          destination_url: form.destination_url || null,
          is_active: true,
          notes: form.notes || null
        })
      });
      setForm({ hostname: "", app: "insured_portal", tenant_id: "", destination_url: "", notes: "" });
      await load(token);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Errore salvataggio");
    } finally {
      setLoading(false);
    }
  };

  if (!token) {
    return (
      <form onSubmit={login} className="mt-10 max-w-md space-y-4">
        <input
          className="w-full rounded border border-zinc-700 bg-zinc-900 px-3 py-2 text-zinc-50"
          placeholder="Email PerX"
          type="email"
          value={email}
          onChange={(event) => setEmail(event.target.value)}
        />
        <input
          className="w-full rounded border border-zinc-700 bg-zinc-900 px-3 py-2 text-zinc-50"
          placeholder="Password"
          type="password"
          value={password}
          onChange={(event) => setPassword(event.target.value)}
        />
        {error ? <p className="text-sm text-red-300">{error}</p> : null}
        <button className="rounded bg-cyan-400 px-4 py-2 font-medium text-zinc-950" disabled={loading}>
          {loading ? "Accesso..." : "Accedi"}
        </button>
      </form>
    );
  }

  return (
    <div className="mt-10 grid gap-8 lg:grid-cols-[minmax(280px,360px)_1fr]">
      <form onSubmit={createRoute} className="space-y-4 rounded border border-zinc-800 bg-zinc-900/70 p-5">
        <h2 className="text-xl font-medium">Nuova route dominio</h2>
        <input
          className="w-full rounded border border-zinc-700 bg-zinc-950 px-3 py-2"
          placeholder="hostname, es. assicurati.cliente.it"
          value={form.hostname}
          onChange={(event) => setForm({ ...form, hostname: event.target.value })}
          required
        />
        <select
          className="w-full rounded border border-zinc-700 bg-zinc-950 px-3 py-2"
          value={form.app}
          onChange={(event) => setForm({ ...form, app: event.target.value as DomainRoute["app"] })}
        >
          <option value="insured_portal">Portale assicurati</option>
          <option value="catdispatcher">CatDispatcher</option>
          <option value="perx_admin">PerX Admin</option>
        </select>
        <select
          className="w-full rounded border border-zinc-700 bg-zinc-950 px-3 py-2"
          value={form.tenant_id}
          onChange={(event) => setForm({ ...form, tenant_id: event.target.value })}
        >
          <option value="">Nessun tenant</option>
          {tenants.map((tenant) => (
            <option key={tenant.id} value={tenant.id}>{tenant.name}</option>
          ))}
        </select>
        <input
          className="w-full rounded border border-zinc-700 bg-zinc-950 px-3 py-2"
          placeholder="destination_url opzionale"
          value={form.destination_url}
          onChange={(event) => setForm({ ...form, destination_url: event.target.value })}
        />
        <textarea
          className="min-h-24 w-full rounded border border-zinc-700 bg-zinc-950 px-3 py-2"
          placeholder="Note"
          value={form.notes}
          onChange={(event) => setForm({ ...form, notes: event.target.value })}
        />
        {error ? <p className="text-sm text-red-300">{error}</p> : null}
        <button className="rounded bg-cyan-400 px-4 py-2 font-medium text-zinc-950" disabled={loading}>
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
              <th className="px-4 py-3">Destination</th>
            </tr>
          </thead>
          <tbody>
            {routes.map((route) => (
              <tr key={route.id} className="border-t border-zinc-800">
                <td className="px-4 py-3 font-medium">{route.hostname}</td>
                <td className="px-4 py-3">{route.app}</td>
                <td className="px-4 py-3">{route.tenant_name ?? route.tenant_id ?? "-"}</td>
                <td className="px-4 py-3 text-zinc-400">{route.destination_url ?? "-"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
