import type { ReactNode } from "react";

import { PortalNav } from "@/components/portal-nav";

export function PortalShell({
  children,
  centered = false
}: {
  children: ReactNode;
  centered?: boolean;
}) {
  return (
    <div className="portal-shell">
      <PortalNav />
      <main className={`app-shell${centered ? " app-shell--centered" : ""}`}>{children}</main>
      <footer className="portal-footer">
        <div className="portal-footer__inner">
          <p>
            Hai bisogno di assistenza?{" "}
            <a href="mailto:assistenza@perx.it">Contattaci</a>
          </p>
          <p>© {new Date().getFullYear()} PerX Assicurati</p>
        </div>
      </footer>
    </div>
  );
}
