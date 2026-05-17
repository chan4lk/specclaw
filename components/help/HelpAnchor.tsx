import Link from "next/link";

interface HelpAnchorProps {
  href: string;
  label?: string;
  variant?: "icon" | "text";
  className?: string;
}

export function HelpAnchor({
  href,
  label = "Help",
  variant = "text",
  className = "",
}: HelpAnchorProps) {
  if (variant === "icon") {
    return (
      <Link
        href={href}
        aria-label={label}
        className={`inline-flex h-6 w-6 items-center justify-center rounded-full bg-gray-100 text-xs font-bold text-gray-500 hover:bg-gray-200 hover:text-gray-700 ${className}`}
      >
        ?
      </Link>
    );
  }

  return (
    <Link
      href={href}
      className={`inline-flex items-center gap-1 text-xs text-blue-600 hover:underline ${className}`}
    >
      <span className="inline-flex h-4 w-4 items-center justify-center rounded-full bg-blue-100 text-xs font-bold text-blue-600">
        ?
      </span>
      {label}
    </Link>
  );
}
