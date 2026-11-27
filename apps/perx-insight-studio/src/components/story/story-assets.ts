/**
 * Mappa filename → URL pubblico quando la cattura è pronta.
 * Aggiungere qui l'import statico non appena il PNG è in src/assets/story/.
 *
 * Esempio:
 *   import elenco from "@/assets/story/01-elenco-sinistri.png";
 *   storyAssets["01-elenco-sinistri.png"] = elenco.src;
 */

const storyAssets: Record<string, string> = {};

export function resolveStoryAsset(filename: string): string | null {
  return storyAssets[filename] ?? null;
}
