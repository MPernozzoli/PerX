import { AuthEntry } from "@/components/auth-entry";
import { PortalShell } from "@/components/portal-shell";

export default function HomePage() {
  return (
    <PortalShell>
      <AuthEntry />
    </PortalShell>
  );
}
