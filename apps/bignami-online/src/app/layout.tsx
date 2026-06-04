import type { Metadata } from "next";
import type { ReactNode } from "react";
import "../index.css";

export const metadata: Metadata = {
  title: "Bignami Online - Portale Periti Property",
  description:
    "Portale per periti property con focus su Fenomeno Elettrico. Consultazione rapida polizze, ricerca NLP, editing collaborativo.",
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
