import Link from "next/link";
import { HelpAnchor } from "@/components/help/HelpAnchor";

/**
 * Top navigation bar — shown on all authenticated routes.
 * Integrate this into app/(authenticated)/layout.tsx or equivalent.
 */
export function NavBar() {
  return (
    <nav className="flex h-14 items-center justify-between border-b border-gray-200 bg-white px-4 shadow-sm">
      {/* Brand */}
      <Link href="/dashboard" className="text-lg font-bold text-blue-600">
        Keyflow
      </Link>

      {/* Right side actions */}
      <div className="flex items-center gap-3">
        <HelpAnchor
          href="/help"
          label="Help"
          variant="icon"
          className="h-8 w-8 text-base"
        />
        {/* TODO: add user avatar / profile menu here */}
      </div>
    </nav>
  );
}
