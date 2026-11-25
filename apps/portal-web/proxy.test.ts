import { describe, expect, it } from "vitest";

import { localFallback } from "./proxy";

describe("product domain fallback routing", () => {
  it.each([
    ["perx.it", "insight_studio"],
    ["perx.pynkstudio.eu", "insight_studio"],
    ["catdispatcher.it", "catdispatcher"],
    ["catdispatcher.pynkstudio.eu", "catdispatcher"],
    ["bignami.perx.it", "bignami"],
    ["bignamionline.pynkstudio.eu", "bignami"],
  ] as const)("routes %s to %s", (hostname, app) => {
    expect(localFallback(hostname)).toMatchObject({ found: true, hostname, app });
  });

  it("keeps tenant custom domains out of the product aliases", () => {
    expect(localFallback("randapro.it")).toMatchObject({ app: "randa" });
    expect(localFallback("assicurati.randa.perx.it")).toMatchObject({
      app: "insured_portal",
      tenant_domain: "randa.perx.it",
    });
  });
});
