"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const NAV_ITEMS = [
  { href: "/", label: "Accesso" },
  { href: "/claim", label: "Panoramica" },
  { href: "/come-funziona", label: "Come funziona" }
];

export function PortalNav() {
  const pathname = usePathname();

  return (
    <header className="portal-header">
      <div className="portal-header__inner">
        <Link href="/" className="portal-brand">
          <span className="portal-brand__mark">PX</span>
          <span className="portal-brand__text">Area Assicurato</span>
        </Link>

        <nav className="portal-nav">
          {NAV_ITEMS.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              className={`portal-nav__link${pathname === item.href ? " portal-nav__link--active" : ""}`}
            >
              {item.label}
            </Link>
          ))}
        </nav>
      </div>
    </header>
  );
}
