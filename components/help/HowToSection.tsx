import type { HowToSection as HowToSectionData } from "@/lib/help/sections";
import { ScreenshotViewer } from "./ScreenshotViewer";

interface HowToSectionProps {
  section: HowToSectionData;
}

export function HowToSection({ section }: HowToSectionProps) {
  return (
    <section
      id={section.slug}
      className="scroll-mt-24 border-b border-gray-100 py-8 last:border-0"
    >
      <h2 className="mb-2 text-xl font-semibold text-gray-900">{section.title}</h2>
      <p className="mb-4 text-sm text-gray-600">{section.description}</p>
      <ScreenshotViewer src={section.screenshotPath} alt={section.altText} />
    </section>
  );
}
