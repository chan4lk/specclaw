# Project presets

Coding presets for this repo. Lean build reads every file `specclaw-presets .specclaw` prints:
`base` first, then each name in `config.yaml` `presets: [..]`.

- `<name>.md` here **replaces** the built-in preset of the same name (`base`, `dotnet`, `node`,
  `nextjs`, `python`, `react-spa`), or adds a new one (`acme-dotnet`, `go`). List it in `presets:`.
- To keep a preset and add your rules after it, open the file with frontmatter:

  ```markdown
  ---
  extends: dotnet
  ---
  # Our .NET rules
  ```

  `extends: dotnet` in `dotnet.md` keeps the built-in dotnet. One level only: a parent's own
  `extends` is not followed and is reported. `extends` is the only key; anything
  else in the frontmatter, or a missing closing `---`, is reported as an error. An `extends:` line
  outside the frontmatter is ignored with a warning.
- Names are lowercase letters, digits and hyphens. Unknown names are reported by `specclaw-presets`.
- Presets are prose guidance. `specclaw-preset-check` only enforces the built-in mechanical rules.
