import type { ReactNode } from "react";

import { ClaimSectionNav } from "@/components/claim-section-nav";
import { PortalShell } from "@/components/portal-shell";

export default function ClaimLayout({
  children
}: Readonly<{
  children: ReactNode;
}>) {
  return (
    <PortalShell>
      <div className="claim-route-shell">
        <ClaimSectionNav />
        {children}
      </div>
    </PortalShell>
  );
}
