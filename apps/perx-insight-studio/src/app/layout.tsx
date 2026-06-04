import type { Metadata } from "next";
import type { ReactNode } from "react";
import "../index.css";

export const metadata: Metadata = {
  title: "PerX.it - Il futuro della perizia property",
  description:
    "Software gestionale innovativo ed integrato per studi peritali e professionisti del settore assicurativo.",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="it">
      <body>{children}</body>
    </html>
  );
}
