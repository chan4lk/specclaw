"use client";

import type { MDXRemoteSerializeResult } from "next-mdx-remote";
import { MDXRemote } from "next-mdx-remote";
import { MDX_COMPONENTS } from "./mdx-components";

interface ConceptsSectionProps {
  slug: string;
  compiledSource: MDXRemoteSerializeResult;
}

export function ConceptsSection({ slug, compiledSource }: ConceptsSectionProps) {
  return (
    <section
      id={slug}
      className="scroll-mt-24 border-b border-gray-100 py-8 last:border-0"
    >
      <div className="prose prose-gray max-w-none overflow-x-hidden prose-headings:font-semibold prose-a:text-blue-600 prose-table:text-sm [&_table]:w-full [&_table]:overflow-x-auto [&_table]:block">
        <MDXRemote {...compiledSource} components={MDX_COMPONENTS} />
      </div>
    </section>
  );
}
