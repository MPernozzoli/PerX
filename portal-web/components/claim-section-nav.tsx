"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

const CLAIM_NAV_ITEMS = [
  { href: "/claim", label: "Panoramica" },
  { href: "/claim/documentazione", label: "Documentazione" },
  { href: "/claim/sopralluogo", label: "Sopralluogo" },
  { href: "/claim/iban", label: "IBAN" },
  { href: "/claim/atto", label: "Atto" },
  { href: "/claim/chat", label: "Messaggi" }
];

export function ClaimSectionNav() {
  const pathname = usePathname();

  return (
    <nav className="claim-section-nav">
      {CLAIM_NAV_ITEMS.map((item) => {
        const isActive = item.href === "/claim" ? pathname === item.href : pathname.startsWith(item.href);
        return (
          <Link
            key={item.href}
            href={item.href}
            className={`claim-section-nav__link${isActive ? " claim-section-nav__link--active" : ""}`}
          >
            {item.label}
          </Link>
        );
      })}
    </nav>
  );
}
