"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";

import { getPortalTenantBranding, type PortalTenantBranding } from "@/lib/api";
import {
  getBrowserPortalHost,
  getTenantDomainFromHost,
  isPathSlugPortalHost,
  PORTAL_PATH_SLUG
} from "@/lib/tenant";

const NAV_ITEMS = [
  { href: "/claim", label: "Panoramica" },
  { href: "/claim/documentazione", label: "Documentazione" },
  { href: "/claim/sopralluogo", label: "Perizia" },
  { href: "/claim/pagamenti", label: "Pagamenti" },
  { href: "/claim/atto", label: "Atto" },
  { href: "/claim/messaggi", label: "Messaggi" },
];

function BrandMark() {
  return (
    <span className="brand__mark">
      <svg width="16" height="16" viewBox="0 0 24 24" fill="none" aria-hidden="true">
        <path
          d="M5 4v16M5 4h6a4 4 0 0 1 0 8H5"
          stroke="currentColor"
          strokeWidth="2.2"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
        <path
          d="M14 13l6 8M20 13l-6 8"
          stroke="currentColor"
          strokeWidth="2.2"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
    </span>
  );
}

export function PortalNav() {
  const pathname = usePathname();
  const isAuthPage = pathname === "/";
  const [branding, setBranding] = useState<PortalTenantBranding>({});

  useEffect(() => {
    getPortalTenantBranding()
      .then((nextBranding) => {
        setBranding(nextBranding);
        const color = nextBranding.primary_color?.trim();
        if (color && /^#[0-9a-f]{6}$/i.test(color)) {
          const root = document.documentElement;
          root.style.setProperty("--accent", color);
          root.style.setProperty("--accent-2", `color-mix(in srgb, ${color} 78%, black)`);
          root.style.setProperty("--accent-soft", `color-mix(in srgb, ${color} 22%, white)`);
          root.style.setProperty("--accent-tint", `color-mix(in srgb, ${color} 12%, white)`);
        }
      })
      .catch(() => undefined);
  }, []);

  const browserHost = typeof window !== "undefined" ? getBrowserPortalHost() : null;
  const tenantDomain = browserHost ? (getTenantDomainFromHost(browserHost) ?? null) : null;
  const pathSlugHost = isPathSlugPortalHost(browserHost);
  const portalDisplayDomain = tenantDomain
    ? pathSlugHost
      ? `${tenantDomain}/${PORTAL_PATH_SLUG}`
      : `assicurati.${tenantDomain}`
    : null;

  return (
    <header className="topbar">
      <div className="topbar__inner">
        <Link href="/" className="brand">
          {branding.logo_data_url ? (
            <img className="brand__logo" src={branding.logo_data_url} alt={branding.tenant_name ?? "Logo tenant"} />
          ) : (
            <BrandMark />
          )}
          <div>
            <div className="brand__name">
              PerX{" "}
              <span style={{ color: "var(--ink-3)", fontWeight: 300 }}>Assicurati</span>
            </div>
            {portalDisplayDomain ? (
              <div className="brand__sub">{portalDisplayDomain}</div>
            ) : null}
          </div>
        </Link>

        {!isAuthPage && (
          <nav className="nav" aria-label="Navigazione pratica">
            {NAV_ITEMS.map((item) => {
              const isActive =
                item.href === "/claim"
                  ? pathname === "/claim"
                  : pathname.startsWith(item.href);
              return (
                <Link
                  key={item.href}
                  href={item.href}
                  className={`nav__link${isActive ? " nav__link--active" : ""}`}
                >
                  {item.label}
                </Link>
              );
            })}
          </nav>
        )}

        <div className="topbar__right">
          {isAuthPage ? (
            <Link href="/come-funziona" className="nav__link">
              Come funziona
            </Link>
          ) : (
            <>
              <Link href="/come-funziona" className="nav__link">
                Come funziona
              </Link>
              <div style={{ width: 1, height: 16, background: "var(--line)" }} />
              <Link href="/" className="btn btn--quiet btn--sm">
                Esci
              </Link>
            </>
          )}
        </div>
      </div>
    </header>
  );
}
