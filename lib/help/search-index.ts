import { HOW_TO_SECTIONS } from "./sections";

export interface SearchRecord {
  id: string;
  title: string;
  description: string;
  slug: string;
  tab: "how-to-use" | "concepts";
}

const CONCEPT_RECORDS: SearchRecord[] = [
  {
    id: "concept-objective",
    title: "What is an Objective?",
    description:
      "Objectives are ambitious, qualitative goals that define where you want to go. They cascade from company to team to individual.",
    slug: "what-is-objective",
    tab: "concepts",
  },
  {
    id: "concept-key-result",
    title: "What Makes a Good Key Result?",
    description:
      "Key Results are specific, measurable outcomes. They follow the pattern: verb + metric + from X to Y. Outcome-based, not activity-based.",
    slug: "good-key-result",
    tab: "concepts",
  },
  {
    id: "concept-scoring",
    title: "Scoring & Grading OKRs",
    description:
      "OKRs are scored 0.0–1.0. A score of 0.7 is the sweet spot — it means the goal was ambitious enough. 1.0 consistently means goals are too easy.",
    slug: "scoring-grading",
    tab: "concepts",
  },
  {
    id: "concept-cfrs",
    title: "CFRs: Conversations, Feedback, Recognition",
    description:
      "CFRs are the continuous performance practices that make OKRs work. Weekly check-ins, real-time feedback, and timely recognition replace annual reviews.",
    slug: "cfrs",
    tab: "concepts",
  },
  {
    id: "concept-cadence",
    title: "OKR Cadence",
    description:
      "OKRs run on nested cycles: annual company objectives, quarterly team OKRs, and weekly CFR check-ins. Each level serves the next.",
    slug: "cadence",
    tab: "concepts",
  },
  {
    id: "concept-mistakes",
    title: "Common OKR Mistakes",
    description:
      "Tasks as KRs, too many objectives, sandbagging, set-and-forget, no vertical alignment, and using OKRs as performance reviews.",
    slug: "common-mistakes",
    tab: "concepts",
  },
];

export const SEARCH_RECORDS: SearchRecord[] = [
  ...HOW_TO_SECTIONS.map((s) => ({
    id: `how-to-${s.slug}`,
    title: s.title,
    description: s.description,
    slug: s.slug,
    tab: "how-to-use" as const,
  })),
  ...CONCEPT_RECORDS,
];
