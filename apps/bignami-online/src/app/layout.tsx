import type { Metadata } from "next";
import type { ReactNode } from "react";
import "../index.css";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL?.trim() || "https://bignami.perx.it";

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: "Bignami Online - Portale Periti Property",
  description:
    "Portale per periti property con focus su Fenomeno Elettrico. Consultazione rapida polizze, ricerca NLP, editing collaborativo.",
  alternates: {
    canonical: "/",
  },
  icons: {
    icon: ["/favicon.ico", { url: "/favicon.svg", type: "image/svg+xml" }],
    apple: "/apple-touch-icon.png",
  },
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="it">
      <body>{children}</body>
    </html>
  );
}
