import type { ReactNode } from "react";

export const metadata = {
  title: "Keyflow",
  description: "OKR management for teams",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" style={{ overflowX: "hidden" }}>
      <body style={{ margin: 0, overflowX: "hidden" }}>{children}</body>
    </html>
  );
}
