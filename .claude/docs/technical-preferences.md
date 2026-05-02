# Technical Preferences

<!-- Populated by /setup-engine. Updated as the user makes decisions throughout development. -->
<!-- All agents reference this file for project-specific standards and conventions. -->

## Engine & Language

- **Engine**: Godot 4.6
- **Language**: GDScript
- **Rendering**: Forward+ (default, best for PC desktop 3D)
- **Physics**: Jolt (Godot 4.6 default)

## Input & Platform

<!-- Written by /setup-engine. Read by /ux-design, /ux-review, /test-setup, /team-ui, and /dev-story -->
<!-- to scope interaction specs, test helpers, and implementation to the correct input methods. -->

- **Target Platforms**: PC (Steam, itch.io)
- **Input Methods**: Keyboard/Mouse (primary), Gamepad (stretch support)
- **Primary Input**: Keyboard/Mouse
- **Gamepad Support**: Partial (stretch goal — Tier 2+)
- **Touch Support**: None
- **Platform Notes**: Mouse look is critical for FPS feel. Input latency must stay under one frame (see Pillar 1 "FLOW AVANT TOUT" in game-concept.md). Target 60+ fps locked with vsync. Gamepad support is stretch; if prioritized, aim-assist will need to be evaluated to preserve skill ceiling.

## Naming Conventions

- **Classes**: PascalCase (e.g., `PlayerController`)
- **Variables**: snake_case (e.g., `move_speed`)
- **Signals/Events**: snake_case past tense (e.g., `health_changed`, `credit_collected`)
- **Files**: snake_case matching class (e.g., `player_controller.gd`)
- **Scenes/Prefabs**: PascalCase matching root node (e.g., `PlayerController.tscn`)
- **Constants**: UPPER_SNAKE_CASE (e.g., `MAX_HEALTH`, `DASH_DISTANCE`)

## Performance Budgets

<!-- Aligned with Pillar 1 "FLOW AVANT TOUT" — any regression here is a design violation, not just a perf issue. -->

- **Target Framerate**: 60 fps minimum (vsync locked), 120+ fps desirable on modern hardware
- **Frame Budget**: 16.6 ms (60 fps) — input-to-display latency under one frame
- **Draw Calls**: < 500 per frame (Chrome Zen minimalism: primitives + flat shaders keep this achievable)
- **Memory Ceiling**: 2 GB RAM, 1 GB VRAM (target: entry-level gaming laptop)

## Testing

- **Framework**: GUT (Godot Unit Testing) — standard GDScript testing framework
- **Minimum Coverage**: 80% on gameplay systems (movement, katana hitbox, shop economy); 0% on VFX/presentation (covered by playtest evidence)
- **Required Tests**: Balance formulas, gameplay systems (movement, katana hitbox detection, shop transactions, checkpoint/respawn logic)

## Forbidden Patterns

<!-- Add patterns that should never appear in this project's codebase -->
- [None configured yet — add as architectural decisions are made]

## Allowed Libraries / Addons

<!-- Add approved third-party dependencies here. Only add when actively integrating — never speculatively. -->
- [None configured yet — add as dependencies are approved]

## Architecture Decisions Log

<!-- Quick reference linking to full ADRs in docs/architecture/ -->
- [No ADRs yet — use /architecture-decision to create one]

## Engine Specialists

<!-- Written by /setup-engine when engine is configured. -->
<!-- Read by /code-review, /architecture-decision, /architecture-review, and team skills -->
<!-- to know which specialist to spawn for engine-specific validation. -->

- **Primary**: godot-specialist
- **Language/Code Specialist**: godot-gdscript-specialist (all .gd files)
- **Shader Specialist**: godot-shader-specialist (.gdshader files, VisualShader resources)
- **UI Specialist**: godot-specialist (no dedicated UI specialist — primary covers all UI)
- **Additional Specialists**: godot-gdextension-specialist (GDExtension / native C++ bindings only, if needed)
- **Routing Notes**: Invoke primary for architecture decisions, ADR validation, and cross-cutting code review. Invoke GDScript specialist for code quality, signal architecture, static typing enforcement, and GDScript idioms. Invoke shader specialist for Chrome Zen flat shaders and material design. Invoke GDExtension specialist only when native extensions are involved.

### File Extension Routing

<!-- Skills use this table to select the right specialist per file type. -->
<!-- If a row says [TO BE CONFIGURED], fall back to Primary for that file type. -->

| File Extension / Type | Specialist to Spawn |
|-----------------------|---------------------|
| Game code (.gd files) | godot-gdscript-specialist |
| Shader / material files (.gdshader, VisualShader) | godot-shader-specialist |
| UI / screen files (Control nodes, CanvasLayer) | godot-specialist |
| Scene / prefab / level files (.tscn, .tres) | godot-specialist |
| Native extension / plugin files (.gdextension, C++) | godot-gdextension-specialist |
| General architecture review | godot-specialist |
