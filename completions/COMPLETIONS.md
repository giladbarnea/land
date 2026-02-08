# Completions Scripts - Which Files To Take Example From

Not: scripts starting with a dot, e.g. `._yt-dlp`. 
Not: auto-generated, huge scripts, like `_ruff`. 
Not: thin wrappers to underlying functions that create the completion code that live outside this repo, like _kitty, ._stern. 
Not: older files (in the git sense) that use bad completions techniques

Run the following snippet to sort the completion scripts by created and modified dates:
```bash
if [[ -d completions ]]; then
  scripts=(completions/_*)
else
  scripts=(_*)
fi
  
echo "│ File       │ Created                   │ Modified                  │";
echo "│ ────────── │ ───────────────────────── │ ───────────────────────── │";
for file in "${scripts[@]}"; do
  created=$(git log --follow --diff-filter=A --format=%aI -- "$file" | tail -1);
  modified=$(git log --follow -1 --format=%aI -- "$file");
  printf "│ %-10s │ %-25s │ %-25s │\n" "${file##*/}" "$created" "$modified";
done | sort -k4,4r -k6,6r;
```

As of Feb 08, 2026, this is the script's output:
```
│ File       │ Created                   │ Modified                  │
│ ────────── │ ───────────────────────── │ ───────────────────────── │
│ _gemini    │ 2026-02-08T09:51:15+02:00 │ 2026-02-08T11:09:58+02:00 │
│ _codex     │ 2026-02-08T08:44:51+02:00 │ 2026-02-08T08:44:51+02:00 │
│ _claude    │ 2026-01-27T13:07:39+02:00 │ 2026-01-27T13:07:39+02:00 │
│ _opencode  │ 2026-01-27T12:37:51+02:00 │ 2026-01-27T12:37:51+02:00 │
│ _codanna   │ 2026-01-13T17:10:52+02:00 │ 2026-01-13T19:45:15+02:00 │
│ _scraping  │ 2025-12-17T12:11:43+02:00 │ 2025-12-17T12:11:43+02:00 │
│ _delta     │ 2025-11-14T14:32:30+02:00 │ 2025-11-14T14:32:30+02:00 │
│ _git       │ 2025-10-15T11:52:53+03:00 │ 2026-01-27T12:37:51+02:00 │
│ _ruff      │ 2025-10-15T11:52:53+03:00 │ 2026-01-13T19:48:28+02:00 │
│ _tools     │ 2025-10-15T11:52:53+03:00 │ 2025-11-14T14:37:34+02:00 │
│ _llm       │ 2025-10-15T11:52:53+03:00 │ 2025-11-14T14:37:28+02:00 │
│ _async     │ 2025-10-15T11:52:53+03:00 │ 2025-11-14T14:15:57+02:00 │
│ _util      │ 2025-10-15T11:52:53+03:00 │ 2025-11-14T14:15:57+02:00 │
│ _ghcli     │ 2025-10-15T11:52:53+03:00 │ 2025-10-15T18:54:40+03:00 │
│ _inspect   │ 2025-10-15T11:52:53+03:00 │ 2025-10-15T18:54:40+03:00 │
│ _pretty    │ 2025-10-15T11:52:53+03:00 │ 2025-10-15T18:54:40+03:00 │
│ _fzf       │ 2025-10-15T11:52:53+03:00 │ 2025-10-15T11:52:53+03:00 │
│ _gh        │ 2025-10-15T11:52:53+03:00 │ 2025-10-15T11:52:53+03:00 │
│ _kitty     │ 2025-10-15T11:52:53+03:00 │ 2025-10-15T11:52:53+03:00 │
│ _nav       │ 2025-10-15T11:52:53+03:00 │ 2025-10-15T11:52:53+03:00 │
│ _python    │ 2025-10-15T11:52:53+03:00 │ 2025-10-15T11:52:53+03:00 │
│ _str       │ 2025-10-15T11:52:53+03:00 │ 2025-10-15T11:52:53+03:00 │
```

Therefore, good example scripts are:
- _gemini: most recently created AND updated. I'm signing here that it's the best script in this directory. Inspired by `/Users/giladbarnea/.openclaw/completions/openclaw.zsh`. It is superior because: 
    * it leverages separation of data arrays (`local -a options`) from logic before passing them to `_arguments`, instead of a massive, unreadable `_arguments` call
    * modular dispatching (the 'Router') pattern, which uses a root function `_gemini` that acts as a router, which doesn't know *how* to complete `mcp add`, it just knows to pass control to `_gemini:mcp`, instead of nesting logic deep inside the root function 
    * state-based argument handling: uses `_arguments -C` with `->state` to handle complex flows where the completion needs to change based on the position (Command vs. Arguments), rather than a single complex argument specification
    * Robust registration (the footer): end with an explicit `compdef ...` rather than executing the function.
- _codex: very recently created AND updated
- _claude: recently created AND updated

Perhaps unintuitively bad examples scripts are:
- _git: created date in the oldest bin
- _ruff: created date in the oldest bin AND auto-generated (360kb)
