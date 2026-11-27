import type { Metadata } from "next";
import type { ReactNode } from "react";
import "../index.css";

export const metadata: Metadata = {
  title: "PerX — Piattaforma operativa per studi peritali",
  description:
    "Una pratica dall'incarico alla stima: elenco sinistri, dettaglio, bignami, studio e team, CAT dispatcher, portale assicurati, PerX Lite e elaborato calcoli.",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="it">
      <body>{children}</body>
    </html>
  );
}
