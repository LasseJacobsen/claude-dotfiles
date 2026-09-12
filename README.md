# claude-dotfiles

Reusable Claude Code configuration, hooks, skills, and commands — versioned as a git repo.

## Structure

```
claude-dotfiles/
├── CLAUDE.md                           # Non-obvious overrides (commit rules, naming)
├── settings.json                       # Claude Code settings (hooks, permissions, env)
├── settings.local.example.json         # Template for machine-specific overrides
├── install.sh                          # One-shot setup script
├── Makefile                            # make install / make test
├── hooks/
│   ├── block-destructive.sh            # PreToolUse: block rm -rf /, force-push, fork bombs, etc.
│   ├── block-git-main.sh               # PreToolUse: block direct commits/pushes to main/master/prod
│   ├── block-big-binaries.sh           # PreToolUse: block committing large or binary result files
│   ├── enforce-uv.sh                   # PreToolUse: redirect pip/poetry/conda → uv
│   ├── ruff-after-edit.sh              # PostToolUse: ruff lint+format on every .py edit
│   ├── nbstripout.sh                   # PostToolUse: strip notebook outputs on .ipynb edits
│   ├── check-claims.sh                 # Stop: block uncertain/speculative responses
│   ├── precompact-backup.sh            # PreCompact: back up transcript before context compaction
│   ├── session-start.sh                # SessionStart: inject branch/status/recent commits as context
│   └── notify.sh                       # Notification: cross-platform desktop notification bridge
├── skills/
│   ├── bro/
│   │   └── SKILL.md                    # Skill: restate last message in plain human language
│   ├── domain-modeling/                # Vendored: CONTEXT.md glossary + ADR discipline (see Grilling section)
│   │   ├── SKILL.md
│   │   └── references/                 #   CONTEXT-FORMAT.md, ADR-FORMAT.md
│   ├── git-pr-message/
│   │   └── SKILL.md                    # Skill: generate PR descriptions from git log
│   ├── grill-with-docs/
│   │   └── SKILL.md                    # Vendored: /grill-with-docs, grilling + domain-modeling (manual only)
│   ├── grilling/
│   │   └── SKILL.md                    # Vendored: round-based interview until shared understanding
│   ├── iso-24495-*/                    # Six plain-language skills (see Plain language section)
│   │   └── SKILL.md
│   ├── iso-24495-4/                    # Vendored: 4 gap-analysis CLIs + rule engine,
│   │                                   #   plus references/ and assets/
│   ├── iso-24495-text-audit/scripts/   # Vendored: text-audit CLI (uses the engine above)
│   ├── pyspark-style/
│   │   └── SKILL.md                    # Skill: PySpark style rules (Palantir guide), applied at write time
│   ├── pyspark-audit/
│   │   └── SKILL.md                    # Skill: audit .py files against pyspark-style (manual only)
│   ├── writing-for-agents/             # Vendored: how to write SKILL.md / CLAUDE.md files
│   │   ├── SKILL.md
│   │   └── references/                 #   SKILL-MECHANICS.md
│   └── book-to-skill/                  # Vendored: document → skill converter (SKILL.md + Python extractor)
├── output-styles/
│   └── iso-24495.md                    # Output style: plain-language rules on every response
├── commands/
│   ├── commit.md                       # /user:commit — guided commit helper
│   └── pr.md                           # /user:pr — generate and open a pull request
└── tests/
    ├── test_hooks.sh                   # Unit tests for all hooks
    ├── test_audit.sh                   # Vendored CLI contracts + SKILL.md file references
    └── test_install.sh                 # install.sh prune, idempotence, backup
```

## Setup (new machine)

```bash
git clone <this-repo>
cd <repo-dir>
bash install.sh
```

The clone location doesn't matter — `install.sh` resolves paths relative to its own location.

`install.sh` does the following:
1. Auto-installs `jq` if missing (winget / brew / apt / yum)
2. Symlinks (or copies) `settings.json` and `CLAUDE.md` into `~/.claude/`
3. Copies hooks into `~/.claude/hooks/`
4. Copies commands into `~/.claude/commands/`
5. Copies skills into `~/.claude/skills/`
6. Copies output styles into `~/.claude/output-styles/`
7. **Prunes** anything in `~/.claude/{hooks,commands,skills,output-styles}` that this repo does not ship, one log line per removal. Those four directories mirror the repo exactly after every run, so a hook or skill you place there by hand will be removed; keep such things in this repo instead. Everything else under `~/.claude` (`projects/`, `plans/`, `backups/`, `plugins/`, `settings.local.json`, credentials, history) is Claude Code's own state and is never touched.
8. Seeds `~/.claude/settings.local.json` from `settings.local.example.json` on first run
9. Installs `nbstripout` and registers it as a global git filter (strips notebook outputs on every `git add`, regardless of who staged the file)

Then **start a new Claude Code session** — hooks are loaded at startup.

### Windows notes

- Symlinks for files require [Developer Mode](https://learn.microsoft.com/en-us/windows/apps/get-started/enable-your-device-for-development) or admin. Without it, `install.sh` falls back to copying — re-run after changes.
- `uv` installs to `~/.local/bin` — make sure it's on your PATH before starting Claude Code.
- Run `install.sh` in Git Bash (not PowerShell/cmd).
- Corporate security tools (EDR/AppLocker) sometimes block ordinary binaries on locked-down machines (`/usr/bin/find: Permission denied`). We have seen `find`, `sort`, `curl`, and `uv` blocked this way, so `install.sh` and the test suites avoid `find` and `sort`. If a *different* command fails the same way, it's the same class of issue — report it. The most common one is `uv` itself; see [When `uv` is blocked](#when-uv-is-blocked-corporate-edr-or-application-control).
  - **A blocked binary inside a pipeline is worse than a visible error.** The pipeline yields nothing, so a test can pass while proving nothing. `tests/test_audit.sh` therefore counts what it extracted and fails when it finds none.
- Several hooks require `jq`. Claude Code ships jq in its bundled environment so hooks always work in sessions. `install.sh` installs jq automatically via `winget`; if that fails, install it manually before running `make test`:
  ```
  winget install jqlang.jq
  ```

### Updating after changes

```bash
bash install.sh   # or: make install
```

If settings.json was symlinked, changes take effect immediately. If it was copied, re-run.

### Machine-specific overrides

Copy the example template after install and fill in machine-specific values:

```bash
cp settings.local.example.json ~/.claude/settings.local.json
# Edit ~/.claude/settings.local.json — add additionalDirectories, per-machine allow rules, etc.
```

`settings.local.json` is gitignored in all projects; it never gets committed.

---

## Testing hooks

Run the test suite from the dotfiles root:

```bash
bash tests/test_hooks.sh    # hooks
bash tests/test_audit.sh    # text-audit CLI
bash tests/test_install.sh  # install.sh prune + backup
make test                   # all three
```

`test_hooks.sh` pipes crafted JSON payloads into each hook and asserts exit codes and JSON output. Hooks that rely on `jq` internally are skipped if jq isn't in PATH (all tests still pass — they're reported as SKIP). Install jq to unlock full coverage.

`test_install.sh` runs `install.sh` against a temp directory and asserts that stale entries in the four managed dirs are pruned, every repo entry lands, unmanaged state survives, a re-run prunes nothing, and an unmanaged target is backed up first. It uses two env overrides on `install.sh`: `CLAUDE_DOTFILES_TARGET` (install somewhere other than `~/.claude`) and `CLAUDE_DOTFILES_SKIP_TOOLS=1` (skip the jq/uv/nbstripout install and the global git config edits). The symlink-safety case is skipped where symlinks are unavailable.

`test_audit.sh` covers the five vendored CLIs: the `iso-24495-text-audit` one and the four `iso-24495-4` gap-analysis ones. It asserts which rule each fixture trips, every argument-error exit code, and that the full four-step gap-analysis chain produces a report. It also checks that **every file a `SKILL.md` names actually exists** — the bug that made the suite necessary. It skips entirely if Node is missing or too old to strip types, so `make test` stays green without it.

---

## uv

[`uv`](https://github.com/astral-sh/uv) powers the global `nbstripout` git filter (strips notebook outputs on every `git add`). It's optional — everything else installs and runs without it.

**Install uv:**

```powershell
# Windows
powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
```

`install.sh` installs `nbstripout` via uv and registers it as a global git filter. After installing uv, re-run `install.sh`.

#### When `uv` is blocked (corporate EDR or application control)

**Symptom:** `uv …: Permission denied`. `install.sh` prints a single "uv is installed but cannot be executed" warning and skips the nbstripout git filter.

**Why:** some managed/corporate machines run an EDR or application-control product that blocks specific executables by reputation — `uv.exe` is a common target (we've also seen `find.exe` and even `System32\whoami.exe` blocked on the same machine). This is **not** an NTFS-permission or PATH problem, so it can't be fixed by relocating or reinstalling uv.

**Confirm it (read-only, in PowerShell):**

```powershell
uv --version                                          # → "Permission denied" if blocked
(Get-Item (Get-Command uv).Source).GetAccessControl().Owner   # you usually still own the file — rules out an ACL issue
```

**Fix:** ask IT / security to **allowlist `uv.exe` and `uvx.exe`** in the EDR / application-control console. Give them the path printed by `command -v uv` (Git Bash) or `(Get-Command uv).Source` (PowerShell). There is no safe script-side workaround — bypassing the control (renaming/repacking the binary, disabling protection) is out of scope.

**Meanwhile:** the rest of the setup works without uv — hooks, permissions, env, commands, and skills all install and run. You only lose notebook output stripping.

---

## Hooks

Hooks live in `~/.claude/hooks/` and run deterministically on every matching tool call — no Claude judgement involved. PreToolUse hooks output a structured JSON deny decision and exit 0; blocking PostToolUse/Stop hooks exit 2 to feed errors back to Claude.

### PreToolUse

| Hook | Trigger | What it blocks |
|------|---------|----------------|
| `block-destructive.sh` | Any `Bash` | `rm -rf /`, `rm -rf ~`, `git push --force`, `chmod -R 777`, pipe-to-shell, fork bomb, `DROP TABLE` (best-effort — see below) |
| `block-git-main.sh` | Any `Bash` | `git commit`/`push` while on `main`, `master`, `prod`, or `production` |
| `block-big-binaries.sh` | `git add` / `git commit -a` | Files >50 MB or with binary result extensions (`.h5`, `.vtk`, `.pkl`, `.npz`, etc.) |
| `enforce-uv.sh` | Any `Bash` | Denies `pip install`, `pip uninstall`, `poetry add`, `poetry install`, `conda install`, `python -m pytest`, `python -m ruff`, and bare `pytest`. The deny reason includes the suggested uv replacement (e.g. `uv add`, `uv run pytest`). |
| `protect-secrets.sh` | Any `Bash` | Read-tools (`cat`/`less`/`head`/`tail`/`awk`/`sed`/`xxd`/`od`/`strings`/`nl`/`tac`/`dd`) and inline interpreters (`python -c`, `ruby -e`, etc.) when targeting `.env*`, `*.pem`, `*.key`, `credentials.json`, `.ssh/` paths. Bash bypass of `permissions.deny` (issue #6631). Best-effort tripwire — see posture note below. |

#### Posture, not protection

`block-destructive.sh` and `protect-secrets.sh` are **tripwires against accidental damage and routine disclosure, not security boundaries.** A motivated caller can bypass them with shell tricks the regexes don't model:

- `block-destructive.sh` doesn't catch `rm -rf "$HOME"`, `rm -rf ${HOME}`, `rm -rf /etc`, `dd if=/dev/zero of=/dev/sda`, `mkfs`, `> /dev/sda`, `find / -delete`, `shred`, `wipefs`, separated `-r -f` flags, etc.
- `protect-secrets.sh` doesn't catch process substitution (`<(cat .env)`), here-docs, base64-piped reads, or arbitrary script files that read secrets at runtime.

If you need a real security boundary, run Claude Code in a sandboxed environment (container, VM, or dedicated user) and rely on filesystem permissions instead of regex matching.

### PostToolUse

| Hook | Trigger | What it does |
|------|---------|--------------|
| `ruff-after-edit.sh` | `Write`/`Edit`/`MultiEdit` on `.py` | Runs `ruff check --fix` then `ruff format` in-place; always exits 0 |
| `nbstripout.sh` | `Write`/`NotebookEdit` on `*/notebooks/*.ipynb` | Strips cell outputs via `nbstripout`; always exits 0. Scoped to `notebooks/` so scratch notebooks keep their outputs for iterative work. The matcher excludes `Edit`/`MultiEdit` because those are line-based operations that don't make sense on a JSON notebook. |

### Stop

| Hook | What it does |
|------|--------------|
| `check-claims.sh` | Parses the transcript JSONL to extract the last assistant text block and checks it for uncertain/speculative phrases ("I can't access", "from memory", "if you could share/provide"). Blocks completion if found. Ignores tool results and file payloads that happen to contain those phrases. |

### PreCompact

| Hook | What it does |
|------|--------------|
| `precompact-backup.sh` | Copies the current transcript to `~/.claude/backups/compact-<timestamp>.jsonl` before Claude compacts the context window |

### SessionStart

| Hook | What it does |
|------|--------------|
| `session-start.sh` | On `startup`, `resume`, or `clear`: prints the current branch, working-tree status, and last 5 commits. Stdout from SessionStart hooks is injected into Claude's context, replacing "remember to check git status" prose rules. Exits silently outside a git repo. |

### Notification

| Hook | What it does |
|------|--------------|
| `notify.sh` | Surfaces "Claude needs input" events as a desktop notification: BurntToast on Windows, `osascript` on macOS, `notify-send` on Linux. Always exits 0; missing notifier is silent. |

#### Enabling Windows toast notifications

`notify.sh` uses [BurntToast](https://github.com/Windos/BurntToast) on Windows. Install it once per user:

```powershell
Install-Module -Name BurntToast -Scope CurrentUser
```

If BurntToast is not installed, `notify.sh` silently falls through — no error. macOS and Linux work out of the box (no install).

---

## Skills

| Skill | Trigger |
|-------|---------|
| `git-pr-message` | "generate a PR description", "write the PR body" |
| `bro` | "/bro" — restate the last message in plain human language |
| `grilling` | Automatic on "grill me", "stress-test this plan", or "/grilling" — round-based interview until shared understanding |
| `grill-with-docs` | Manual only — "/grill-with-docs", the same interview plus `CONTEXT.md` and ADRs written as terms and decisions settle |
| `domain-modeling` | Automatic when editing `CONTEXT.md`, recording an ADR, or settling codebase terminology |
| `writing-for-agents` | Automatic when creating or editing a `SKILL.md`, `CLAUDE.md`, or `AGENTS.md` |
| `iso-24495-1` | Automatic on user-facing prose — core plain-language rules |
| `iso-24495-2` | Automatic on legal/compliance text |
| `iso-24495-3` | Automatic on technical/science writing and docs |
| `iso-24495-4` | Automatic on org-level plain-language work (gap analysis, policy). Its four CLIs need Node 22.18+ |
| `iso-24495-code` | Automatic on code readability (naming, structure) |
| `iso-24495-text-audit` | Manual only — "audit this file/directory for plain language". Needs Node 22.18+ |
| `pyspark-style` | Automatic on writing/restructuring PySpark code — column refs, joins, windows, chaining |
| `pyspark-audit` | Manual only — "/pyspark-audit <file-or-dir>", checks existing files against `pyspark-style` |
| `book-to-skill` | "/book-to-skill <path> [slug]" or "turn this book into a skill" — converts a document into a study/reference skill. Needs Python 3.9+ (see Book to skill section) |

## Plain language (ISO 24495)

The `iso-24495-*` skills and the `output-styles/iso-24495.md` output style are vendored from [GaZmagik/iso-24495](https://github.com/GaZmagik/iso-24495) (MIT). They apply plain-language rules from the ISO 24495 standard series: lead with the outcome, no preamble filler, sentences under 30 words, active voice, one term per concept.

The two pieces work at different levels:

- **The output style** governs every response. `settings.json` sets it as the default (`"outputStyle": "ISO 24495"`); switch per session with `/output-style`, or back to normal with `/output-style default`.
- **The skills** add domain depth (legal, technical, document design) and activate when the task matches. `iso-24495-text-audit` never auto-activates — invoke it to audit existing files.

### What is vendored

The `SKILL.md` files, `output-styles/iso-24495.md`, and every script the two runnable skills need:

```
skills/iso-24495-text-audit/scripts/  audit-text-cli.ts, audit-text.ts
skills/iso-24495-4/scripts/           audit-corpus{,-cli}.ts, audit-evidence{,-cli}.ts,
                                      generate-report{,-cli}.ts, score-maturity{,-cli}.ts,
                                      lib/{parse,lexicon,types}.ts
skills/iso-24495-4/references/        evidence-map.md, interview-guide.md, maturity-model.md
skills/iso-24495-4/assets/            gap-report-template.md
```

`audit-text.ts` is a thin wrapper; its rule engine lives in the `iso-24495-4` scripts, so both directories are needed and must stay siblings under `skills/`.

**These run on Node, not Bun.** Upstream targets Bun, but every file uses erasable TypeScript syntax and imports only `node:fs` and `node:path`. Node strips the types and runs them unbuilt — no build step, no `node_modules`, no new runtime. Node 22.18 or newer is required, because type stripping is unflagged from that version.

Eleven lines differ from upstream, every one of them reading `node` where upstream reads `bun`:

| File | Lines | What changed |
|------|-------|--------------|
| `iso-24495-text-audit/SKILL.md` | 2 | step 6: its prose and its command |
| `iso-24495-4/SKILL.md` | 4 | the four workflow commands |
| `audit-text.ts`, `audit-corpus.ts`, `audit-evidence.ts`, `generate-report.ts`, `score-maturity.ts` | 5 | one usage string each |

Two more lines are deleted rather than changed: the `iso-24495-5` bullet in `iso-24495-1/SKILL.md` (Domain Extension Triggers) and the matching bullet in `output-styles/iso-24495.md`. Every other vendored file is byte-identical to upstream 0.6.2. To check, diff this tree against a fresh clone: every differing line should contain `bun` or `node`, or be one of those two deleted bullets.

**`iso-24495-5` (document design) is not vendored.** Upstream's `SKILL.md` tells the agent to read `assets/adr-template.md`, `assets/runbook-template.md` and `assets/design-doc-template.md` before writing those document types, and upstream ships none of the three. The skill therefore fails on exactly the documents it exists for. ADRs are covered by `domain-modeling` instead (see the Grilling section).

Still left out: upstream's Codex CLI config (`agents/openai.yaml`) and its `bun:test` suites. `tests/test_audit.sh` covers the CLI contracts instead.

To update: re-copy the `SKILL.md` files (skipping `iso-24495-5`), `output-styles/iso-24495.md`, and the directories above, then re-apply the eleven `bun` → `node` changes, re-delete the two `iso-24495-5` bullets, and run `bash tests/test_audit.sh`. That suite fails if a `SKILL.md` names a file the copy missed, which is the bug that made this section necessary.

## PySpark style (Palantir guide)

The `pyspark-style` and `pyspark-audit` skills adapt the rules of the
[Palantir PySpark style guide](https://github.com/palantir/pyspark-style-guide)
(MIT, Copyright (c) 2020 Palantir Technologies, Inc.). The prose is rewritten for skill use;
the recommendations are theirs.

The two skills mirror the ISO pair:

- **`pyspark-style`** activates whenever Claude writes or restructures PySpark code and governs
  column references, schema contracts, joins, window frames, and chaining. Formatting stays with
  the `ruff-after-edit` hook.
- **`pyspark-audit`** never auto-activates. Invoke it with a file or directory to get findings
  (file, line, rule, snippet, effect) against the `pyspark-style` rules. Unlike
  `iso-24495-text-audit` it ships no script — the checks are judgement calls (chain length,
  schema contracts), so the model performs them by reading the code.

## Grilling (mattpocock/skills)

Four skills are vendored from [mattpocock/skills](https://github.com/mattpocock/skills) 1.2.3
(MIT, Copyright (c) 2026 Matt Pocock). They cover alignment before work starts; the rest of that
repo (specs, tickets, implement, wayfinder, triage, code review, merge conflicts) is left out
because plan mode, the issue tracker and the built-in `/code-review` already cover it.

| Skill | Invocation | What it does |
|-------|-----------|--------------|
| `grilling` | Automatic on "grill" phrases, or `/grilling` | The interview primitive. Maps the subject as a **design tree**, asks the whole **frontier** (every question whose prerequisites are settled) in one **round** as numbered ❓ questions each with a ➡️ recommended answer, then waits. Facts it looks up itself; decisions it puts to you. It stops when the frontier is empty and asks you to confirm the understanding is shared before acting. |
| `grill-with-docs` | Manual only, `/grill-with-docs` | The same interview, pointed at a repo. Calls `grilling` and `domain-modeling`. |
| `domain-modeling` | Automatic on `CONTEXT.md`, ADR, or terminology work | Writes each resolved term to a `CONTEXT.md` glossary the moment it settles (root, or per-context via `CONTEXT-MAP.md`), and offers an ADR under `docs/adr/NNNN-slug.md` only when a decision is hard to reverse, surprising without context, and a real trade-off. Formats live in its `references/`. |
| `writing-for-agents` | Automatic when editing a `SKILL.md`, `CLAUDE.md`, or `AGENTS.md` | Reference for writing documents an agent consumes: context pointers, progressive disclosure, completion criteria, leading words, pruning. `references/SKILL-MECHANICS.md` covers frontmatter and model- vs user-invocation. |

Prefer one question at a time? Upstream's supported opt-out is a line in your global `CLAUDE.md`:

```
When grilling, ask one question at a time.
```

### What is vendored

The seven prose files: `grilling/SKILL.md`, `grill-with-docs/SKILL.md`, `domain-modeling/SKILL.md`
with `CONTEXT-FORMAT.md` and `ADR-FORMAT.md`, and `writing-for-agents/SKILL.md` with
`SKILL-MECHANICS.md`. Differences from upstream:

- Each `SKILL.md` gains a `metadata` block naming the source, version and licence.
- Upstream keeps sibling files beside `SKILL.md`; here they live in `references/`, and the links
  in `SKILL.md` are rewritten to `references/<file>`. That is the path shape
  `tests/test_audit.sh` checks, so a missing reference file fails the suite.
- `grill-with-docs/SKILL.md` gains one sentence: "Before the first round, state which of the
  two skills loaded." Upstream's docs report that the one-line router sometimes runs without
  loading its two dependencies (the tell is a question dump with no ➡️ recommendations) and that
  asking which skills loaded is the recovery. Saying it up front makes the failure visible.
- `grill-me` is not vendored. Its whole body is "call `grilling`", and `/grilling` is already a
  slash command in Claude Code.
- Upstream's `agents/openai.yaml` (Codex metadata) is left out, as with the ISO skills.

To update: re-copy the seven files from
`skills/productivity/{grilling,writing-for-agents}` and `skills/engineering/{grill-with-docs,domain-modeling}`,
move the sibling files into `references/` and re-apply the path rewrites, re-add the metadata
blocks and the one `grill-with-docs` sentence, then run `bash tests/test_audit.sh`.

## Book to skill (virgiliojr94/book-to-skill)

The `book-to-skill` skill is vendored from [virgiliojr94/book-to-skill](https://github.com/virgiliojr94/book-to-skill)
(MIT, Copyright (c) 2025 virgiliojr94) at commit `01f8a742ae` (2026-09-12; version 1.4.0 plus
later fixes on `master`). It converts a document — PDF, EPUB, DOCX, HTML, Markdown, text, RTF,
or MOBI/AZW via Calibre — into a skill under `~/.claude/skills/<slug>/`: a small `SKILL.md`
holding the book's frameworks and a chapter index, plus on-demand `chapters/*.md`,
`glossary.md`, `patterns.md`, and `cheatsheet.md`.

Invoke it with `/book-to-skill <file|dir|glob>... [slug]`. It asks two questions (content type,
depth), extracts text with a deterministic Python script, then writes the skill files. Generated
skills are synthesized summaries; keep skills of copyrighted books private.

### What is vendored

Upstream is 2.6 MB, mostly docs, images, tests, and CI. The skill itself is 21 files (~195 KB),
each one something `SKILL.md` needs at run time:

```
skills/book-to-skill/SKILL.md                       the generator spec (Steps 0–10)
skills/book-to-skill/LICENSE.md                     upstream MIT licence
skills/book-to-skill/scripts/extract.py             entry shim; adds the skill dir to sys.path
skills/book-to-skill/book_to_skill/                 extractor package: cli, config, dependencies,
                                                    sanitize, utils, parsers/{pdf,epub,docx,html,rtf,calibre,text}
skills/book-to-skill/tools/scan_generated_skill.py  Step 9.5 prompt-injection scan of the output
```

Left out: `docs/`, `tests/`, `evals/`, `.github/`, the README translations, and
`tools/{validate_skill,discovery_tax}.py` plus `tools/evals/`, which `SKILL.md` never calls.

**Python only; no packages required.** The extractor is stdlib for every format. PDFs use
`pdftotext` when it is on PATH (Git for Windows ships it), else `pypdf` or `pdfminer.six` if
installed; EPUB, DOCX, HTML, and RTF each have a stdlib fallback. Optional packages raise
fidelity: `pypdf`, `ebooklib` + `beautifulsoup4`, `python-docx`, `striprtf`. Install them into
the interpreter that runs the extractor (for example `uv pip install --python "$(command -v python)" pypdf`).
`docling` (technical PDFs: tables, code, formulas) pulls in a large ML stack; install it only on
purpose. MOBI/AZW need Calibre's `ebook-convert`; there is no fallback. To see what is available:

```bash
python skills/book-to-skill/scripts/extract.py --check
```

Seven lines differ from upstream:

| File | Lines | What changed |
|------|-------|--------------|
| `SKILL.md` frontmatter | 4 | added `metadata:` (source, licence, pinned commit), matching `pyspark-style` |
| `SKILL.md` Step 5 | 3 | generated skills default to `~/.claude/skills` instead of `~/.agents/skills` plus a symlink, which needs Developer Mode on Windows; the offer to migrate an existing real directory is dropped |

The other 20 files are byte-identical to upstream at that commit. `tests/test_audit.sh` checks
that `SKILL.md` names only files that exist and that the extractor and scanner run.

To update: re-copy the files above at the new commit, re-apply the seven lines, and run `make test`.

## Commands

| Command | Description |
|---------|-------------|
| `/user:commit` | Stage and commit with a well-formed message, no AI footers |
| `/user:pr` | Generate a PR title/body from git log and open the PR with `gh` |
