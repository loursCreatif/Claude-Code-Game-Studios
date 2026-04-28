# Claude Code Game Studios -- Game Studio Agent Architecture

Indie game development managed through 48 coordinated Claude Code subagents.
Each agent owns a specific domain, enforcing separation of concerns and quality.

## Technology Stack

- **Engine**: Godot 4.6
- **Language**: GDScript
- **Version Control**: Git with trunk-based development
- **Build System**: SCons (engine), Godot Export Templates
- **Asset Pipeline**: Godot Import System + custom resource pipeline

> **Note**: Engine-specialist agents exist for Godot, Unity, and Unreal with
> dedicated sub-specialists. Use the set matching your engine.

## Project Structure

@.claude/docs/directory-structure.md

## Engine Version Reference

@docs/engine-reference/godot/VERSION.md

## Technical Preferences

@.claude/docs/technical-preferences.md

## Coordination Rules

@.claude/docs/coordination-rules.md

## Collaboration Protocol

**Auto-approve recommended proposals by default.** When an agent or skill presents
a recommended option (the one it considers best), proceed with that recommendation
without asking the user to confirm. Only pause for explicit user input when:

- The decision is irreversible or destructive (deletion, force-push, prod changes)
- Multiple options are genuinely equivalent with no clear recommendation
- The choice materially changes the product vision (pillar-level design decisions)
- Credentials, authentication, or external approvals are required

For routine work — writing design docs, editing code, updating configs, creating
stories, running reviews — execute the recommendation immediately and report the
outcome. The user will course-correct if needed.

Every task still follows: **Question -> Options -> Recommendation -> Execute -> Report**
(not "wait for approval between each step").

- Agents may Write/Edit files that fit the agreed task scope without asking
- Show the draft in the output when writing, so the user can review after the fact
- Multi-file changes: execute in one pass, summarise the full changeset at the end
- No commits without user instruction (commits remain explicit-approval only)

See `docs/COLLABORATIVE-DESIGN-PRINCIPLE.md` for full protocol and examples.

> **First session?** If the project has no engine configured and no game concept,
> run `/start` to begin the guided onboarding flow.

## Coding Standards

@.claude/docs/coding-standards.md

## Context Management

@.claude/docs/context-management.md

## Godot CLI Safety (multi-session environment)

**Critical context** : the user runs **multiple Claude Code sessions in parallel**
(typically 5–8). A misbehaving `godot` CLI invocation in one session pops native
macOS dialog alerts that interrupt every other session. **Never** invoke the
`godot` binary in a way that may produce a GUI alert.

### Mandatory rules

1. **Always pass `--headless` AND `--script <path.gd>`** when running Godot from
   the CLI. The script form bypasses scene resolution entirely — no risk of
   "no main scene" alerts.
   ```bash
   godot --headless --script tools/lint/run_level_lint.gd  # ✅ SAFE
   ```

2. **Never use `--main-scene` pointing to a stub or empty `.tscn`.** If a scene
   is incomplete, run via `--script` instead.
   ```bash
   godot --headless --main-scene tests/performance/foo.tscn  # ❌ FORBIDDEN if foo.tscn is a stub
   ```

3. **Never invoke `godot` without arguments** or with only `--path`. Both
   trigger `OS::alert()` ("Couldn't detect whether to run the editor…").

4. **Never wrap a `godot` invocation in `run_in_background: true` with
   self-killing loops** (`godot ... & sleep N; kill $!`). If the background
   process gets orphaned, it pops alerts on every subsequent shell that touches
   the project. If you genuinely need a long-running godot process, run it
   foreground with a hard timeout, or document it with an explicit cleanup
   step.

5. **`OS::alert()` fires on macOS even with `--headless`** (Godot bug). The
   only reliable mitigation is to ensure the godot invocation **cannot fail
   into the alert paths above**. Defensive arg construction > defensive
   exception handling.

### Authorized exception : GdUnit4 headless test runs

The following pattern is **validated safe** (zero GUI alert across parallel
sessions, run 2026-04-28) and may be used by Claude sessions to execute the
test suite :

```bash
godot --headless --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --add tests/<path> [--add tests/<other>] \
  --ignoreHeadlessMode
```

**Why safe** : `GdUnitCmdTool.gd` extends `SceneTree` (proper MainLoop), the
flag set respects rule #1 (`--headless --script`), and `--ignoreHeadlessMode`
bypasses GdUnit4's default display check.

**Hard prerequisite** : `.godot/global_script_class_cache.cfg` must exist on
disk. Without it the parser cannot resolve `class_name GdUnitTestCIRunner` and
fails (without GUI alert — fail-loud is acceptable). The cache is built only
by the Godot Editor on first project open. If absent : ask the user to open
the project once in Godot Editor, then retry.

**Reports** auto-emitted to `reports/report_N/` (gitignored).

### If alerts appear anyway

Run this immediately to clear orphaned processes — safe in any session:

```bash
pkill -9 -f "godot" && pkill -9 -f "level_ccd"
```

Then locate the offending invocation in the conversation that spawned it
(grep for `run_in_background.*godot` in recent agent output) and fix the
command before relaunching.

### Source

- Incident 2026-04-27 : story-014 background runner spawned `godot --headless
  --path . --main-scene tests/performance/level_ccd_sweep_runner.tscn` (stub
  `.tscn`), which popped alerts every ~90s across all parallel sessions.
- `tests/performance/level_ccd_sweep_runner.gd` is documented as STUB until
  Sprint 1 (see active.md tech debt #1) — must be invoked via `--script`,
  never via `--main-scene`.
