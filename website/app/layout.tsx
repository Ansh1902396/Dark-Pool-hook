import type { Metadata, Viewport } from "next";
import { GeistSans } from "geist/font/sans";
import { GeistMono } from "geist/font/mono";
import { DepthBackground } from "@/components/DepthBackground";
import { Nav } from "@/components/Nav";
import { site } from "@/content/site";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL(site.url),
  title: site.title,
  description: site.description,
  applicationName: site.name,
  authors: [{ name: site.author }],
  creator: site.author,
  keywords: [
    "Uniswap v4",
    "Uniswap hook",
    "dark pool",
    "coincidence of wants",
    "CoW",
    "EigenLayer",
    "AVS",
    "zero-knowledge",
    "SP1",
    "DeFi",
    "MEV",
    "Ayush Petwal",
  ],
  openGraph: {
    title: site.title,
    description: site.description,
    url: site.url,
    siteName: site.name,
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: site.title,
    description: site.description,
  },
};

export const viewport: Viewport = {
  themeColor: "#0a0b0d",
  colorScheme: "dark",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className={`${GeistSans.variable} ${GeistMono.variable}`}>
      <body className="min-h-screen font-sans antialiased">
        <DepthBackground />
        <Nav />
        {children}
      </body>
    </html>
  );
}
