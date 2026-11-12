import { describe, expect, it } from "vitest";

import { getProvinceCode, getProvinceName, normalizeText } from "./textUtils";

describe("CAT dispatcher text utilities", () => {
  it("normalizes the capitalization of every word", () => {
    expect(normalizeText("città metropolitana")).toBe("Città Metropolitana");
  });

  it("maps province codes and names case-insensitively", () => {
    expect(getProvinceName("mi")).toBe("Milano");
    expect(getProvinceCode(" milano ")).toBe("MI");
  });

  it("handles missing and unknown values", () => {
    expect(getProvinceName(null)).toBe("");
    expect(getProvinceCode("Provincia inesistente")).toBeNull();
  });
});
