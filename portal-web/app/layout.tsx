import type { Metadata } from "next";
import { Inter, Plus_Jakarta_Sans } from "next/font/google";
import { headers } from "next/headers";
import type { ReactNode } from "react";

import { getPortalTenantContext } from "@/lib/tenant";

import "./globals.css";

const displayFont = Plus_Jakarta_Sans({
  subsets: ["latin"],
  variable: "--font-display"
});

const bodyFont = Inter({
  subsets: ["latin"],
  variable: "--font-body"
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
      <body className={`${displayFont.variable} ${bodyFont.variable}`}>{children}</body>
    </html>
  );
}
