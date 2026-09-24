# Completions Scripts - Which Files To Take Example From

Not: scripts starting with a dot, e.g. `._yt-dlp`. 
Not: auto-generated, huge scripts, like `_ruff`. 
Not: thin wrappers to underlying functions that create the completion code that live outside this repo, like _kitty, ._stern. 
Not: older files (in the git sense) that use bad completions techniques
Not: `_agy` and `_moshi` — not good examples (`_moshi` is auto-generated; `_agy` fails to complete options that appear after positional or subcommand arguments).

Run the following snippet to sort the completion scripts by created and modified dates:
```bash
if [[ -d completions ]]; then
  scripts=(completions/_*)
else
  scripts=(_*)
fi
scripts=(${scripts:#*.zwc})
  
echo "│ File       │ Created                   │ Modified                  │";
echo "│ ────────── │ ───────────────────────── │ ───────────────────────── │";
for file in "${scripts[@]}"; do
  created=$(git log --follow --diff-filter=A --format=%aI -- "$file" | tail -1);
  modified=$(git log --follow -1 --format=%aI -- "$file");
  printf "│ %-10s │ %-25s │ %-25s │\n" "${file##*/}" "$created" "$modified";
done | sort -k4,4r -k6,6r;
```

As of Sep 24, 2026, this is the script's output:
```
│ File       │ Created                   │ Modified                  │
│ ────────── │ ───────────────────────── │ ───────────────────────── │
│ _herdr     │ 2026-07-19T13:05:41+03:00 │ 2026-07-19T13:24:53+03:00 │
│ _agy       │ 2026-06-09T16:13:05+03:00 │ 2026-06-09T17:12:19+03:00 │
│ _ch        │ 2026-04-23T12:59:10+03:00 │ 2026-09-24T11:38:30+03:00 │
│ _skills    │ 2026-04-19T09:27:40+03:00 │ 2026-08-06T13:20:18+03:00 │
│ _pi        │ 2026-04-07T11:32:03+03:00 │ 2026-09-24T11:38:30+03:00 │
│ _gemini    │ 2026-02-08T09:51:15+02:00 │ 2026-06-09T17:12:19+03:00 │
│ _codex     │ 2026-02-08T08:44:51+02:00 │ 2026-05-08T09:15:02+03:00 │
│ _claude    │ 2026-01-27T13:07:39+02:00 │ 2026-09-24T11:38:30+03:00 │
│ _opencode  │ 2026-01-27T12:37:51+02:00 │ 2026-01-27T12:37:51+02:00 │
│ _scraping  │ 2025-12-17T12:11:43+02:00 │ 2025-12-17T12:11:43+02:00 │
│ _delta     │ 2025-11-14T14:32:30+02:00 │ 2025-11-14T14:32:30+02:00 │
│ _str       │ 2025-10-15T11:52:53+03:00 │ 2026-09-10T12:32:53+03:00 │
│ __git      │ 2025-10-15T11:52:53+03:00 │ 2026-08-14T10:11:59+03:00 │
│ _llm       │ 2025-10-15T11:52:53+03:00 │ 2026-08-14T10:11:59+03:00 │
│ _moshi     │ 2025-10-15T11:52:53+03:00 │ 2026-07-09T22:37:20+03:00 │
│ _nav       │ 2025-10-15T11:52:53+03:00 │ 2026-06-11T12:02:36+03:00 │
│ _wacli     │ 2025-10-15T11:52:53+03:00 │ 2026-03-27T17:14:02+03:00 │
│ _ruff      │ 2025-10-15T11:52:53+03:00 │ 2026-01-13T19:48:28+02:00 │
│ _tools     │ 2025-10-15T11:52:53+03:00 │ 2025-11-14T14:37:34+02:00 │
│ _async     │ 2025-10-15T11:52:53+03:00 │ 2025-11-14T14:15:57+02:00 │
│ _util      │ 2025-10-15T11:52:53+03:00 │ 2025-11-14T14:15:57+02:00 │
│ _ghcli     │ 2025-10-15T11:52:53+03:00 │ 2025-10-15T18:54:40+03:00 │
│ _inspect   │ 2025-10-15T11:52:53+03:00 │ 2025-10-15T18:54:40+03:00 │
│ _pretty    │ 2025-10-15T11:52:53+03:00 │ 2025-10-15T18:54:40+03:00 │
│ _fzf       │ 2025-10-15T11:52:53+03:00 │ 2025-10-15T11:52:53+03:00 │
│ _gh        │ 2025-10-15T11:52:53+03:00 │ 2025-10-15T11:52:53+03:00 │
│ _kitty     │ 2025-10-15T11:52:53+03:00 │ 2025-10-15T11:52:53+03:00 │
│ _python    │ 2025-10-15T11:52:53+03:00 │ 2025-10-15T11:52:53+03:00 │
```

Therefore, good example scripts are, best to worst:
- _pi: Router pattern with a nested sub-router (`_pi:auth`), mutually-exclusive option groups declared inline, and half a dozen live dynamic completers backed by real data (provider list, model IDs parsed from `pi --list-models` and cached, installed sources parsed from `pi list`, session IDs scanned off `.jsonl` files on disk, theme names off the filesystem).
- _ch: state-based routing applied consistently across every subcommand, and a well-organized custom parser for the tool-filter mini-language that separates parsing, validation, and match-emission into single-purpose functions.
- _herdr: the most recently created script in this directory (2026-07-19). Clean router pattern, a single reusable `_herdr_object_selectors` helper driven by a live `jq` snapshot instead of duplicated selector logic per subcommand.
- _str: the plain-function case (2026-09-10). Positionals plus options with no router state, `_guard` for numeric values, a `_describe` spec table for `--shape`, and inline mutually-exclusive option groups. Read it before copying `-A '-*'` from the scripts above; see the first gotcha.
- _skills: recently created (2026-04-19). Router pattern with genuine reuse — it sources the real `skills.sh` at completion time instead of reimplementing its logic — though the `sk*` short-command dispatch (`skr`/`ske`/`skcd`/`skt`) repeats similar option/provider-detection logic across several functions instead of sharing one.

Perhaps unintuitively bad examples scripts are:
- __git: created date in the oldest bin and accreted from an older style, despite its recent maintenance
- _ruff: created date in the oldest bin AND auto-generated (360kb)

## Zsh Built-in Completion Files

`/usr/share/zsh/5.9/functions/_*` contains thousands of high quality zsh built-in completion files. Some of them are huge (e.g., `_git` at 8503 lines, `_gcc` at 2287 lines) so not a good idea to load and clog them into the context.

### 3 Recommended Files to Read

Not too long but exemplify a wide variety of completion techniques:

| File     | Lines | Key Techniques |
| -------- | ----- | -------------- |
| `_ps`    | 244   | `_call_program`, `_describe`, `_sequence`, `compset -P`, many completers (`_pids`, `_groups`, `_users`, `_ttys`) |
| `_make`  | 273   | File parsing, helper functions, associative arrays, `zstyle`, `_guard` |
| `_rsync` | 273   | `_wanted`/`_combination`, remote file completion, `compset -P/S`, `_call_program` |

### Know all the subcommands, options, and their sub-subcommands and options before writing the script

Recursively traverse the tool's `--help` pages down to the leaves.
`helpall <command>` does this for you: it prints the whole help tree in one pass (verified with `agy`, `claude`, `gemini`, and `pi`). Use the manual method below only when `helpall` misses a level.
E.g., `claude --help | tee -a /tmp/claude-help-all.txt` reveals (truncated):

```
Usage: claude [options] [command] [prompt]
Arguments:
  prompt                                            Your prompt

Options:
  --add-dir <directories...>                        Additional directories to allow tool

Commands:
  plugin                                            Manage Claude Code plugins
  mcp                                               Configure and manage MCP servers
```

Therefore, immediately run `claude plugin --help | tee -a /tmp/claude-help-all.txt` and `claude mcp --help | tee -a /tmp/claude-help-all.txt`.
`claude plugin --help` will itself reveal more subcommands (`claude plugin marketplace`), which in turn also have nested subcommands (`claude plugin marketplace list`), and so on. Traverse exhaust the whole tree breadth-first to cultivate a complete help-all file. Only then apply the best practices of the good example scripts listed above and proceed to implement.

## Test a Completion Script

Test in a real completion session, not by reading the script. Start a `zsh -f -i` under `zsh/zpty`, run `compinit` with this directory first in `fpath`, type a partial command line, and send a Tab.

`comptest.zsh` in this directory does this. Run `./comptest.zsh 'claude plugin ma' 'pi --provider '` to see what Tab does for each line. It is a starting point, not a rule. Write a custom temporary script when that suits the task better.

Two traps:
1. The pty shell runs your input only while you keep reading its output. After each `zpty -w`, drain with repeated `zpty -r -t` calls and short sleeps. If you do not, the shell echoes the line and never runs it.
2. A `compadd` override that records matches is useful to see the lists that `_describe` builds, but it is not a full check. It misses many flag options from `_arguments`, and it inserts nothing. For the final check, use the unmodified completion system and read back the command line or the match listing after the Tab.

## Gotchas

### Options after positionals: plain `_arguments` already does it

Plain `_arguments` completes options after positional arguments by default. Do not add `-A '-*'` for that: the zsh manual defines `-A` as "do not complete options after the first non-option argument", so it disables exactly what you want. Use `-A` only where it belongs: a wrapper whose first positional is another command, like `sudo`.

`_str` is the reference example for the plain form:

```zsh
_arguments \
  "${options[@]}" \
  '1:string:' \
  '2:max length:_guard "[0-9]#" "max length"'
```

### Rest states are for subcommand dispatch

A `'*:: :->rest'` state, as in `_pi` and `_herdr`, exists to dispatch on `line[1]`. It is not a way to re-enable options. With `*::` the rest state's `words` starts at the first positional, which then plays the command word. That only works when there is exactly one positional before the options. A second positional, as in `shorten STRING MAX_LENGTH`, becomes a stray argument in the rest call and completion fails.

Avoid using `_default` as a rest completion unless files, commands, and other default completions are valid at that position. `_default` can mask the original "no more arguments" problem by introducing file completion where only options should be offered.

### Guard root positional completions

In router-style completions, first-argument completers can leak into later positions if the root state is too broad. Restrict first-argument behavior to the first positional. `words[1]` is the command itself (`claude`, or `plugin` inside a `*::` rest state), so the first positional is at `CURRENT == 2`. A `CURRENT == 1` guard never matches and silently disables the subcommand list:

```zsh
case $state in
  (root_arg)
    if (( CURRENT == 2 )); then
      _describe -t subcommands 'commands' subcommands
      _session_selector
    fi
    ;;
esac
```

Without this guard, completions for the first positional argument may appear after that argument has already been supplied.
