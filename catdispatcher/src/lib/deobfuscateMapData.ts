/**
 * Decode map-data payload: obfuscated UUID-like keys -> original key names.
 * reverseMap is from get-map-keys (session-based); no static mapping in bundle.
 */
function deobfuscateValue(value: unknown, reverseMap: Record<string, string>): unknown {
  if (value === null || value === undefined) {
    return value;
  }
  if (Array.isArray(value)) {
    return value.map((v) => deobfuscateValue(v, reverseMap));
  }
  if (typeof value === 'object' && value !== null && !(value instanceof Date)) {
    const obj = value as Record<string, unknown>;
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(obj)) {
      const realKey = reverseMap[k] ?? k;
      out[realKey] = deobfuscateValue(v, reverseMap);
    }
    return out;
  }
  return value;
}

/** Decode a get-map-data response using the session's reverse mapping from get-map-keys. */
export function deobfuscateMapData<T = unknown>(payload: unknown, reverseMap: Record<string, string>): T {
  return deobfuscateValue(payload, reverseMap) as T;
}
