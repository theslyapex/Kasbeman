import type { Metadata, Viewport } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: {
    default: "کسبمن | مدیریت یکپارچه کسب‌وکار",
    template: "%s | کسبمن",
  },
  description: "کسب‌وکارت، یک قدم جلوتر",
  applicationName: "کسبمن",
};

export const viewport: Viewport = {
  themeColor: "#071426",
  width: "device-width",
  initialScale: 1,
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="fa" dir="rtl">
      <body>{children}</body>
    </html>
  );
}
