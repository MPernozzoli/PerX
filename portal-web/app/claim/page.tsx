import { ClaimDashboard } from "@/components/claim-dashboard";
import { PortalShell } from "@/components/portal-shell";

export default function ClaimPage() {
  return (
    <PortalShell>
      <ClaimDashboard />
    </PortalShell>
  );
}
