# Story 009: Debug overlay F3 (latency, action, mouse mode)

> **Epic**: input-system
> **Status**: Complete
> **Layer**: Foundation
> **Type**: UI
> **Estimate**: S (2-3 h)
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/input-system.md`
**Requirement**: *(pas de TR dédié — c'est une aide debug. Consume TR-inp-007 via `get_latency_p99_ms()`)*

**ADR Governing Implementation**: ADR-0004 D-9 (fixtures debug-only via `OS.has_feature("debug")`)
**ADR Decision Summary**: En build debug, l'action `&"debug_toggle"` mappée à F3 bascule un overlay qui affiche en temps réel : latency p99 (via `get_latency_p99_ms()`), action courante pressée, mouse mode indicator. En release, l'action n'est pas enregistrée (story-001 AC-DBG-1) et l'overlay n'apparaît pas (AC-DBG-2).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `CanvasLayer` + `Label` standard pour overlay HUD. Rendu debug seulement — aucun impact perf release. Flag rouge si `last_input_to_publish_latency_ms > latency_anomaly_threshold_ms` (tuning knob GDD Tuning Knobs, default 0.1 ms release / 0.5 ms debug).

**Control Manifest Rules (Foundation layer)**:
- Required: action `&"debug_toggle"` enregistrée uniquement en debug (story-001 AC-DBG-1) ; overlay gated par `OS.has_feature("debug")`
- Forbidden: overlay rendered en release
- Guardrail: overlay update ≤ 1 ms/frame (≤ 0.5 ms Camera guardrail déjà acquis — le débit HUD debug est cosmetic, pas compté dans Input budget)

---

## Acceptance Criteria

*From GDD `design/gdd/input-system.md`, scoped to this story:*

- [ ] Scène `src/core/input_debug_overlay.tscn` créée avec :
  - [ ] `CanvasLayer` root (layer très élevé, ex: 100)
  - [ ] `Label` "LatencyLabel" affichant `latency_p99: X.XX ms`
  - [ ] `Label` "ActionLabel" affichant la dernière action pressée (vide si aucune depuis 500 ms)
  - [ ] `Label` "MouseModeLabel" affichant `CAPTURED` ou `VISIBLE`
- [ ] Script `src/core/input_debug_overlay.gd` attaché :
  - [ ] `_ready()` : if `not OS.has_feature("debug")`: `queue_free()` + return (garantit non-rendered en release)
  - [ ] Connecté aux signaux `InputManager.jump_pressed`, `dash_pressed`, `attack_pressed`, `restart_pressed` pour update `ActionLabel` + reset après 500 ms via `Timer`
  - [ ] `_process(_delta)` : update `LatencyLabel` (~1 Hz via accumulator) + update `MouseModeLabel` read-through
  - [ ] Flag rouge sur `LatencyLabel` si `InputManager.last_input_to_publish_latency_ms > LATENCY_ANOMALY_THRESHOLD_MS`
- [ ] `_debug_overlay_enabled: bool` membre dans InputManager (ou autoload dédié `DebugManager` à créer si existe déjà — sinon dans InputManager) ; toggle sur press `&"debug_toggle"`
- [ ] Overlay visibility = `_debug_overlay_enabled` (boot à `false` en release forcé, configurable via tuning knob `debug_overlay_default` en debug/editor)
- [ ] **AC-DBG-3** : build debug, press F3 → overlay toggle visible/invisible ; affiche latency p99 + action pressée + mouse mode
- [ ] **AC-DBG-2** : build release, F3 pressé → overlay n'apparaît **jamais** (binary check) ; vérifié smoke pre-release via walkthrough manuel dans `production/qa/evidence/input-debug-overlay-release-{date}.md`

---

## Implementation Notes

*Derived from ADR-0004 D-9 + GDD Tuning Knobs:*

```gdscript
# src/core/input_debug_overlay.gd
extends CanvasLayer

const LATENCY_ANOMALY_THRESHOLD_MS: float = 0.5  # debug default ; 0.1 release (si overlay accessible)
const ACTION_LABEL_TIMEOUT_SEC: float = 0.5
const LATENCY_UPDATE_INTERVAL_SEC: float = 1.0

@onready var _latency_label: Label = $LatencyLabel
@onready var _action_label: Label = $ActionLabel
@onready var _mouse_mode_label: Label = $MouseModeLabel

var _latency_accum: float = 0.0
var _action_clear_timer: float = 0.0

func _ready() -> void:
    if not OS.has_feature("debug"):
        queue_free()
        return
    visible = false  # default OFF — F3 toggle
    # Bind InputManager signals
    InputManager.jump_pressed.connect(_on_action_pressed.bind(&"jump"))
    InputManager.dash_pressed.connect(_on_action_pressed.bind(&"dash"))
    InputManager.attack_pressed.connect(_on_action_pressed.bind(&"attack"))
    InputManager.restart_pressed.connect(_on_action_pressed.bind(&"restart"))

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed(&"debug_toggle"):
        visible = not visible

func _process(delta: float) -> void:
    if not visible:
        return
    _latency_accum += delta
    if _latency_accum >= LATENCY_UPDATE_INTERVAL_SEC:
        _latency_accum = 0.0
        var p99 := InputManager.get_latency_p99_ms()
        _latency_label.text = "latency_p99: %.2f ms" % p99
        _latency_label.modulate = Color.RED if p99 > LATENCY_ANOMALY_THRESHOLD_MS else Color.WHITE
    _mouse_mode_label.text = "mouse_mode: %s" % ("CAPTURED" if InputManager.is_mouse_captured() else "VISIBLE")
    if _action_clear_timer > 0.0:
        _action_clear_timer -= delta
        if _action_clear_timer <= 0.0:
            _action_label.text = "action: —"

func _on_action_pressed(action_name: StringName) -> void:
    _action_label.text = "action: %s" % String(action_name)
    _action_clear_timer = ACTION_LABEL_TIMEOUT_SEC
```

Intégration boot : l'overlay est instancié automatiquement par InputManager `_ready()` en build debug :

```gdscript
# InputManager._ready() addition
if OS.has_feature("debug"):
    var overlay_scene := preload("res://src/core/input_debug_overlay.tscn")
    var overlay := overlay_scene.instantiate()
    get_tree().root.call_deferred("add_child", overlay)
```

Notes clés :
- **Binary gate release** : `if not OS.has_feature("debug"): queue_free()` dans `_ready()` garantit zéro coût runtime en release — pas juste `visible = false`.
- **AC-DBG-2 smoke check** : doit être fait sur un vrai export release (`godot --export-release`), pas juste mock `OS.has_feature = false`. Le testeur lance l'exe, presse F3, confirme rien ne se passe.
- **Update latency 1 Hz** : `get_latency_p99_ms()` est rare par design (évite de trier à chaque frame). Accumulator CPU-cheap.
- **Modulate rouge** : utilise le tuning knob `latency_anomaly_threshold_ms`. En debug interpreter default 0.5 ms (tolérance 5× release). Si dépassé, flag visible → investigation.
- **Pas d'ownership autoload conflit** : l'overlay est un CanvasLayer enfant de `/root`, pas un autoload — évite collisions avec GameStateManager / futurs HUD managers. Si un `DebugManager` autoload apparaît plus tard, refactor possible.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001 : enregistrement action `&"debug_toggle"` en debug (pré-requis — AC-DBG-1)
- Story 006 : `get_latency_p99_ms()` (consommé)
- Story 003-004 : signaux action (consommés)
- Post-MVP : signal `mouse_captured_changed` pour réactivité instant (actuellement polling 1 Hz suffit pour debug)
- Post-MVP : overlay configurable via menu graphics (positionnement, taille)

---

## QA Test Cases

- **AC-DBG-3** : F3 toggle debug
  - Setup : build debug, scène MVP lancée, input capture actif
  - Verify : presser F3 → overlay apparaît avec 3 labels ; bouger souris → overlay persiste ; presser F3 → overlay disparaît
  - Pass condition : screenshot + capture video ≥ 3 toggles dans `production/qa/evidence/input-debug-overlay-{date}.md`

- **AC-DBG-3 bis** : latency displayed + action pressée
  - Setup : build debug, overlay toggled ON
  - Verify : presser `jump` → `action: jump` pendant 500 ms puis `action: —` ; presser `dash` → idem avec "dash" ; `latency_p99` update toutes ~1 s
  - Pass condition : vidéo 10 s montrant les 3 labels dynamiques, sign-off inclus

- **AC-DBG-2** : release build F3 inactif
  - Setup : export release `godot --export-release`, lancer exe sur machine cible
  - Verify : presser F3 plusieurs fois pendant 30 s gameplay
  - Pass condition : overlay ne s'affiche **jamais**, aucune pause, aucun log. Evidence : capture vidéo + `production/qa/evidence/input-debug-overlay-release-{date}.md` avec lead sign-off

---

## Test Evidence

**Story Type**: UI
**Required evidence**:
- `production/qa/evidence/input-debug-overlay-{date}.md` — walkthrough debug build AC-DBG-3 (screenshots + video)
- `production/qa/evidence/input-debug-overlay-release-{date}.md` — AC-DBG-2 release smoke + sign-off

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (debug_toggle action), Story 003 (mouse mode API), Story 004 (signaux gameplay), Story 006 (get_latency_p99_ms)
- Unlocks: rien directement (contribue au DoD de l'epic — debug QoL)

---

## Completion Notes

**Completed**: 2026-04-23
**Criteria**: 6/8 COVERED + 2 DEFERRED
- Auto-vérifiés : scène `input_debug_overlay.tscn` (3 labels), script `input_debug_overlay.gd` (binary gate `queue_free()` release, signaux bind `.bind(&"...")`, accumulator 1 Hz, flag rouge sur seuil, F3 toggle via `_unhandled_input`), instanciation debug-only via `InputManager._ready()` (`call_deferred(&"add_child", overlay)`).
- DEFERRED (playtest UI manuel) : AC-DBG-3 (toggle F3 + 3 labels dynamiques en debug build) + AC-DBG-2 (release smoke via export release). Templates evidence créés et enrichis (hardware, warmup note, binary pass conditions, sign-off structuré) dans `production/qa/evidence/input-debug-overlay-2026-04-23.md` et `input-debug-overlay-release-2026-04-23.md`.

**Deviations** (ADVISORY, toutes documentées) :
1. AC3 mentionne `_debug_overlay_enabled` membre — implémentation utilise la propriété native `visible` de `CanvasLayer` (fonctionnellement identique, conforme au code sample story l.81).
2. UID `.tscn` `uid://debug_overlay_009` non-standard — Godot régénérera au premier import éditeur (diff git cosmétique, pas fonctionnel).
3. Deux warnings specialists résolus inline pendant `/code-review` :
   - Dirty-flag + const strings pour `MouseModeLabel` (remplace interpolation `"mouse_mode: %s" %` → zero alloc/frame en régime permanent, 1 alloc sur transition CAPTURED↔VISIBLE uniquement).
   - `suppress_debug_overlay: bool` public var dans InputManager — permet aux tests d'intégration `InputManagerScript.new() + add_child` d'éviter la pollution de `/root` par un overlay par instance (protège VC-3 zero-alloc story-008).

**Test Evidence**: UI — 2 templates créés (debug walkthrough + release smoke), playtest manuel requis post-merge.

**Code Review**: Complete (run `/code-review src/core/input_debug_overlay.gd src/core/input_debug_overlay.tscn src/core/input_manager.gd` — APPROVED WITH SUGGESTIONS résolues inline ; LP-CODE-REVIEW gate skipped en solo mode).

**Smoke post-implem** : `godot --headless res://tests/performance/input_benchmark.tscn` → EXIT=0, p99=14.994 ms, hp p99=0.108 ms — zéro régression autoload après ajout du boot overlay debug.
