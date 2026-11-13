## React SPA rules

- **RS1** `useEffect` dependency arrays that omit a value the effect reads (a stale closure), or a fetch effect
  with no cancellation/ignore flag on unmount or re-run → **major** with a scenario.
- **RS2** A failed or loading query rendered as an empty list or "no results" (B3) → **major**. Errors must
  render an error state.
- **RS3** List keys from array index on lists that reorder, insert or delete → **major**.
- **RS4** `dangerouslySetInnerHTML` with non-sanitised data → **blocker** (B8).
- **RS5** The same derived value computed in two components (B4) instead of one selector/hook.
- **RS6** Interactive elements without an accessible name, or a click handler on a non-button → **minor**,
  unless it blocks keyboard use → **major**.
- **RS7** A token stored in `localStorage` or `sessionStorage` → **major**.
- **RS8** A login return path taken from the URL without checking it is a local path (open redirect) → **major**.
- **RS9** A secret placed in a `VITE_*` variable (it ships to the browser) → **blocker** (B8).
- **RS10** A user-supplied URL put in `href` without checking the scheme (`javascript:`) → **major**.
