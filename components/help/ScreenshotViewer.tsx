"use client";

import Image from "next/image";
import { useState } from "react";

interface ScreenshotViewerProps {
  src: string;
  alt: string;
}

export function ScreenshotViewer({ src, alt }: ScreenshotViewerProps) {
  const [zoomed, setZoomed] = useState(false);

  return (
    <>
      <button
        type="button"
        onClick={() => setZoomed(true)}
        className="group relative block w-full overflow-hidden rounded-lg border border-gray-200 shadow-sm transition hover:shadow-md"
        aria-label={`Zoom in: ${alt}`}
      >
        <Image
          src={src}
          alt={alt}
          width={1280}
          height={720}
          className="h-auto w-full object-contain"
          unoptimized
        />
        <div className="absolute inset-0 flex items-center justify-center bg-black/0 transition group-hover:bg-black/10">
          <span className="rounded-full bg-white/90 px-3 py-1 text-xs font-medium text-gray-700 opacity-0 shadow group-hover:opacity-100">
            Click to enlarge
          </span>
        </div>
      </button>

      {zoomed && (
        <div
          role="dialog"
          aria-label="Zoomed screenshot"
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 p-4"
          onClick={() => setZoomed(false)}
        >
          <div className="relative max-h-full max-w-5xl overflow-auto" onClick={(e) => e.stopPropagation()}>
            <button
              type="button"
              onClick={() => setZoomed(false)}
              className="absolute right-2 top-2 z-10 rounded-full bg-white/90 px-3 py-1 text-xs font-medium text-gray-700 shadow hover:bg-white"
            >
              Close ✕
            </button>
            <Image
              src={src}
              alt={alt}
              width={1280}
              height={720}
              className="h-auto w-full rounded-lg object-contain"
              unoptimized
            />
          </div>
        </div>
      )}
    </>
  );
}
