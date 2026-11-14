// git.base_branch from .specclaw/config.yaml, by the same rules as lib/base-ref.sh (base_config_branch);
// tests/fixtures/base-branch.tsv holds the cases both are tested against.
// The `git:` block runs until a column-0 line that is not blank and not a comment; the key may have any
// indent; a comment needs a space before its `#` (as yaml_val); one pair of surrounding quotes is dropped.
const GIT_BLOCK = /^git:[^\n]*\n((?:[ \t]*\n|[ \t]+[^\n]*\n?|#[^\n]*\n?)*)/m
const KEY = /^[ \t]+base_branch:([^\n]*)$/m

export function baseBranchFrom(config: string): string {
  const value = KEY.exec(GIT_BLOCK.exec(config)?.[1] ?? '')?.[1] ?? ''
  return value.replace(/[ \t]+#.*$/, '').trim().replace(/^"(.*)"$/, '$1').replace(/^'(.*)'$/, '$1')
}
