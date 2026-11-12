import { describe, expect, it } from "vitest";

import {
  getPortalTenantContext,
  getTenantDomainFromHost,
  isPathSlugPortalHost,
} from "./tenant";

describe("portal tenant routing", () => {
  it("normalizes insured subdomains and removes ports", () => {
    expect(getTenantDomainFromHost(" ASSICURATI.RANDA.PERX.IT:3001 ")).toBe("randa.perx.it");
  });

  it("does not treat local development hosts as tenant domains", () => {
    expect(getTenantDomainFromHost("localhost:3001")).toBeNull();
    expect(getTenantDomainFromHost("127.0.0.1:3001")).toBeNull();
  });

  it("recognizes the shared path-based portal hosts", () => {
    expect(isPathSlugPortalHost("demo.perx.it")).toBe(true);
    expect(isPathSlugPortalHost("randa.perx.it")).toBe(false);
  });

  it("builds tenant and theme contexts consistently", () => {
    expect(getPortalTenantContext("assicurati.randa.perx.it")).toEqual({
      tenantDomain: "randa.perx.it",
      themeId: "randa-perx-it",
    });
    expect(getPortalTenantContext("demo.perx.it")).toEqual({
      tenantDomain: "demo.perx.it",
      themeId: "demo-perx-it",
    });
  });
});
