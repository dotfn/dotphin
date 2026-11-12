import type { Metadata, Viewport } from "next";
import { Geist_Mono, Urbanist } from "next/font/google";
import { Analytics } from "@vercel/analytics/next";
import { site } from "@/lib/site";
import "./globals.css";

// Urbanist: geometric and soft, it matches the rounded glass of the product.
const urbanist = Urbanist({
  variable: "--font-urbanist",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

const description =
  "A native macOS file manager with tabs, split panes, an embedded terminal and Git status on every file, built in SwiftUI.";

export const metadata: Metadata = {
  metadataBase: new URL(site.url),
  title: "Dotphin — every folder, side by side",
  description,
  icons: { icon: "/brand/icon-256.png", apple: "/brand/icon-256.png" },
  openGraph: {
    title: "Dotphin",
    description,
    images: [{ url: "/brand/screenshot.png", width: 1271, height: 810, alt: "Dotphin window with two panes and the terminal open" }],
  },
  twitter: { card: "summary_large_image" },
};

export const viewport: Viewport = {
  themeColor: "#edf0f2",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html lang="en" className={`${urbanist.variable} ${geistMono.variable} antialiased`}>
      <body>
        {children}
        <Analytics />
      </body>
    </html>
  );
}
