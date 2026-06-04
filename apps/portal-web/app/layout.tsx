import type { Metadata } from "next";
import { Geist, Geist_Mono, Newsreader } from "next/font/google";
import { headers } from "next/headers";
import type { ReactNode } from "react";
import { Analytics } from "@vercel/analytics/next";

import { getPortalTenantContext } from "@/lib/tenant";

import "./globals.css";

const displayFont = Newsreader({
  subsets: ["latin"],
  weight: ["300", "400", "500"],
  style: ["normal", "italic"],
  variable: "--font-display"
});

const bodyFont = Geist({
  subsets: ["latin"],
  variable: "--font-body"
});

const monoFont = Geist_Mono({
  subsets: ["latin"],
  variable: "--font-mono"
});

export const metadata: Metadata = {
  title: "PerX Assicurati",
  description: "Portale web per monitorare e gestire il proprio sinistro."
};

export default async function RootLayout({
  children
}: Readonly<{
  children: ReactNode;
}>) {
  const requestHeaders = await headers();
  const tenant = getPortalTenantContext(
    requestHeaders.get("x-forwarded-host") ?? requestHeaders.get("host")
  );

  return (
    <html lang="it" data-tenant-domain={tenant.tenantDomain ?? "local"} data-tenant-theme={tenant.themeId}>
      <head>
        {tenant.themeId !== "default" ? (
          <link rel="stylesheet" href={`/tenant-themes/${tenant.themeId}.css`} />
        ) : null}
      </head>
      <body className={`${displayFont.variable} ${bodyFont.variable} ${monoFont.variable}`}>
        {children}
        <Analytics />
      </body>
    </html>
  );
}
