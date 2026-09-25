# claude-dotfiles

Reusable Claude Code configuration, hooks, and skills — versioned as a git repo.

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
│   └── notify.sh                       # Notification: cross-platform desktop notification bridge
├── skills/
│   ├── domain-modeling/                # Vendored: CONTEXT.md glossary + ADR discipline (see Grilling section)
│   │   ├── SKILL.md
│   │   └── references/                 #   CONTEXT-FORMAT.md, ADR-FORMAT.md
│   ├── grill-with-docs/
│   │   └── SKILL.md                    # Vendored: /grill-with-docs, anthropic-skills:grilling + domain-modeling
│   ├── iso-24495-code/
│   │   └── SKILL.md                    # Vendored: plain-language rules for code (see Plain language section)
│   ├── pyspark-style/
│   │   └── SKILL.md                    # Skill: PySpark style rules (Palantir guide), applied at write time
│   ├── pyspark-audit/
│   │   └── SKILL.md                    # Skill: audit .py files against pyspark-style (manual only)
│   └── book-to-skill/                  # Vendored: document → skill converter (SKILL.md + Python extractor)
├── .claude/skills/
│   └── writing-for-agents/             # Vendored, project-only: how to write SKILL.md / CLAUDE.md files
│       ├── SKILL.md
│       └── references/                 #   SKILL-MECHANICS.md
└── tests/
    ├── test_hooks.sh                   # Unit tests for all hooks
    ├── test_skills.sh                  # SKILL.md file references, invocation flags, book-to-skill extractor
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
4. Copies skills into `~/.claude/skills/`
5. **Prunes** anything in `~/.claude/{hooks,skills}` that this repo does not ship, one log line per removal. Those two directories mirror the repo exactly after every run, so a hook or skill you place there by hand will be removed; keep such things in this repo instead. Everything else under `~/.claude` (`projects/`, `plans/`, `backups/`, `plugins/`, `settings.local.json`, credentials, history) is Claude Code's own state and is never touched.
   The repo no longer ships commands or output styles; `~/.claude/{commands,output-styles}` are still pruned so older installs clean up, and removed once empty.
6. Seeds `~/.claude/settings.local.json` from `settings.local.example.json` on first run
7. Installs `nbstripout` and registers it as a global git filter (strips notebook outputs on every `git add`, regardless of who staged the file)

Then **start a new Claude Code session** — hooks are loaded at startup.

### Windows notes

- Symlinks for files require [Developer Mode](https://learn.microsoft.com/en-us/windows/apps/get-started/enable-your-device-for-development) or admin. Without it, `install.sh` falls back to copying — re-run after changes.
- `uv` installs to `~/.local/bin` — make sure it's on your PATH before starting Claude Code.
- Run `install.sh` in Git Bash (not PowerShell/cmd).
- Corporate security tools (EDR/AppLocker) sometimes block ordinary binaries on locked-down machines (`/usr/bin/find: Permission denied`). We have seen `find`, `sort`, `curl`, and `uv` blocked this way, so `install.sh` and the test suites avoid `find` and `sort`. If a *different* command fails the same way, it's the same class of issue — report it. The most common one is `uv` itself; see [When `uv` is blocked](#when-uv-is-blocked-corporate-edr-or-application-control).
  - **A blocked binary inside a pipeline is worse than a visible error.** The pipeline yields nothing, so a test can pass while proving nothing. `tests/test_skills.sh` therefore counts what it extracted and fails when it finds none.
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
bash tests/test_skills.sh   # skill file references + book-to-skill extractor
bash tests/test_install.sh  # install.sh prune + backup
make test                   # all three
```

`test_hooks.sh` pipes crafted JSON payloads into each hook and asserts exit codes and JSON output. Hooks that rely on `jq` internally are skipped if jq isn't in PATH (all tests still pass — they're reported as SKIP). Install jq to unlock full coverage.

`test_install.sh` runs `install.sh` against a temp directory and asserts that stale entries in the managed dirs are pruned, every repo entry lands, unmanaged state survives, a re-run prunes nothing, and an unmanaged target is backed up first. It uses two env overrides on `install.sh`: `CLAUDE_DOTFILES_TARGET` (install somewhere other than `~/.claude`) and `CLAUDE_DOTFILES_SKIP_TOOLS=1` (skip the jq/uv/nbstripout install and the global git config edits). The symlink-safety case is skipped where symlinks are unavailable.

`test_skills.sh` checks that **every file a `SKILL.md` names actually exists** (vendored skills have shipped pointing at files the copy never brought over), that `book-to-skill` stays invoke-only and `grill-with-docs` names skills that resolve, and that the `book-to-skill` extractor and scanner run. The extractor part skips without Python 3.9+.

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

**Meanwhile:** the rest of the setup works without uv — hooks, permissions, env, and skills all install and run. You only lose notebook output stripping.

---

## Hooks

Hooks live in `~/.claude/hooks/` and run deterministically on every matching tool call — no Claude judgement involved. PreToolUse hooks output a structured JSON deny decision and exit 0.

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

`grilling` and `bro` are not vendored: the built-in `anthropic-skills:grilling` and `anthropic-skills:bro` cover them.

| Skill | Trigger |
|-------|---------|
| `grill-with-docs` | Manual only — "/grill-with-docs", the same interview plus `CONTEXT.md` and ADRs written as terms and decisions settle |
| `domain-modeling` | Automatic when editing `CONTEXT.md`, recording an ADR, or settling codebase terminology |
| `writing-for-agents` | Project-only (this repo's `.claude/skills/`): automatic when creating or editing a `SKILL.md`, `CLAUDE.md`, or `AGENTS.md` here |
| `iso-24495-code` | Automatic on code readability (naming, structure) |
| `pyspark-style` | Automatic on writing/restructuring PySpark code — column refs, joins, windows, chaining |
| `pyspark-audit` | Manual only — "/pyspark-audit <file-or-dir>", checks existing files against `pyspark-style` |
| `book-to-skill` | Manual only — "/book-to-skill <path> [slug]" — converts a document into a study/reference skill. Needs Python 3.9+ (see Book to skill section) |

## Plain language (ISO 24495)

`iso-24495-code` is vendored from [GaZmagik/iso-24495](https://github.com/GaZmagik/iso-24495) (MIT) 0.6.2 and is byte-identical to upstream. It applies the ISO 24495-1 plain-language principles to the parts of code a person reads: the order units appear in, names, comments, and error messages.

The rest of that repo (the output style, `iso-24495-1` to `-4`, and the text audit) was dropped. Current models already write plainly, and the output style plus the skills it loaded added several thousand tokens of rules to most sessions.

To update: re-copy `skills/iso-24495-code/SKILL.md` from upstream.

## PySpark style (Palantir guide)

The `pyspark-style` and `pyspark-audit` skills adapt the rules of the
[Palantir PySpark style guide](https://github.com/palantir/pyspark-style-guide)
(MIT, Copyright (c) 2020 Palantir Technologies, Inc.). The prose is rewritten for skill use;
the recommendations are theirs.

The two skills split writing from reviewing:

- **`pyspark-style`** activates whenever Claude writes or restructures PySpark code and governs
  column references, schema contracts, joins, window frames, and chaining. Formatting stays with
  the `ruff-after-edit` hook.
- **`pyspark-audit`** never auto-activates. Invoke it with a file or directory to get findings
  (file, line, rule, snippet, effect) against the `pyspark-style` rules. It ships no script —
  the checks are judgement calls (chain length, schema contracts), so the model performs them
  by reading the code.

## Grilling (mattpocock/skills)

Three skills are vendored from [mattpocock/skills](https://github.com/mattpocock/skills) 1.2.3
(MIT, Copyright (c) 2026 Matt Pocock). They cover alignment before work starts; the rest of that
repo (specs, tickets, implement, wayfinder, triage, code review, merge conflicts) is left out
because plan mode, the issue tracker and the built-in `/code-review` already cover it.

| Skill | Invocation | What it does |
|-------|-----------|--------------|
| `anthropic-skills:grilling` | Built in, not vendored. Automatic on "grill" phrases | The interview primitive. Maps the subject as a **design tree**, asks the whole **frontier** (every question whose prerequisites are settled) in one **round** as numbered ❓ questions each with a ➡️ recommended answer, then waits. Facts it looks up itself; decisions it puts to you. It stops when the frontier is empty and asks you to confirm the understanding is shared before acting. |
| `grill-with-docs` | Manual only, `/grill-with-docs` | The same interview, pointed at a repo. Calls `anthropic-skills:grilling` and `domain-modeling`. |
| `domain-modeling` | Automatic on `CONTEXT.md`, ADR, or terminology work | Writes each resolved term to a `CONTEXT.md` glossary the moment it settles (root, or per-context via `CONTEXT-MAP.md`), and offers an ADR under `docs/adr/NNNN-slug.md` only when a decision is hard to reverse, surprising without context, and a real trade-off. Formats live in its `references/`. |
| `writing-for-agents` | Project-only; automatic when editing a `SKILL.md`, `CLAUDE.md`, or `AGENTS.md` in this repo | Reference for writing documents an agent consumes: context pointers, progressive disclosure, completion criteria, leading words, pruning. `references/SKILL-MECHANICS.md` covers frontmatter and model- vs user-invocation. |

Prefer one question at a time? Upstream's supported opt-out is a line in your global `CLAUDE.md`:

```
When grilling, ask one question at a time.
```

### What is vendored

Six prose files: `grill-with-docs/SKILL.md`, `domain-modeling/SKILL.md` with
`CONTEXT-FORMAT.md` and `ADR-FORMAT.md`, and `.claude/skills/writing-for-agents/SKILL.md` with
`SKILL-MECHANICS.md`. Differences from upstream:

- Each `SKILL.md` gains a `metadata` block naming the source, version and licence.
- Upstream keeps sibling files beside `SKILL.md`; here they live in `references/`, and the links
  in `SKILL.md` are rewritten to `references/<file>`. That is the path shape
  `tests/test_skills.sh` checks, so a missing reference file fails the suite.
- `grill-with-docs/SKILL.md` gains one sentence: "Before the first round, state which of the
  two skills loaded." Upstream's docs report that the one-line router sometimes runs without
  loading its two dependencies (the tell is a question dump with no ➡️ recommendations) and that
  asking which skills loaded is the recovery. Saying it up front makes the failure visible.
- `grill-with-docs` calls the built-in `anthropic-skills:grilling` instead of a vendored `grilling`.
- `writing-for-agents` lives in this repo's `.claude/skills/`, so it loads only when working on
  these dotfiles rather than in every project.
- `grilling` and `grill-me` are not vendored; the built-in `anthropic-skills:grilling` covers both.
- Upstream's `agents/openai.yaml` (Codex metadata) is left out.

To update: re-copy the six files from `skills/productivity/writing-for-agents` (into
`.claude/skills/`) and `skills/engineering/{grill-with-docs,domain-modeling}`, move the sibling
files into `references/` and re-apply the path rewrites, re-add the metadata blocks, the one
`grill-with-docs` sentence and the `anthropic-skills:grilling` name, then run `make test`.

## Book to skill (virgiliojr94/book-to-skill)

The `book-to-skill` skill is vendored from [virgiliojr94/book-to-skill](https://github.com/virgiliojr94/book-to-skill)
(MIT, Copyright (c) 2025 virgiliojr94) at commit `01f8a742ae` (2026-09-12; version 1.4.0 plus
later fixes on `master`). It converts a document — PDF, EPUB, DOCX, HTML, Markdown, text, RTF,
or MOBI/AZW via Calibre — into a skill under `~/.claude/skills/<slug>/`: a small `SKILL.md`
holding the book's frameworks and a chapter index, plus on-demand `chapters/*.md`,
`glossary.md`, `patterns.md`, and `cheatsheet.md`.

Invoke it with `/book-to-skill <file|dir|glob>... [slug]`. It never loads on its own
(`disable-model-invocation: true`), so its long description stays out of every other session. It asks two questions (content type,
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

Eight lines differ from upstream:

| File | Lines | What changed |
|------|-------|--------------|
| `SKILL.md` frontmatter | 4 | added `metadata:` (source, licence, pinned commit), matching `pyspark-style` |
| `SKILL.md` frontmatter | 1 | added `disable-model-invocation: true`: runs only on `/book-to-skill` |
| `SKILL.md` Step 5 | 3 | generated skills default to `~/.claude/skills` instead of `~/.agents/skills` plus a symlink, which needs Developer Mode on Windows; the offer to migrate an existing real directory is dropped |

The other 20 files are byte-identical to upstream at that commit. `tests/test_skills.sh` checks
that `SKILL.md` names only files that exist and that the extractor and scanner run.

To update: re-copy the files above at the new commit, re-apply the eight lines, and run `make test`.
