"use client";

import Fuse from "fuse.js";
import { useEffect, useMemo, useRef, useState } from "react";
import type { SearchRecord } from "@/lib/help/search-index";
import { SEARCH_RECORDS } from "@/lib/help/search-index";
import type { HelpTab } from "./HelpTabs";

interface HelpSearchProps {
  onNavigate: (slug: string, tab: HelpTab) => void;
}

export function HelpSearch({ onNavigate }: HelpSearchProps) {
  const [query, setQuery] = useState("");
  const [open, setOpen] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);

  const fuse = useMemo(
    () =>
      new Fuse<SearchRecord>(SEARCH_RECORDS, {
        keys: ["title", "description"],
        threshold: 0.4,
        includeScore: true,
      }),
    []
  );

  const results = useMemo(() => {
    if (!query.trim()) return [];
    return fuse.search(query).slice(0, 6);
  }, [fuse, query]);

  useEffect(() => {
    function handleClickOutside(e: MouseEvent) {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setOpen(false);
      }
    }
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  function handleSelect(record: SearchRecord) {
    setQuery("");
    setOpen(false);
    onNavigate(record.slug, record.tab);
  }

  return (
    <div ref={containerRef} className="relative w-full max-w-md">
      <div className="relative">
        <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-gray-400">
          🔍
        </span>
        <input
          ref={inputRef}
          type="search"
          placeholder="Search help..."
          value={query}
          onChange={(e) => {
            setQuery(e.target.value);
            setOpen(true);
          }}
          onFocus={() => setOpen(true)}
          className="w-full rounded-lg border border-gray-200 bg-white py-2 pl-9 pr-4 text-sm shadow-sm outline-none focus:border-blue-400 focus:ring-2 focus:ring-blue-100"
        />
      </div>

      {open && (
        <div className="absolute left-0 right-0 top-full z-40 mt-1 overflow-hidden rounded-lg border border-gray-200 bg-white shadow-lg">
          {results.length === 0 && query.trim() ? (
            <p className="px-4 py-3 text-sm text-gray-500">No results found.</p>
          ) : (
            <ul>
              {results.map(({ item }) => (
                <li key={item.id}>
                  <button
                    type="button"
                    className="flex w-full flex-col gap-0.5 px-4 py-2.5 text-left hover:bg-gray-50"
                    onClick={() => handleSelect(item)}
                  >
                    <span className="text-sm font-medium text-gray-900">{item.title}</span>
                    <span className="line-clamp-1 text-xs text-gray-500">{item.description}</span>
                    <span className="text-xs text-blue-500 capitalize">
                      {item.tab === "how-to-use" ? "How to Use" : "OKR Concepts"}
                    </span>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
    </div>
  );
}
