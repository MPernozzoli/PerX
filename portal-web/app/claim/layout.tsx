import type { ReactNode } from "react";

import { ClaimSectionNav } from "@/components/claim-section-nav";
import { PortalShell } from "@/components/portal-shell";
import { PushPrompt } from "@/components/push-prompt";

export default function ClaimLayout({
  children
}: Readonly<{
  children: ReactNode;
}>) {
  return (
    <PortalShell>
      <div className="claim-route-shell">
        <ClaimSectionNav />
        <PushPrompt />
        {children}
      </div>
    </PortalShell>
  );
}
