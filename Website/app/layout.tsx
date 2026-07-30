import type { Metadata } from "next";
import { Inter } from "next/font/google";
import "./globals.css";

const BASE_PATH = process.env.NEXT_PUBLIC_BASE_PATH ?? "";
const SITE_URL = "https://mamontov-design.github.io/Shatl/";

const inter = Inter({
  variable: "--font-inter",
  subsets: ["cyrillic", "latin"],
  display: "swap",
});

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: "Shatl — лёгкий торрент‑клиент для Mac",
  description:
    "Выбирайте нужные файлы до начала загрузки, открывайте .torrent и magnet‑ссылки и настраивайте производительность под свой Mac. Для macOS 27+ и Apple Silicon.",
  icons: {
    icon: `${BASE_PATH}/favicon.svg`,
    shortcut: `${BASE_PATH}/favicon.svg`,
  },
  alternates: {
    canonical: SITE_URL,
  },
  openGraph: {
    url: SITE_URL,
    type: "website",
    locale: "ru_RU",
    siteName: "Shatl",
    title: "Shatl — лёгкий торрент‑клиент для Mac",
    description:
      "Выбирайте нужные файлы до начала загрузки, открывайте .torrent и magnet‑ссылки и настраивайте производительность под свой Mac.",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="ru">
      <body className={inter.variable}>{children}</body>
    </html>
  );
}
