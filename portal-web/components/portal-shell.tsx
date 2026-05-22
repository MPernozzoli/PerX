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
    <div className="shell">
      <PortalNav />
      <div style={{ flex: 1, display: "flex", flexDirection: "column" }}>
        <main className={centered ? "app-shell app-shell--centered" : "app-shell"}>
          {children}
        </main>
      </div>
      <footer className="footer">
        <div>
          © {new Date().getFullYear()} PerX · Portale assicurati.{" "}
          Tutti i diritti riservati.
        </div>
        <div className="row" style={{ gap: 24 }}>
          <a href="#">Privacy</a>
          <a href="#">Termini di servizio</a>
          <a href="#">Cookie</a>
          <a href="mailto:assistenza@perx.it">Assistenza</a>
        </div>
      </footer>
    </div>
  );
}
