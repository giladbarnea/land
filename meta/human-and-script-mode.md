---
last_updated: 2026-10-28T13-48
---

# Human mode and script mode

`land` functions run in many contexts. A person can type in a terminal, a cron job can run unattended, and an AI agent can run a shell that it drives. This document explains how `land` decides which features each context gets, and why. The decisions were made on 2026-10-11, after experiments in every agent harness that Gilad uses.

## The two modes

**Human mode** is only Gilad typing directly in a terminal. This includes kitty, herdr panes (also over SSH and Moshi), and the VS Code and Cursor integrated terminals. Human mode gets colors and interactive prompts.

**Script mode** is everything else: unattended scripts, background programs, and every AI agent, even an attended agent whose shell is interactive. Script mode gets no colors and no prompts. It still gets logs and all tools.

## Gates

| Function (`util.sh`) | Question it answers | Used for |
|---|---|---|
| `is_agent` | Does an AI agent harness run this shell? | Every mode decision |
| `is_human` | `is_interactive && [[ -t 0 && -t 2 ]] && ! is_agent` | Prompts: `input`, `confirm`, `ghg-run`, the `llm` viewer |
| `IS_HUMAN` | Human session at startup, before instant prompt redirects stdin and stderr | Loading the `eza` function for `ls`; `skills sync` cleanup confirmation |
| `is_piped` | Is stdin a pipe or a regular file? | Functions that read input from stdin |
| `is_piping` | Is stdout something other than a terminal? | Output formatting |
| `is_interactive` | Did zsh start with `-i`? | Loading completions, hooks, and the `cd` patch |

`log` (`log.sh`) uses its own color check: `[[ -t 2 ]] && ! is_agent`.

## What each context looks like

The agent rows are measured. A dash means not measured.

| Context | `$-` has `i` | stdin | stderr | Agent variable | Mode |
|---|---|---|---|---|---|
| Gilad in a herdr pane | yes | terminal | terminal | none | human |
| Claude Code, Bash tool and `zshi -c` | with `zshi` only | `/dev/null` | pipe | `CLAUDECODE=1`, `AI_AGENT=claude-code_…` | script |
| Pi, `zsh` tool | yes | `/dev/null` | – | `PI_CODING_AGENT=true` | script |
| Pi, `bash` tool | no | `/dev/null` | – | `PI_CODING_AGENT=true` | script |
| Codex, shell tool and `zshi -c` | with `zshi` only | `/dev/null` | – | `CODEX_THREAD_ID=<id>` | script |
| cron, background job | no | – | not a terminal | none | script |

## Why each decision

### 1. Detect agents by environment variables

Agent shells are often interactive. `zshi` is `zsh -i`, and Pi's `zsh` tool is interactive too. So `$-` cannot tell an agent from a person. Each harness sets a variable that a person's terminal does not have:

- `CLAUDECODE` = `1` or `true`.
- `PI_CODING_AGENT` = `true` or `1`.
- `CODEX_THREAD_ID` is not empty.
- `AI_AGENT` is not empty. It is a generic variable that is independent of the harness.
- `CURSOR_AGENT` is not empty. It costs nothing to keep.

Two variables are excluded on purpose. `CODEX_SANDBOX` was absent in a Codex run with full access, so it is not reliable. `CODEX_CI` is not used, by Gilad's choice. `VSCODE_INJECTION` and `CURSOR_TRACE_ID` mark IDE terminals, and a person types in those terminals, so they are not agent signals.

### 2. Stdin-based prompts need terminal stdin and stderr

`input` writes its question to stderr and reads the answer from stdin. It requires both to be terminals. Every agent harness gives `/dev/null` as stdin. This alone puts agents in script mode, and `! is_agent` is a second, independent check. `input` refuses with a warning and returns 1 in script mode, and `confirm` uses `input`.

`skills sync` cleanup instead uses `IS_HUMAN` and opens `/dev/tty` for its questions and answers. Piped input or output does not suppress these questions. Without a human session or a usable terminal, it keeps each obsolete link and reports its absolute link path.

### 3. Log colors use stderr, not `is_human`

`log` writes to stderr, so colors depend on stderr being a terminal. `log` does not use `is_human`, because `is_human` also requires stdin to be a terminal. With `is_human`, `echo x | fn` in Gilad's terminal would lose its log colors. A script that Gilad starts by hand from a terminal also keeps colors, because a person sees it.

### 4. Logs stay on in script mode, without colors

Previously, `environment.sh` set `LAND_LOG=false` for agents and non-interactive shells, which turned all logs off. Agents then did not see warnings or errors. Experiments showed that every harness shows stderr to the model:

| Harness | Tools | Sees stderr | Labeled as stderr | Color codes |
|---|---|---|---|---|
| Claude Code | Bash, `zshi -c` | yes | no, mixed with stdout | raw bytes |
| Pi | bash, zsh, codemode | yes | no | raw bytes in the tool output |
| Codex | shell, `zshi -c` | yes | no | raw bytes |

So logs stay on stderr, and `log` removes all color codes in script mode. Raw color codes are only noise for a model. `LAND_LOG=false` still turns logs off when a person sets it by hand.

The `[caller][LEVEL]` prefix is the intended format in both modes. Previously, the level parsing depended on `is_interactive`, which printed `warn disk low` in non-interactive shells. Now the level always shows as `[WARN]`.

### 5. `is_piped` means "a pipe or a file", not "not a terminal"

The old check was `[[ ! -t 0 ]]`. In agent shells stdin is `/dev/null`, so every function took its "read stdin" path. `indent hello 4` then read an empty stdin, used `hello` as the width, and failed. The new check `[[ -p /dev/stdin || -f /dev/stdin ]]` is true for `echo x | fn`, `fn < file`, and `fn <<< x`. It is false for a terminal and for `/dev/null`.

### 6. `~/.zshrc` repeats the agent check

`~/.zshrc` decides whether to load Oh My Zsh and `land` at all. It makes this decision before `land` loads, so it cannot call `is_agent`. It repeats the same variable list, with a comment that says to keep the two lists in sync. Before loading Powerlevel10k instant prompt, it also sets the non-exported global `IS_HUMAN` to `true` or `false`. Child shells calculate their own value.

`FORCE_OMZ=true` skips that early return. `~/.zshrc` sets it for herdr, SSH, Moshi, and VS Code or Cursor terminals. So an agent inside herdr also loads `land`. This is intentional. `land` gives agents useful functions and `PATH` entries. The gates in section "Gates" limit what an agent gets, at call time.

### 7. VS Code and Cursor terminals act like the daily terminal

These terminals do not set `KITTY_WINDOW_ID`, so `~/.zshrc` used to return early and skip `land`. Now `TERM_PROGRAM=vscode` sets `FORCE_OMZ=true`. Cursor sets the same `TERM_PROGRAM`.

### 8. The `cd` patch follows the same rule

`nav.sh` replaces `cd` only when `is_interactive && ! is_agent` is true. Previously it used a `CD_PATCH` variable that `environment.sh` set from an older, Claude-only check.

## Rules to keep

1. Change the agent list in `is_agent` and in `~/.zshrc` together.
2. Gate prompts that read stdin with `is_human`. The `skills sync` cleanup prompt uses `IS_HUMAN` and `/dev/tty` instead.
3. Send colored output through `log`, or gate it with `[[ -t <fd> ]] && ! is_agent` for the file descriptor that gets the output.
4. Check live terminal descriptors at call time for prompts. Startup choices such as the `eza` function for `ls` use `IS_HUMAN`, because instant prompt temporarily redirects stdin and stderr. The `cd` patch uses `is_interactive && ! is_agent` at source time.

## Read stdin only when no input argument was given

A function that takes its input "from an argument or from stdin" reads stdin only when the input argument is absent. An empty string is a valid input, not a missing one.

- A function with one input argument checks `(( $# == 0 )) && is_piped`.
- A function that also takes options counts its positional arguments while it parses them (`positional_count`). It reads stdin only when the count is zero.

Before 2026-10-11, about 40 functions used `[[ ! "$1" ]] && is_piped`, which also treats `""` as missing. Two cases broke:

1. In `while read -r line; do fn "$line"; done < file`, an empty line made `fn` read the rest of the loop's input. The result was wrong and the loop lost lines.
2. If stdin was a pipe that stayed open without data, `fn ""` blocked until the writer closed it.

`is_piped` alone cannot prevent these cases, because the stdin is a real pipe in both.

The cost is small and accepted: a wrapper such as `myfn() { upper "$1"; }` no longer passes piped input through when it is called with no arguments. Such a wrapper must forward `"$@"`.

## How to verify

1. **Human side:** open a herdr pane with `herdr pane split`, run commands in it with `herdr pane run`, and read the colors with `herdr pane read --format ansi`.
2. **Agent side:** run `zshi -c '…'` from an agent shell.
3. **`~/.zshrc` early return:** start `zsh -i` with `env -u KITTY_WINDOW_ID -u HERDR_ENV -u FORCE_OMZ -u SSH_CLIENT -u MOSHI_CLIENT` and add one variable to test.
