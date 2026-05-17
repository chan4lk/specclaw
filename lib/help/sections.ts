export interface HowToSection {
  slug: string;
  title: string;
  description: string;
  screenshotPath: string;
  altText: string;
}

export const HOW_TO_SECTIONS: HowToSection[] = [
  {
    slug: "create-objective",
    title: "Creating an Objective",
    description:
      "Start by defining where your team wants to go. Click \"New Objective\" from the dashboard, write an ambitious qualitative goal, set the time period, and assign an owner.",
    screenshotPath: "/help/screenshots/create-objective.png",
    altText:
      "Screenshot showing the New Objective form with fields for title, time period, team, and owner",
  },
  {
    slug: "add-key-results",
    title: "Adding Key Results",
    description:
      "Key Results make your Objective measurable. Open an Objective and click \"Add Key Result\". Define a start value, target value, and unit of measurement. Aim for 2–4 KRs per Objective.",
    screenshotPath: "/help/screenshots/add-key-results.png",
    altText:
      "Screenshot showing the Add Key Result panel with metric, start value, and target value fields",
  },
  {
    slug: "track-progress",
    title: "Tracking Progress",
    description:
      "Update your Key Result scores regularly. Open a KR, click \"Update Progress\", and enter the current value. Keyflow automatically calculates your 0.0–1.0 score and updates the Objective grade.",
    screenshotPath: "/help/screenshots/track-progress.png",
    altText:
      "Screenshot showing a Key Result detail view with current value input and score indicator",
  },
  {
    slug: "checkin-cfr",
    title: "Running a Check-in",
    description:
      "Check-ins are your weekly CFR moment. Open an OKR and click \"Check In\". Record your status, any blockers, and a brief reflection. These build a history of learning over the cycle.",
    screenshotPath: "/help/screenshots/checkin-cfr.png",
    altText:
      "Screenshot showing the Check-in dialog with status, blockers, and reflection text fields",
  },
  {
    slug: "invite-team",
    title: "Inviting Team Members",
    description:
      "Go to Team Settings and click \"Invite Member\". Enter their email address and choose their role. They'll receive an invitation link to join your team's OKR workspace.",
    screenshotPath: "/help/screenshots/invite-team.png",
    altText:
      "Screenshot showing the Invite Member form with email and role selector",
  },
  {
    slug: "team-dashboard",
    title: "Viewing the Team Dashboard",
    description:
      "The Dashboard shows your team's current OKRs at a glance — Objectives, KR scores, overall grade, and recent check-ins. Use it in team meetings to drive the weekly OKR conversation.",
    screenshotPath: "/help/screenshots/team-dashboard.png",
    altText:
      "Screenshot showing the team dashboard with objective cards, progress bars, and grade indicators",
  },
];
