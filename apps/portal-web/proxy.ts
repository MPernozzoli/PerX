import { NextRequest, NextResponse } from "next/server";

type RouteResolution = {
  found: boolean;
  hostname: string;
  app: "catdispatcher" | "perx_admin" | "insured_portal";
  tenant_id?: string | null;
  tenant_slug?: string | null;
  tenant_name?: string | null;
  tenant_domain?: string | null;
  destination_url?: string | null;
};

const ROUTING_API_URL = process.env.ROUTING_API_URL;
const ROUTING_RESOLVE_SECRET = process.env.ROUTING_RESOLVE_SECRET;
const CATDISPATCHER_ORIGIN = process.env.CATDISPATCHER_ORIGIN;
const PERX_ADMIN_ORIGIN = process.env.PERX_ADMIN_ORIGIN;

function normalizeHost(value: string | null): string {
  return (value ?? "")
    .split(",", 1)[0]
    .trim()
    .toLowerCase()
    .replace(/:\d+$/, "")
    .replace(/\.$/, "");
}

function localFallback(hostname: string): RouteResolution {
  if (hostname === "catdispatcher.it" || hostname === "www.catdispatcher.it") {
    return { found: true, hostname, app: "catdispatcher", destination_url: CATDISPATCHER_ORIGIN ?? null };
  }
  if (hostname === "admin.perx.it") {
    return { found: true, hostname, app: "perx_admin", destination_url: PERX_ADMIN_ORIGIN ?? null };
  }
  if (hostname.startsWith("assicurati.")) {
    return {
      found: true,
      hostname,
      app: "insured_portal",
      tenant_domain: hostname.slice("assicurati.".length),
      destination_url: null
    };
  }
  return { found: false, hostname, app: "insured_portal", destination_url: null };
}

async function resolveRoute(hostname: string): Promise<RouteResolution> {
  if (!ROUTING_API_URL) {
    return localFallback(hostname);
  }

  try {
    const response = await fetch(`${ROUTING_API_URL}?host=${encodeURIComponent(hostname)}`, {
      headers: ROUTING_RESOLVE_SECRET ? { "X-PerX-Routing-Secret": ROUTING_RESOLVE_SECRET } : undefined,
      next: { revalidate: 60 }
    });
    if (!response.ok) return localFallback(hostname);
    return (await response.json()) as RouteResolution;
  } catch {
    return localFallback(hostname);
  }
}

function rewriteToOrigin(request: NextRequest, origin: string): NextResponse {
  const destination = new URL(request.nextUrl.pathname + request.nextUrl.search, origin);
  return NextResponse.rewrite(destination);
}

// Domini "vetrina" che servono tutte le app come path-slug invece che come
// subdomain (es. demo.perx.it/admin, demo.perx.it/assicurati). Il tenant è
// determinato dal dominio stesso, non dal subdomain `assicurati.`.
const PATH_SLUG_HOSTS: Record<string, { tenantDomain: string; tenantSlug: string }> = {
  "demo.perx.it": { tenantDomain: "demo.perx.it", tenantSlug: "demo" }
};

function rewriteWithStrippedPrefix(request: NextRequest, prefix: string): NextResponse {
  const stripped = request.nextUrl.pathname.slice(prefix.length) || "/";
  const url = request.nextUrl.clone();
  url.pathname = stripped;
  return NextResponse.rewrite(url);
}

export default async function proxy(request: NextRequest) {
  const hostname = normalizeHost(request.headers.get("x-forwarded-host") ?? request.headers.get("host"));
  const pathname = request.nextUrl.pathname;

  const pathSlugConfig = PATH_SLUG_HOSTS[hostname];
  if (pathSlugConfig) {
    // /admin/* → app perx_admin esterna (se configurata) altrimenti pagina locale /admin
    if (pathname === "/admin" || pathname.startsWith("/admin/")) {
      if (PERX_ADMIN_ORIGIN) {
        const destination = new URL(pathname + request.nextUrl.search, PERX_ADMIN_ORIGIN);
        return NextResponse.rewrite(destination);
      }
      // fall through to portal-web's local /admin page
      return NextResponse.next();
    }

    // /catdispatcher/* → app cat dispatcher esterna
    if (pathname === "/catdispatcher" || pathname.startsWith("/catdispatcher/")) {
      const origin = CATDISPATCHER_ORIGIN;
      if (origin) {
        const stripped = pathname.replace(/^\/catdispatcher/, "") || "/";
        return NextResponse.rewrite(new URL(stripped + request.nextUrl.search, origin));
      }
      return NextResponse.rewrite(new URL("/_routing/catdispatcher-unconfigured", request.url));
    }

    // /assicurati/* → portale assicurati (root del portal-web), con tenant headers
    if (pathname === "/assicurati" || pathname.startsWith("/assicurati/")) {
      const stripped = pathname.replace(/^\/assicurati/, "") || "/";
      const url = request.nextUrl.clone();
      url.pathname = stripped;
      const requestHeaders = new Headers(request.headers);
      requestHeaders.set("x-perx-tenant-slug", pathSlugConfig.tenantSlug);
      requestHeaders.set("x-perx-tenant-domain", pathSlugConfig.tenantDomain);
      requestHeaders.set("x-perx-route-app", "insured_portal");
      return NextResponse.rewrite(url, { request: { headers: requestHeaders } });
    }

    // root e altri path: lascia passare al portal-web (può fare landing)
    const requestHeaders = new Headers(request.headers);
    requestHeaders.set("x-perx-tenant-slug", pathSlugConfig.tenantSlug);
    requestHeaders.set("x-perx-tenant-domain", pathSlugConfig.tenantDomain);
    requestHeaders.set("x-perx-route-app", "portal_landing");
    return NextResponse.next({ request: { headers: requestHeaders } });
  }

  const route = await resolveRoute(hostname);

  if (route.app === "catdispatcher") {
    const origin = route.destination_url ?? CATDISPATCHER_ORIGIN;
    if (origin) return rewriteToOrigin(request, origin);
    return NextResponse.rewrite(new URL("/_routing/catdispatcher-unconfigured", request.url));
  }

  if (route.app === "perx_admin") {
    const origin = route.destination_url ?? PERX_ADMIN_ORIGIN;
    if (origin) return rewriteToOrigin(request, origin);
    return NextResponse.rewrite(new URL("/admin", request.url));
  }

  const requestHeaders = new Headers(request.headers);
  if (route.tenant_id) requestHeaders.set("x-perx-tenant-id", route.tenant_id);
  if (route.tenant_slug) requestHeaders.set("x-perx-tenant-slug", route.tenant_slug);
  if (route.tenant_domain) requestHeaders.set("x-perx-tenant-domain", route.tenant_domain);
  requestHeaders.set("x-perx-route-app", "insured_portal");

  return NextResponse.next({ request: { headers: requestHeaders } });
}

export const config = {
  matcher: ["/((?!_next/static|_next/image|favicon.ico|robots.txt|tenant-themes|.*\\..*).*)"]
};
