import { HelpAnchor } from "@/components/help/HelpAnchor";

/**
 * Objectives list page — shown as the main OKR hub.
 * When there are no objectives yet, show an empty state with a help anchor.
 */
export default function ObjectivesPage() {
  const objectives: unknown[] = []; // TODO: fetch from DB/API

  if (objectives.length === 0) {
    return (
      <div className="flex min-h-[60vh] flex-col items-center justify-center gap-4 text-center">
        <div className="text-5xl">🎯</div>
        <h2 className="text-xl font-semibold text-gray-800">No objectives yet</h2>
        <p className="max-w-sm text-sm text-gray-500">
          Objectives define where your team is going. Create your first one to get started.
        </p>
        <div className="flex flex-col items-center gap-2">
          <button
            type="button"
            className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-700"
          >
            New Objective
          </button>
          <HelpAnchor
            href="/help#concepts"
            label="Learn how OKRs work"
            variant="text"
          />
        </div>
      </div>
    );
  }

  return (
    <div>
      {/* TODO: render objectives list */}
    </div>
  );
}

export const metadata = {
  title: "Objectives | Keyflow",
};
