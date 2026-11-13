import type { Metadata } from "next";
import { DM_Sans, Geist_Mono } from "next/font/google";
import Header from "@/components/Header";
import Footer from "@/components/Footer";
import TabBar from "@/components/TabBar";
import "./globals.css";

// Regular and medium only: the look has no heavy bold.
const dmSans = DM_Sans({
  variable: "--font-dm-sans",
  subsets: ["latin"],
  weight: ["400", "500"],
});

// Admin tables show ZIP codes and phone numbers in a fixed-width face.
const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "So Much Sushi",
  description:
    "Every place to eat and drink, nothing paid to the top. Restaurants, bars, coffee shops and markets in the order you choose. No ads, no sponsored spots, no scores.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className={`${dmSans.variable} ${geistMono.variable} h-full antialiased`}>
      <body className="min-h-full flex flex-col">
        <Header />
        {children}
        <Footer />
        <TabBar />
      </body>
    </html>
  );
}
