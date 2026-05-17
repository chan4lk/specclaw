"use client";

import type { ReactNode } from "react";

interface CalloutProps {
  type?: "tip" | "warning" | "note";
  children: ReactNode;
}

const CALLOUT_STYLES = {
  tip: {
    border: "border-green-400",
    bg: "bg-green-50",
    icon: "💡",
    label: "Tip",
    labelColor: "text-green-700",
  },
  warning: {
    border: "border-amber-400",
    bg: "bg-amber-50",
    icon: "⚠️",
    label: "Warning",
    labelColor: "text-amber-700",
  },
  note: {
    border: "border-blue-400",
    bg: "bg-blue-50",
    icon: "ℹ️",
    label: "Note",
    labelColor: "text-blue-700",
  },
};

export function Callout({ type = "note", children }: CalloutProps) {
  const style = CALLOUT_STYLES[type];
  return (
    <div
      className={`my-4 flex gap-3 rounded-r-md border-l-4 ${style.border} ${style.bg} px-4 py-3`}
    >
      <span className="mt-0.5 shrink-0 text-base">{style.icon}</span>
      <div>
        <span className={`text-xs font-semibold uppercase tracking-wide ${style.labelColor}`}>
          {style.label}
        </span>
        <div className="mt-1 text-sm text-gray-700">{children}</div>
      </div>
    </div>
  );
}

export const MDX_COMPONENTS = {
  Callout,
};
