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
done | sort -t "$(printf '\x1f')" -k3,3r -k4,4r;
```

As of Jan 27, 2026, this is the script’s output:
```
│ File      │ Created                   │ Modified                  │
│ ───────── │ ───────────────────────── │ ───────────────────────── │
│ _opencode │ 2026-01-27T12:37:51+02:00 │ 2026-01-27T12:37:51+02:00 │
│ _codanna  │ 2026-01-13T17:10:52+02:00 │ 2026-01-13T19:45:15+02:00 │
│ _scraping │ 2025-12-17T12:11:43+02:00 │ 2025-12-17T12:11:43+02:00 │
│ _delta    │ 2025-11-14T14:32:30+02:00 │ 2025-11-14T14:32:30+02:00 │
│ _git      │ 2025-10-15T11:52:53+03:00 │ 2026-01-27T12:37:51+02:00 │
│ _ruff     │ 2025-10-15T11:52:53+03:00 │ 2026-01-13T19:48:28+02:00 │
│ _tools    │ 2025-10-15T11:52:53+03:00 │ 2025-11-14T14:37:34+02:00 │
│ _llm      │ 2025-10-15T11:52:53+03:00 │ 2025-11-14T14:37:28+02:00 │
│ _async    │ 2025-10-15T11:52:53+03:00 │ 2025-11-14T14:15:57+02:00 │
│ _util     │ 2025-10-15T11:52:53+03:00 │ 2025-11-14T14:15:57+02:00 │
│ _ghcli    │ 2025-10-15T11:52:53+03:00 │ 2025-10-15T18:54:40+03:00 │
│ _inspect  │ 2025-10-15T11:52:53+03:00 │ 2025-10-15T18:54:40+03:00 │
│ _pretty   │ 2025-10-15T11:52:53+03:00 │ 2025-10-15T18:54:40+03:00 │
│ _fzf      │ 2025-10-15T11:52:53+03:00 │ 2025-10-15T11:52:53+03:00 │
│ _gh       │ 2025-10-15T11:52:53+03:00 │ 2025-10-15T11:52:53+03:00 │
│ _kitty    │ 2025-10-15T11:52:53+03:00 │ 2025-10-15T11:52:53+03:00 │
│ _nav      │ 2025-10-15T11:52:53+03:00 │ 2025-10-15T11:52:53+03:00 │
│ _python   │ 2025-10-15T11:52:53+03:00 │ 2025-10-15T11:52:53+03:00 │
│ _str      │ 2025-10-15T11:52:53+03:00 │ 2025-10-15T11:52:53+03:00 │
```

Therefore, good example scripts are:
- _opencode: recently created AND updated
- _codanna: recently created AND updated
- _scraping: recently created AND updated

Perhaps unintuitively bad examples scripts are:
- _git: created date in the oldest bin
- _ruff: created date in the oldest bin AND auto-generated (360kb)