---
description: Context for effectively maintaining and updating the completions/_llm file, as well as spotting discrepancies between it and the implementation layer in llm.zsh.
relevant_files: llm.zsh, completions/_llm
note: This document is probably outdated to some extent. Take the principles in it seriously, but don't take precise code references as gospel.
---

# LLM Completions & Implementation Layer Design

## 1. Mismatch Categories & Priorities
* **Hard Mismatch**: The completion shows an option that should be hidden (false positive), or it misses an option that should be shown (false negative), based on the docstring and looking at how the implementation parses the arguments.
* **Soft Mismatch**: The implementation has a function, but there is no corresponding completion for it.

## 2. Hierarchy & Mapping

1. **Internal wrapper hierarchy (llm.zsh):**

The `llm.zsh` file is a big wrapper around the third-party `llm` tool (by simonw). The third-party tool is invoked as `command llm …`.
At the top, it contains the "main" function, `llm`, which is a wrapper around `command llm …`.
This `llm` wrapper belongs to a group of functions that directly invoke `command llm …` — "Primary wrappers".
There is a second group of functions that don't call `command llm`, but instead call other functions in `llm.zsh` — "Secondary wrappers".
“Private” function for internal use start with a dot, e.g., `.llm-has-opt`.
“Public” function, meant to be used by the user, are the ones that are not prefixed with a dot. For example, `llm`, `llm-logs`, `pyai`, etc.


2. **Third-party tool subcommand hierarchy (command llm …):**

`command llm` has a default child-subcommand for every subcommand.

Formally, the syntax is:

```
llm [command [subcommand]] [options...]
```
You can specify nothing, or a command, or a command and a subcommand.
If you specify nothing, the default command — `prompt` — is used.
If you specify almost any command, you can omit the subcommand, and the default subcommand for that command will be used.

For example:
- `command llm` defaults to `command llm prompt`.
- `command llm logs` defaults to `command llm logs list`.
- `command llm templates` defaults to `command llm templates list`.
- `command llm models` defaults to `command llm models list`.
etc.

For the sake of this document, we can refer each of these as a "path".

**Declare option arrays for every *path* we touch**, then derive wrapper arrays from those.

### Mapping (Who Invokes What)

Note: true as of July 2025. This may have changed by the time you read this.

**Wrappers of third-party `command llm` (primary wrappers):**

* `command llm` ← `function llm`
* `command llm logs list` ← `llm-logs`, `llm-response`, `llm-cids`, `llm-code-block`
* `command llm templates list` ← `llm-templates-path`
* `command llm templates path` ← `llm-templates-path`
* `command llm logs path` ← `llm-search`

Note: Surely this list is very partial — there are others that aren't documented here.

**Wrappers of our internal `function llm` (secondary wrappers):**

* `function llm` ← `simplify`, `compress`, `merge`, `agent`, `zshai`, `zshcmd`, `pyai`, `pycmd`, `llm-commit-msg`, `llm-what-changed`
Note: Surely this list is very partial — there are others that aren't documented here.

## 2. Option Allowance Inference Rules


| Case                         | Pattern in Wrapper | Override?                    | Completion Should Offer?                                         |
| ---------------------------- | ------------------ | ---------------------------- | ---------------------------------------------------------------- |
| Hardcoded **before** `"$@"`  | `llm --foo X "$@"` | Yes (user later can replace) | Yes (unless docstring forbids)                                   |
| Hardcoded **after** `"$@"`   | `llm "$@" --foo X` | No (wrapper’s value wins)    | No (exposing is misleading, unless intentionally shown as fixed) |
| Docstring says “unsupported” | *(any position)*   | Irrelevant                   | No                                                               |

**Precedence:** *Docstring prohibition > positional inference > inherited availability.*


---

## 2. Design Principles

1. **Inheritance via Declarative Arrays**  // Again, true as of July 2025. May have been expanded by the time you read this.
   The completion layer reuses a canonical option set for each *real* third-party `llm` subcommand. We define:

   * `LLM_COMMON_OPTIONS` for `llm` / `llm prompt` (default).
   * `LLM_LOGS_OPTIONS` for `llm logs` / `llm logs list`.
   * `LLM_TEMPLATES_OPTIONS` for `llm templates` / `llm templates list`.
   * `LLM_MODELS_OPTIONS` for `llm models` / `llm models list`.

   Wrapper-specific arrays (`{WRAPPER}_OPTIONS`) derive from these base arrays by *purely declarative* filtering / augmentation (pattern deletions, additions).

2. **Central Logic, Minimal Overrides**
   `_llm` may contain “heavier” logic; other completion functions should:

   * Simply select the predeclared array (inherit).
   * Avoid reimplementing filtering logic inline.
   * Use syntactic pattern removals (e.g. `${(M)LLM_COMMON_OPTIONS:#^(*--template*)}`) to subtract disallowed flags.

3. **Declarative Placement**

   * All option arrays live at **module scope near the top**.
   * Function‑local transformations are discouraged unless unavoidable.
   * Any per-wrapper decision should be visible by inspecting top-level arrays.

4. **Short vs Explicit Subcommand Equivalence**
   Because the third-party `command llm` supplies defaults:

   * `llm` ≡ `llm prompt`
   * `llm logs` ≡ `llm logs list`
   * `llm templates` ≡ `llm templates list`
   * `llm models` ≡ `llm models list`

   **Rule**: Short and explicit forms must present identical completion options.

5. **Consistent Registration**
   Every wrapper maps to the third-party subcommand it ultimately invokes. Completion definitions should mirror that mapping directly (no hidden bootstrap hacks if a declarative mapping suffices).

---

## 3. Pattern Snippets (Reference)

* **Remove options by name fragment:**

  ```zsh
  FILTERED=( ${(M)BASE_ARRAY:#^(*--system*)} )
  ```
* **Remove multiple:**

  ```zsh
  FILTERED=( ${(M)BASE_ARRAY:#^(*--(system|template|no-md|md)*)} )
  ```
* **Bulk exclusion via pattern list:**

  ```zsh
  pat="${(j:|:)blocked_opts}"
  RESULT=( ${RESULT:#*($~pat)*} )
  ```

* You are not limited to these patterns. You can use any pattern you want. These are just for convenience.
---

## 4. When Adding New Wrappers

1. Decide which third-party subcommand they relate to.
2. Start from corresponding `LLM_*_OPTIONS`.
3. Apply docstring / argument parsing rules to filter.
4. Add wrapper name to `compdef _llm …` (or a specialized dispatcher if necessary).
5. Add tests / audit script to ensure declared vs inferred sets match (optional automation).

---

## 5. Guiding Intent

* **Declarative first**: Option intent visible without executing code.
* **Predictable overrides**: Users can override defaults *only* where completions signal availability.
* **Docstring is contract**: Completions must never contradict docstring constraints.
* **Stable inheritance**: Base arrays change rarely; wrapper arrays encode deltas only.
