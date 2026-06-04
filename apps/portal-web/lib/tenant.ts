// Hosts that serve all portal apps under path prefixes instead of subdomains.
// Must mirror the PATH_SLUG_HOSTS constant in proxy.ts.
const PATH_SLUG_HOSTS: Record<string, { tenantDomain: string; tenantSlug: string }> = {
  "demo.perx.it": { tenantDomain: "demo.perx.it", tenantSlug: "demo" },
};

// The path prefix used for the insured portal on path-slug hosts.
export const PORTAL_PATH_SLUG = "assicurati";

function normalizeHost(host: string | null): string {
  return (host ?? "")
    .split(",", 1)[0]
    .trim()
    .toLowerCase()
    .replace(/:\d+$/, "")
    .replace(/\.$/, "");
}

export function getTenantDomainFromHost(host: string | null): string | null {
  const h = normalizeHost(host);
  if (h in PATH_SLUG_HOSTS) return PATH_SLUG_HOSTS[h].tenantDomain;
  if (h.startsWith("assicurati.")) return h.slice("assicurati.".length);
  if (h.startsWith("riunioni.")) return h.slice("riunioni.".length);
  return null;
}

export function isPathSlugPortalHost(host: string | null): boolean {
  return normalizeHost(host) in PATH_SLUG_HOSTS;
}

export function getBrowserPortalHost(): string | null {
  if (typeof window === "undefined") return null;
  return window.location.hostname;
}

export interface PortalTenantContext {
  tenantDomain: string | null;
  themeId: string;
}

export function getPortalTenantContext(host: string | null): PortalTenantContext {
  const tenantDomain = getTenantDomainFromHost(host);
  // themeId derivation: use a sanitized domain slug or "default"
  const themeId = tenantDomain
    ? tenantDomain.replace(/[^a-z0-9]/gi, "-").replace(/-+/g, "-").replace(/^-|-$/g, "")
    : "default";
  return { tenantDomain, themeId };
}
