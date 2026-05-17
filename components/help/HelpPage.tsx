"use client";

import { useCallback, useEffect, useRef } from "react";
import type { MDXRemoteSerializeResult } from "next-mdx-remote";
import type { HowToSection } from "@/lib/help/sections";
import { ConceptsSection } from "./ConceptsSection";
import { HelpSearch } from "./HelpSearch";
import { HelpTabs, useHashTab } from "./HelpTabs";
import { HowToSection as HowToSectionComponent } from "./HowToSection";
import type { HelpTab } from "./HelpTabs";

interface ConceptContent {
  slug: string;
  compiledSource: MDXRemoteSerializeResult;
}

interface HelpPageProps {
  howToSections: HowToSection[];
  conceptContents: ConceptContent[];
}

export function HelpPage({ howToSections, conceptContents }: HelpPageProps) {
  const [activeTab, setActiveTab] = useHashTab();
  const contentRef = useRef<HTMLDivElement>(null);

  function handleNavigate(slug: string, tab: HelpTab) {
    setActiveTab(tab);
    setTimeout(() => {
      const el = document.getElementById(slug);
      if (el) el.scrollIntoView({ behavior: "smooth", block: "start" });
    }, 50);
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <div className="mx-auto max-w-4xl px-4 py-8">
        {/* Header */}
        <div className="mb-6 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <h1 className="text-2xl font-bold text-gray-900">Help Center</h1>
            <p className="mt-1 text-sm text-gray-500">
              Learn how to use Keyflow and understand OKR concepts.
            </p>
          </div>
          <HelpSearch onNavigate={handleNavigate} />
        </div>

        {/* Tabs */}
        <HelpTabs activeTab={activeTab} onTabChange={setActiveTab} />

        {/* Content */}
        <div ref={contentRef} className="mt-2 rounded-lg bg-white p-6 shadow-sm">
          {activeTab === "how-to-use" ? (
            <div>
              {howToSections.map((section) => (
                <HowToSectionComponent key={section.slug} section={section} />
              ))}
            </div>
          ) : (
            <div>
              {conceptContents.map(({ slug, compiledSource }) => (
                <ConceptsSection key={slug} slug={slug} compiledSource={compiledSource} />
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
