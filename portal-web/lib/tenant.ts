export const PORTAL_SUBDOMAIN = "assicurati";

export type PortalTenantContext = {
  host: string | null;
  tenantDomain: string | null;
  themeId: string;
};

export function normalizePortalHost(value?: string | null): string | null {
  if (!value) {
    return null;
  }

  const candidate = value
    .split(",", 1)[0]
    .trim()
    .toLowerCase()
    .replace(/^https?:\/\//, "")
    .split("/", 1)[0]
    .split("?", 1)[0]
    .replace(/\.$/, "");

  if (!candidate) {
    return null;
  }

  if (candidate.startsWith("[")) {
    return candidate;
  }

  return candidate.replace(/:\d+$/, "");
}

export function getTenantDomainFromHost(host?: string | null): string | null {
  const normalizedHost = normalizePortalHost(host);
  if (!normalizedHost) {
    return null;
  }

  const prefix = `${PORTAL_SUBDOMAIN}.`;
  return normalizedHost.startsWith(prefix) ? normalizedHost.slice(prefix.length) || null : null;
}

export function getThemeIdFromTenantDomain(tenantDomain?: string | null): string {
  if (!tenantDomain) {
    return "default";
  }

  const [firstLabel] = tenantDomain.split(".");
  return firstLabel?.replace(/[^a-z0-9-]/g, "-").replace(/^-+|-+$/g, "") || "default";
}

export function getPortalTenantContext(host?: string | null): PortalTenantContext {
  const normalizedHost = normalizePortalHost(host);
  const tenantDomain = getTenantDomainFromHost(normalizedHost);

  return {
    host: normalizedHost,
    tenantDomain,
    themeId: getThemeIdFromTenantDomain(tenantDomain)
  };
}

export function getBrowserPortalHost(): string | null {
  if (typeof window === "undefined") {
    return null;
  }

  return normalizePortalHost(window.location.host);
}

export function getPortalStorageScope(): string {
  return getBrowserPortalHost() ?? "local";
}
