import { readdir, readFile } from "fs/promises";
import path from "path";
import { serialize } from "next-mdx-remote/serialize";
import { HelpPage } from "@/components/help/HelpPage";
import { HOW_TO_SECTIONS } from "@/lib/help/sections";

async function loadConceptContents() {
  const dir = path.join(process.cwd(), "content/help/okr-concepts");
  const files = (await readdir(dir)).filter((f) => f.endsWith(".mdx")).sort();

  return Promise.all(
    files.map(async (filename) => {
      const raw = await readFile(path.join(dir, filename), "utf-8");
      const compiledSource = await serialize(raw, {
        parseFrontmatter: true,
      });
      const slug = (compiledSource.frontmatter as { slug?: string })?.slug ?? filename.replace(".mdx", "");
      return { slug, compiledSource };
    })
  );
}

export default async function HelpPageRoute() {
  const conceptContents = await loadConceptContents();

  return (
    <HelpPage
      howToSections={HOW_TO_SECTIONS}
      conceptContents={conceptContents}
    />
  );
}

export const metadata = {
  title: "Help Center | Keyflow",
  description: "Learn how to use Keyflow and understand John Doerr's OKR framework.",
};
