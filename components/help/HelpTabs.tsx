"use client";

import { useEffect, useState } from "react";

export type HelpTab = "how-to-use" | "concepts";

interface HelpTabsProps {
  activeTab: HelpTab;
  onTabChange: (tab: HelpTab) => void;
}

const TABS: { id: HelpTab; label: string }[] = [
  { id: "how-to-use", label: "How to Use" },
  { id: "concepts", label: "OKR Concepts" },
];

export function HelpTabs({ activeTab, onTabChange }: HelpTabsProps) {
  return (
    <div className="flex gap-1 border-b border-gray-200">
      {TABS.map((tab) => (
        <button
          key={tab.id}
          type="button"
          onClick={() => onTabChange(tab.id)}
          className={`px-4 py-2.5 text-sm font-medium transition-colors ${
            activeTab === tab.id
              ? "border-b-2 border-blue-600 text-blue-600"
              : "text-gray-500 hover:text-gray-800"
          }`}
        >
          {tab.label}
        </button>
      ))}
    </div>
  );
}

export function useHashTab(): [HelpTab, (tab: HelpTab) => void] {
  const [activeTab, setActiveTab] = useState<HelpTab>("how-to-use");

  useEffect(() => {
    const hash = window.location.hash.replace("#", "") as HelpTab;
    if (hash === "concepts" || hash === "how-to-use") {
      setActiveTab(hash);
    }
  }, []);

  const handleTabChange = (tab: HelpTab) => {
    setActiveTab(tab);
    window.history.replaceState(null, "", `#${tab}`);
  };

  return [activeTab, handleTabChange];
}
