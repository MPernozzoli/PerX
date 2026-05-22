"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

import { getBrowserPortalHost, getTenantDomainFromHost } from "@/lib/tenant";

const NAV_ITEMS = [
  { href: "/claim", label: "Panoramica" },
  { href: "/claim/documentazione", label: "Documentazione" },
  { href: "/claim/sopralluogo", label: "Sopralluogo" },
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

  const tenantDomain =
    typeof window !== "undefined"
      ? (getTenantDomainFromHost(getBrowserPortalHost()) ?? null)
      : null;

  return (
    <header className="topbar">
      <div className="topbar__inner">
        <Link href="/" className="brand">
          <BrandMark />
          <div>
            <div className="brand__name">
              PerX{" "}
              <span style={{ color: "var(--ink-3)", fontWeight: 300 }}>Assicurati</span>
            </div>
            {tenantDomain ? (
              <div className="brand__sub">assicurati.{tenantDomain}</div>
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
