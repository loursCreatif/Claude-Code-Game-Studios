# Interaction Pattern Library — CHROME://ASCENT

> **Status** : Initialized (baseline)
> **Last Updated** : 2026-05-11
> **Owner** : ux-designer
> **Accessibility Tier** : Standard (cf. `design/accessibility-requirements.md`)
> **Related** : `design/gdd/input-system.md` (ADR-0004), `docs/architecture/architecture.md` §6, `docs/architecture/adr-0015-accessibility-interface-layer.md` D-1 (AccessibilityService — source canonique `reduce_motion` / `reduce_flash`)

---

## 1. Purpose

Ce document fige les patterns d'interaction réutilisables à travers l'UI et les systèmes gameplay. Chaque UX spec (`design/ux/[screen].md`, `design/ux/hud.md`) référence les patterns d'ici plutôt que de les redéfinir. Le library évolue en append-only : un pattern adopté n'est jamais supprimé sans migration plan.

Principe directeur : **chaque pattern respecte Pillar 1 FLOW (latence ≤ 1 frame perçue) et Pillar 4 PERFORMANCE (zero-alloc hot path)**.

---

## 2. Input Patterns

### P-INP-001 — Tick-based polling (gameplay)

**Quand l'utiliser** : systèmes gameplay lisant un input dans `_physics_process` au tick N pour une press ayant eu lieu entre tick N-1 et N.

**API** : `InputManager.was_pressed_this_tick(action: StringName) -> bool`

**Interdit** : `Input.is_action_just_pressed()` direct (ADR-0001 forbidden_pattern). `InputManager.is_action_just_pressed()` retiré de l'API publique (ADR-0004 D-2).

**Exemple** :
```gdscript
# MovementController._physics_process
if InputManager.was_pressed_this_tick(&"jump"):
    _try_jump()
```

**Rationale** : ADR-0001 + ADR-0004 D-1/D-3 — swap `_pressed↔_consumed` en début de `_physics_process`, AC-CS-1 tick N parity.

### P-INP-002 — Mouse motion consumption

**Quand l'utiliser** : tout consumer de mouse delta (Camera, Menu rotation, Cursor position).

**API** : `InputManager.mouse_motion.connect(handler)` signal.

**Interdit** : lire `Input.get_last_mouse_velocity()` ou `InputEventMouseMotion` direct dans `_input`/`_unhandled_input` ailleurs que dans InputManager.

**Exemple** :
```gdscript
# CameraSystem._ready
InputManager.mouse_motion.connect(_on_mouse_motion)

func _on_mouse_motion(delta: Vector2) -> void:
    player.rotate_y(-delta.x * mouse_sensitivity)
    camera_arm.rotate_x(-delta.y * mouse_sensitivity * (-1 if mouse_y_inverted else 1))
```

### P-INP-003 — Menu navigation (UI focus)

**Quand l'utiliser** : tout écran de menu (main menu, pause, settings, shop).

**API** : Godot `Control.focus_mode = FOCUS_ALL` + `grab_focus()` + `focus_neighbor_*` assignments. Utilisation des actions `ui_up / ui_down / ui_left / ui_right / ui_accept / ui_cancel` Godot défaut.

**Dual-focus consideration** : Godot 4.6 dual-focus system (VR-3 advisory) — tests integration focus alt-tab + reacquisition requis Sprint 1 (cf. ADR-0004 VC-1).

**Accessibility** : `ui_cancel` traverse toujours même pendant `InputManager.request_disable` (refcount release pattern — ADR-0004 D-4). Garantit que pause/unpause reste accessible.

### P-INP-004 — Accessibility gating

**Quand l'utiliser** : tout système qui doit être suspendu pendant menu/checkpoint/cutscene.

**API** : `InputManager.request_disable(self)` + cleanup automatique via `tree_exited` (ADR-0004 D-4 CONNECT_ONE_SHOT). `release_enable_request(self)` explicite si le disabled state est levé avant destruction.

**Interdit** : `InputManager.set_enabled(false)` direct sans refcount (ADR-0004 forbidden_pattern `set_enabled_bool_global_without_refcount`).

---

## 3. Feedback Patterns

### P-FB-001 — Signal → consumer reaction

**Quand l'utiliser** : tout événement gameplay observable (Movement dash_started, Combat attacked, etc.).

**API** : producteur déclare signal typé dans son script (ADR-0005 D-1 D-3). Consumer appelle `connect()` explicitement dans `_ready()`. CONNECT_DEFERRED si handler coûte > 0.5 ms / instancie Node / play AudioStream / alloue > 256 bytes (ADR-0005 D-5 critères a-d).

**Interdit** :
- EventBus autoload pour intra-gameplay (ADR-0005 forbidden `event_bus_autoload_for_movement_intra_gameplay_events`).
- Consumer mute le state du producteur depuis handler (ADR-0005 forbidden `mutate_movement_state_from_signal_handler`).

**Exemple** :
```gdscript
# VFXFeedback._ready
movement_controller.dash_started.connect(_on_dash_started, CONNECT_DEFERRED)
# deferred car instancie un Node3D trail (critère a) + play AudioStream (critère b)
```

### P-FB-002 — Shake additif Camera

**Quand l'utiliser** : feedback tactile court (wall-jump kick, impact, damage telegraph).

**API** : `CameraSystem.add_shake(amplitude: float, duration: float)` ou `add_shake_roll(amplitude, duration)` pour un shake roll. Decay exponentiel λ=12 (ADR-0002 + Camera GDD).

**Accessibility** : `reduce_motion` toggle ON → amplitude × 0.3 max. `reduce_flash` n'affecte pas le shake (seulement flash VFX).

**Interdit** : mutation directe de `camera3d.rotation` ou `camera_effects.rotation.z` hors CameraSystem.

### P-FB-003 — Respawn overlay

**Quand l'utiliser** : uniquement à `MovementController.died` → `respawned`.

**API** : owned par CameraSystem (cf. Camera GDD Key Decisions). Overlay rouge `Color(0.4, 0, 0, 0.6)` 100 ms + flash blanc 50 ms. Yaw préservé pendant respawn 200 ms.

**Accessibility** : `reduce_flash` → amplitude × 0.2 (10 % max opacity au lieu de 60 %).

---

## 4. HUD Patterns

### P-HUD-001 — Persistent counter (credits, combo)

**Quand l'utiliser** : valeur numérique affichée en continu.

**Layout** : coin écran (top-left credits, top-right dash cooldown). Text contrast ≥ 4.5:1 (accessibility §2). Font ≥ 20 px à 1080p.

**Update** : bind au signal producer (`credit_collected`, `dash_started/ended`). Pas de poll dans `_process` (Pillar 4 PERF).

### P-HUD-002 — Transient notification (secret found, credit pickup)

**Quand l'utiliser** : feedback temporaire non-bloquant.

**Layout** : text overlay centre-haut. Fade-in 50 ms, hold 2 s (extensible 5 s via settings), fade-out 200 ms.

**Accessibility** : `reduce_motion` → cross-fade only (pas de slide-down animation).

---

## 5. Menu Patterns

### P-MENU-001 — Settings slider

**Quand l'utiliser** : tout paramètre continu (volume, sensitivity, FOV, UI scale).

**Layout** : HSlider + label + current-value text + reset-to-default button. Range + default documentés dans le settings file (`input_settings.tres`, `camera_settings.tres`, `audio_settings.tres`).

**Accessibility** : focus_all, keyboard left/right ajuste par step 5 %. Full text label (pas d'icon-only).

### P-MENU-002 — Settings toggle (boolean)

**Quand l'utiliser** : tout paramètre booléen (mouse_y_inverted, reduce_motion, reduce_flash, vsync).

**Layout** : CheckButton + label. Text label explicite (pas d'icon seulement).

**Default values** : définis dans le settings Resource. Changement immédiat (pas de "Apply" button).

### P-MENU-003 — Binding remap

**Quand l'utiliser** : dans Settings → Controls.

**Layout** : ligne par action, 2 colonnes (Primary / Secondary binding). Click → "Press any key..." prompt. Conflict warning si duplicate.

**Accessibility** : MVP supporte keyboard/mouse remap. Gamepad remap = Tier 2+.

---

## 6. Transition Patterns

### P-TRANS-001 — Scene transition

**Quand l'utiliser** : main menu → gameplay, gameplay → boss, gameplay → death screen.

**API** : `GameStateManager.request_scene_transition(scene_path)` (ADR-0007 à créer).

**Feel** : fade-to-black 200 ms + load + fade-in 200 ms. Pas de scale/zoom animation (incompatible reduce_motion).

**Accessibility** : `reduce_motion` → cut direct 50 ms.

---

## 7. Error / Confirmation Patterns

### P-ERR-001 — Destructive action confirmation

**Quand l'utiliser** : "Delete save slot", "Reset all settings", "Exit to desktop".

**Layout** : modal dialog, 2 buttons (`Cancel` focused default, `Confirm`). `ui_cancel` = cancel. Text explicite quant à l'irréversibilité.

---

## 8. Pattern Adoption Tracking

| Pattern | First adopted | Screens using it |
|---------|---------------|------------------|
| P-INP-001 | MovementController (Sprint 1) | Movement, Combat (planned) |
| P-INP-002 | CameraSystem (Sprint 1) | Camera, Menu cursor (planned) |
| P-INP-003 | MenuSystem (planned) | Main menu, Pause menu, Settings, Shop |
| P-INP-004 | GameStateManager (planned) | Pause, Checkpoint, Cutscene |
| P-FB-001 | MovementController (Sprint 1) | All Core/Feature consumers of Movement signals |
| P-FB-002 | CameraSystem (Sprint 1) | Wall-jump, Combat impact (planned) |
| P-FB-003 | CameraSystem (Sprint 1) | Respawn system |
| P-HUD-001 | HUD (planned) | Credits counter, Dash cooldown |
| P-HUD-002 | HUD (planned) | Credit pickup, Secret found |
| P-MENU-001 | MenuSystem (planned) | Settings (audio, sensitivity, FOV) |
| P-MENU-002 | MenuSystem (planned) | Settings (accessibility toggles, vsync) |
| P-MENU-003 | MenuSystem (planned, Tier 2+ for gamepad) | Settings → Controls |
| P-TRANS-001 | GameStateManager (planned) | All scene transitions |
| P-ERR-001 | MenuSystem (planned) | Settings reset, Save delete |

---

## 9. Maintenance

- Nouveau pattern → append section 2-7 correspondante + ajouter ligne §8 tracking.
- Pattern déprécié → marquer `[DEPRECATED]` avec migration plan + date. Ne pas supprimer avant migration complète.
- Conflit entre patterns → escalade creative-director (cf. coordination-rules).

---

## 10. Accessibility Tier Coverage

Rétro-référence canonique : **ADR-0015 D-1** (`docs/architecture/adr-0015-accessibility-interface-layer.md`)
— définit l'autoload `AccessibilityService` comme single-source-of-truth pour `reduce_motion` / `reduce_flash` et les multipliers per-system.

Les patterns de cette library qui portent des features accessibility sont couverts aux tiers suivants :

| Pattern | Feature accessibility | Tier | Service API (ADR-0015 D-3) |
|---------|----------------------|------|---------------------------|
| P-INP-003 | `ui_cancel` toujours actif même pendant `request_disable` | Tier 1 (baseline MVP) | n/a — gating InputManager (ADR-0004 D-4) |
| P-INP-004 | Accessibility gating refcount (pause/checkpoint/cutscene) | Tier 1 (baseline MVP) | n/a — InputManager |
| P-FB-002 | Camera shake → amplitude × 0.3 si `reduce_motion` | Tier 1 (baseline MVP) | `AccessibilityService.get_camera_shake_mult()` |
| P-FB-003 | Respawn flash → opacity × 0.2 si `reduce_flash` | Tier 1 (baseline MVP) | `AccessibilityService.get_flash_mult()` |
| P-HUD-001 | Contraste texte ≥ 4.5:1, font ≥ 20 px | Tier 1 (baseline MVP) | n/a — valeurs visuelles statiques |
| P-HUD-002 | Notification → cross-fade only si `reduce_motion` (pas de slide) | Tier 1 (baseline MVP) | `AccessibilityService.is_reduce_motion_enabled()` |
| P-MENU-001 | Slider keyboard navigable, full text label | Tier 1 (baseline MVP) | n/a — Godot Control focus |
| P-MENU-002 | Toggle `reduce_motion` / `reduce_flash` accessibles dans Settings | Tier 2 (expanded — Settings Menu UI) | `AccessibilityService.apply_settings()` + `save_settings()` |
| P-MENU-003 | Keyboard/mouse remap (gamepad remap Tier 2+) | Tier 1 clavier / Tier 2 gamepad | n/a — InputManager remap |
| P-TRANS-001 | Scene transition → cut direct 50 ms si `reduce_motion` | Tier 1 (baseline MVP) | `AccessibilityService.is_reduce_motion_enabled()` |

**Résumé tiers** :
- **Tier 1 baseline MVP** : reduce_motion appliqué sur shake (P-FB-002), flash respawn (P-FB-003), notifications (P-HUD-002), transitions (P-TRANS-001) + contraste/focus statiques (P-HUD-001, P-MENU-001, P-INP-003/004).
- **Tier 2 expanded** : Settings Menu UI exposant les toggles `reduce_motion` / `reduce_flash` à l'utilisateur (P-MENU-002) — différé post-MVP.
- **Tier 3 advanced** : non couvert par les patterns actuels de cette library (colorblind filter, font scaling, screen reader — cf. ADR-0015 REQ-10 open questions OQ-ACC-3/4/5).
