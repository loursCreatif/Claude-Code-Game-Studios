# Epic: HUD System

> **Layer**: Presentation
> **GDD**: `design/gdd/hud-system.md` (In Design r1.1 — solo auto-approve, amendement r2.2 cascade NB-CRD-6 Option A 2026-04-28 — pulse différencié SECRET tween +50% durée)
> **Architecture Module**: `HUDSystem` (autoload Godot — `src/gameplay/hud/hud_system.gd` ; CanvasLayer enfant `layer = 50` < 100 ; Label `CreditCounterLabel` ancré top-right)
> **Status**: In Progress (5/6 Complete 2026-05-05 — story-001 skeleton ✅ + story-002 listener ✅ + story-003 visibility ✅ + story-004 pulse différencié source KILL/SECRET ✅ AC-HUD-36 + OQ-HUD-5 wall-clock + story-005 anti-patterns lint static ✅ 16/16 PASS)
> **Stories**: 6 created 2026-05-04 (4 Logic + 1 Integration + 1 Visual/Feel ADVISORY) — 5 Complete + 1 Ready (story-006 playtest manuel BLOCKED)
> **Manifest Version**: 2026-05-04

## Overview

Le HUD System est l'autoload Godot 4.6 **Presentation layer outbound-only** qui pilote l'unique élément d'UI visible pendant le gameplay actif de CHROME://ASCENT : un compteur de crédits monospace blanc froid (`CreditCounterLabel`) ancré en coin supérieur droit, à l'intérieur d'un `CanvasLayer.layer = 50` (< 100 réservé GSM fade overlay). Il est exclusivement consommateur — il **ne mute aucun système amont, ne route aucune décision gameplay, et n'émet aucun signal**. Au boot, il pull synchronement `CreditEconomy.get_total()` et `GameStateManager.get_current_state()` (ADR-0007 D-9 pattern pull). À chaque émission `CreditEconomy.credits_changed(total, delta, source: SourceKind)` SYNC, il met à jour le `Label.text` dans le **même `_physics_process` tick** que le kill (Pillar 1 FLOW garde-fou — débloque AC-CRD-46 listener `_on_credits_changed`). La visibilité est gouvernée par `GameStateManager.state_changed` CONNECT_DEFERRED : visible en `PLAYING` + `RESPAWNING`, masqué en `MENU` / `PAUSED` / `BOSS_DEFEATED`. Pulse de scale différencié par source (r1.1 amendement NB-CRD-6 Option A) : `CREDIT_COUNTER_TWEEN_KILL_MS = 100 ms` vs `CREDIT_COUNTER_TWEEN_SECRET_MS = 150 ms` (+50%) — cohérent Audio Rule 17 (clac aigu pitch +5 semitones bus `SFX`). Le scope MVP **exclut** intentionnellement health bar / ammo / minimap / compass / objective marker / hint UI / death screen / damage numbers — tous violent un anti-pillar du game-concept. Sert **Pillar 2 — LA PROGRESSION SE VOIT** primaire + **Pillar 1 — FLOW AVANT TOUT** garde-fou (zero alloc hot path) + **Pillar 3 — UNE SECONDE CHANCE** par soustraction (pas de death screen) + **Pillar 4 — SECRETS = MOUVEMENT** par différenciation source kill/secret.

## Governing ADRs

Aucun ADR HUD-spécifique requis MVP — système Presentation orchestré par contrats upstream verrouillés (analogue Menu / Shop / Credit epics). Trigger ADR escalation : si UI Toolkit Godot 4.5+ migration (OQ-HUD-7), si Accessibility Tier 3 contraintes architecturales non absorbables (text scaling slider + screen reader AccessKit), OU si introduction room indicator + cooldown indicator Tier 2+ avec data binding pattern.

ADRs hérités gouvernant l'implémentation HUD :

| ADR | Decision Summary | Engine Risk |
|-----|------------------|-------------|
| **ADR-0001** Physics Rate 60 Hz | Handler `_on_credits_changed` SYNC s'exécute dans le `_physics_process` tick de Credit Economy. Pillar 1 FLOW garde-fou — `Label.text = str(total)` dans le **même tick** que `enemy_killed → credits_changed`. | LOW |
| **ADR-0007** Game State Manager + Scene Transition | D-9 pattern pull `get_current_state()` au `_ready()` HUD (R-HUD-2 — pas d'attente signal `game_booted` qui n'existe pas, GSM Rule 12 minimisation API) ; D-10 5 verbes publics figés (HUD utilise 0 — outbound-only) ; signal `state_changed(new_state: State)` SYNC côté GSM consommé via CONNECT_DEFERRED côté HUD (R-HUD-4 — visibility logic implique potentiellement rebuild structurel). | LOW |
| **ADR-0010** Save/Load Persistence (ConfigFile Ratification) | R-SAV-9 délégation pure — HUD ne référence **jamais** SaveLoad APIs (AC-HUD-35 grep enforce). Le HUD ne persiste rien — l'état visuel est dérivé du `total_credits` Credit Economy. | LOW |

**Engine Risk global** : **LOW** (architecture minimale Presentation : 1 autoload + 1 CanvasLayer + 1 Label + 2 connexions signal + Tween Godot natif. Aucune API post-cutoff Godot — `Control` + `Label` + `CanvasLayer` + `Tween.tween_property` + `set_ignore_time_scale` stables Godot 4.0+. 1 verification empirique pré-Sprint HUD : OQ-HUD-5 wall-clock `set_ignore_time_scale(true)` cohérence pulse 100/150 ms quand Combat slow-mo `SLOW_MO_SCALE = 0.3` au même tick — recommandation MVP `true`).

## GDD Requirements

HUD System utilise un schéma `R-HUD-N` (Rules numérotées 1-15 dans GDD §Detailed Rules) comme stable IDs en attendant rotation `/architecture-review` post-Sprint 1. **Aucune entrée TR-hud-* dans `docs/architecture/tr-registry.yaml`** (analogue Menu / Shop / Credit / Save-Load / Audio epics — pattern récurrent stable IDs jusqu'à rotation `/architecture-review`).

### Core Rules (15 R-HUD)

| R-HUD | Requirement (résumé) | ADR Coverage |
|-------|---------------------|--------------|
| R-HUD-1 | Autoload data-light `HUDSystem` registered AVANT/APRÈS contrainte : `InputManager → GameStateManager → CreditEconomy → HUDSystem` ordre `project.godot` | ADR-0007 D-1 + GDD seul ✅ |
| R-HUD-2 | Pattern pull boot — `GSM.get_current_state()` + `CreditEconomy.get_total()` au `_ready()` (jamais signal `game_booted`) | ADR-0007 D-9 ✅ |
| R-HUD-3 | Connexion SYNC à `CreditEconomy.credits_changed` (pas CONNECT_DEFERRED — Pillar 1 same-frame update) | GDD seul (Pillar 1) ✅ |
| R-HUD-4 | Connexion CONNECT_DEFERRED à `GameStateManager.state_changed` (consumer lourd visibility logic) | ADR-0007 D-10 ✅ |
| R-HUD-5 | Pulse de scale différencié par source — KILL `100 ms` / SECRET `150 ms` (r1.1 amendement NB-CRD-6 Option A) ; magnitude identique `1.05` MVP | F-HUD-1 r1.1 ✅ |
| R-HUD-6 | `delta < 0` (`SPEND_SHOP`) → hard set sans tween — `Label.scale == Vector2.ONE` | GDD seul ✅ |
| R-HUD-7 | `delta == 0` (`BOOT_HYDRATE`) → hard set, jamais de tween (garde-fou faux pulse boot) | GDD seul ✅ |
| R-HUD-8 | Visibility par State machine binaire — `visible = (state in [PLAYING, RESPAWNING])` | ADR-0007 D-2 ✅ |
| R-HUD-9 | Pendant `RESPAWNING` (50 ms wall-clock) — counter visible, pas de freeze, pas de fade — Pillar 3 | F-MOV-RESPAWN_DELAY = 0.05 s ✅ |
| R-HUD-10 | Pendant `PAUSED` — counter masqué (Menu owns full-screen overlay) | ADR-0007 D-2 + R-MNU-3 ✅ |
| R-HUD-11 | Layer ordering strict — `HUD_CANVAS_LAYER = 50` < `100` (GSM owns 100 fade overlay + focus pause) | GDD seul + AC-MNU layer convention ✅ |
| R-HUD-12 | Outbound-only zero couplage cross-feature — HUD ne référence **jamais** Combat/Level/Movement/Enemy/Audio/Player/Input/SaveLoad | GDD seul + lint static ✅ |
| R-HUD-13 | Zero allocation hot path — `_on_credits_changed` ≤ 1 alloc tolérée (`str(total)` boxing int → String) | `.claude/rules/no-alloc-hot-paths.md` à étendre ✅ |
| R-HUD-14 | Aucun input HUD MVP — HUD ne consomme **jamais** `InputManager.*` ni `Input.*` | `.claude/rules/input-singleton-main-thread-only.md` cover-all ✅ |
| R-HUD-15 | Aucun SFX HUD MVP — HUD n'appelle **jamais** `AudioServer.*` / `AudioStreamPlayer.*` / `AudioSystem.play_2d/3d` | audio-system.md ligne 169 + AC-HUD-34 ✅ |

**Coverage** : **15/15 R-HUD ✅** par contrats upstream (ADR-0001 + ADR-0007 + ADR-0010) + GDD self-contained. Aucun gap, aucun untraced requirement. **0 BLOCKED** au niveau architecture.

### Formulas (3 F-HUD)

| Formule | Description | Couverture |
|---------|-------------|------------|
| F-HUD-1 | Pulse de scale credit counter différencié source (r1.1) — `D = CREDIT_COUNTER_TWEEN_KILL_MS=100` si KILL, `CREDIT_COUNTER_TWEEN_SECRET_MS=150` si SECRET ; magnitude `1.05` ; easing `EASE_IN_OUT TRANS_SINE` ; wall-clock `set_ignore_time_scale(true)` | F-HUD-1 r1.1 ✅ |
| F-HUD-2 | Positionnement responsive — `position_x = viewport_width - HUD_MARGIN_RIGHT_PX - label_width` ; `position_y = HUD_MARGIN_TOP_PX` ; anchor `PRESET_TOP_RIGHT` | F-HUD-2 ✅ |
| F-HUD-3 | (Provisoire Tier 2+) Flash couleur source-dependent — `if source == SECRET: label_color_tween(#E8E8F0 → #00D4FF → #E8E8F0, 180 ms)` | OQ-HUD-1 latent ✅ |

### Edge Cases (16 EC-HUD)

Couvertes par GDD §Edge Cases — EC-HUD-01 boot autoload order broken (assert), EC-HUD-02 credits_changed pendant MENU/BOSS_DEFEATED (silent update), EC-HUD-03 credits_changed pendant PAUSED, EC-HUD-04 state_changed + credits_changed même tick (ordre déterministe SYNC puis DEFERRED), EC-HUD-05 multi-kill 3 emits (`MAX_KILLS_PER_SWING = 3`), EC-HUD-06 tween en cours PLAYING → PAUSED (kill tween), EC-HUD-07 tween en cours PLAYING → RESPAWNING (continue Pillar 3), EC-HUD-08 `total < 0` impossible (assert defensive), EC-HUD-09 `total > 999999` (Godot int64 native), EC-HUD-10/11 resize / fullscreen toggle (anchor handle), EC-HUD-12 Save/Load mid-run BOOT_HYDRATE (hard set sans burst), EC-HUD-13 mutual kill (Combat AC-CMB-41) — credit gain visible AVANT respawn transition (Pillar 2 + Pillar 3 cohérents), EC-HUD-14 float scaling content_scale_factor (Godot handle), EC-HUD-15 mode debug F3 Combat (HUD MVP n'affiche pas), EC-HUD-16 UI Master mute Audio (HUD muet MVP).

### Acceptance Criteria (35 ACs r1.1, 13 catégories A-M)

33 BLOCKING + 2 ADVISORY ; 33 AUTO (94%) + 1 PLAYTEST + 1 MANUAL. Couvertes par GDD §Acceptance Criteria — Groupes : A Boot & Init ×4 (AC-HUD-01..04), B Counter increment ×3 (AC-HUD-05..07), C Counter decrement ×2 (AC-HUD-08..09), D Counter rollback ×2 (AC-HUD-10..11), E Visibility par State ×5 (AC-HUD-12..16), F Pattern pull boot ×2 (AC-HUD-17..18), G Multi-kill swing ×2 (AC-HUD-19..20), H Idempotence respawn ×2 (AC-HUD-21..22), I Source-dependent feedback ×2 (AC-HUD-23 ADVISORY PLAYTEST + AC-HUD-24 BLOCKING), J Layer ordering ×2 (AC-HUD-25..26), K Performance ×2 (AC-HUD-27..28), L Edge cases UI ×2 (AC-HUD-29 BLOCKING + AC-HUD-30 ADVISORY MANUAL), M Anti-patterns ×5 (AC-HUD-31..35) + AC-HUD-36 (r1.1 BLOCKING) pulse durée différenciée KILL vs SECRET avec invariant balance `tween_secret > tween_kill`.

## Dependencies

### Hard (HUD ne peut pas démarrer sans)

| Système | Direction | Status | Contrat |
|---------|-----------|--------|---------|
| **Credit Economy** | In (Hard) | Designed r1 — Sprint 1 implémentation 7/8 Complete | **In** : `get_total() -> int` au `_ready()` (boot pull) ; signal `credits_changed(total: int, delta: int, source: SourceKind)` SYNC pendant le run ; enum `SourceKind { KILL, SECRET, SPEND_SHOP, BOOT_HYDRATE }`. HUD lit, n'écrit jamais. **Bidirectional check** : Credit r3 §Cross-system contracts table cite "HUD downstream consume `credits_changed` aval" ✅ — débloque AC-CRD-46. |
| **Game State Manager** | In (Hard) | APPROVED r1 (GDD), ADR-0007 Accepted, **GSM autoload Not Started** | **In** : `get_current_state() -> State` au `_ready()` (boot pull, ADR-0007 D-9) ; signal `state_changed(new_state: State)` CONNECT_DEFERRED côté HUD (GSM Rule 4 / ADR-0007 D-10) ; enum `State { MENU, PLAYING, PAUSED, RESPAWNING, BOSS_DEFEATED }`. HUD lit, n'écrit jamais. **Bidirectional check** : GSM GDD §Interactions ligne 113 + UI Requirements ligne 419 mentionnent HUD ✅. |

### Soft (interface accessible mais non consommée MVP)

| Système | Status | Contrat |
|---------|--------|---------|
| **Player Combat** | APPROVED r6 — 20/22 Complete | Property `cooldown_ratio: float` read-only — non affichée MVP (Combat §Interactions ligne 275 "feel no UI"). Tier 2+ knob `HUD_COOLDOWN_INDICATOR_ENABLED`. |
| **Level System** | APPROVED r3 — 23/23 Complete | Signal `room_entered(room_index, total_rooms)` non consommé MVP (OQ-HUD-2 différé Tier 2+). Knob `HUD_ROOM_INDICATOR_ENABLED` latent. |

### Peers (no-conflict)

| Système | Status | Note |
|---------|--------|------|
| **Menu System** | 13/13 Complete | Menu owns full-screen pause overlay. HUD se masque pendant `PAUSED` via signal GSM, jamais via appel direct au Menu. Pas de shared API. Layer convention HUD=50 < Pause=80 < GSM=100. |
| **VFX & Feedback** | Not Started | VFX/Camera owns damage flash mort 200 ms fondu rouge (game-concept ligne 98). HUD n'a aucun élément full-screen. |
| **Audio System** | 12/12 Complete | Aucun SFX HUD MVP (audio-system.md ligne 169). Tier 2+ pickup chime à router via `AudioSystem.play_2d` si décidé. |
| **Save/Load** | 8/8 Complete | HUD ne persiste rien — état dérivé `total_credits` Credit Economy. AC-HUD-35 grep enforce zero SaveLoad ref. |
| **Input System** | 10/10 Complete | HUD ne consomme jamais Input. Lint cover-all `.claude/rules/input-singleton-main-thread-only.md` couvre HUD. |

### Anti-deps (zéro reference — R-HUD-12 contrainte architecturale dure)

`CombatSystem`, `LevelSystem`, `MovementController`, `EnemySystem`, `AudioSystem`, `Player.*`, `InputManager`, `SaveLoadSystem` — lint statique cover-all (AC-HUD-35 grep). Toute future référence requiert amendement R-HUD-12.

### Bidirectional Check (5/5 PASS)

- Credit Economy r3 §Cross-system contracts cite HUD downstream `credits_changed` ✅ — débloque AC-CRD-46
- GSM GDD r1 §Interactions ligne 113 + UI Requirements ligne 419 cite HUD ✅
- Player Combat r6 §Interactions ligne 275 cite HUD `cooldown_ratio` Tier 2+ ✅
- Level System r3 §Interactions ligne 229 cite HUD `room_entered` Tier 2+ consumer ✅
- Audio System r2.1 ligne 169 cite HUD no SFX MVP ✅

## Definition of Done

This epic is complete when :

- [ ] All stories implémentées, reviewed via `/code-review`, et closed via `/story-done`
- [ ] All **35 ACs r1.1 + AC-HUD-36** vérifiés (33 BLOCKING + 2 ADVISORY ; 33 AUTO + 1 PLAYTEST + 1 MANUAL)
- [ ] **Boot lifecycle (R-HUD-1/2)** : autoload `HUDSystem` registered `project.godot` APRÈS InputManager → GSM → CreditEconomy ; assert `GSM != null and CreditEconomy != null` au `_ready()` ; CanvasLayer enfant `layer = 50` instancié ; Label `CreditCounterLabel` ancré `PRESET_TOP_RIGHT` — AC-HUD-01..04 PASS
- [ ] **Pattern pull (R-HUD-2)** : `GSM.get_current_state()` + `CreditEconomy.get_total()` appelés exactement 1× au `_ready()` chacun ; `Label.text = str(initial_total)` hard set avant 1ère frame rendue — AC-HUD-17..18 PASS
- [ ] **Connect SYNC + DEFERRED (R-HUD-3/4)** : `CreditEconomy.credits_changed.connect(_on_credits_changed)` sans flag (SYNC) ; `GameStateManager.state_changed.connect(_on_state_changed, CONNECT_DEFERRED)` — AC-HUD-04 PASS
- [ ] **Counter increment KILL (R-HUD-5)** : `delta > 0 + source == KILL` → `Label.text = str(total)` hard set + tween scale `1.0 → 1.05 → 1.0` durée `100 ms` wall-clock — AC-HUD-05 + AC-HUD-36 (a) PASS
- [ ] **Counter increment SECRET (R-HUD-5 r1.1)** : `delta > 0 + source == SECRET` → tween scale durée `150 ms` wall-clock ; **invariant balance** `tween_secret.duration > tween_kill.duration` strictement — AC-HUD-06 + AC-HUD-36 (b)(c) PASS
- [ ] **Multi-kill collision (R-HUD-5)** : si tween en cours quand nouveau signal arrive, `tween.kill()` + `create_tween()` redémarre à scale courante avec durée du nouveau source ; valeur finale `Label.text == str(N+Σdelta)` sans overshoot — AC-HUD-07 + AC-HUD-19/20 + AC-HUD-36 (e) PASS
- [ ] **Counter decrement (R-HUD-6)** : `delta < 0 + source == SPEND_SHOP` → hard set sans tween ; `Label.scale == Vector2.ONE` — AC-HUD-08..09 PASS
- [ ] **Counter rollback (Credit Rule 4 atomicité)** : `try_spend` échoué = aucun signal émis = HUD reste à `str(N)` — AC-HUD-10..11 PASS
- [ ] **BOOT_HYDRATE (R-HUD-7)** : `delta == 0` → hard set, jamais de tween ; `Tween.is_running() == false` après traitement — AC-HUD-24 PASS
- [ ] **Visibility par State (R-HUD-8/9/10)** : `visible = (state in [PLAYING, RESPAWNING])` ; PAUSED hidden ; RESPAWNING reste visible (Pillar 3) ; BOSS_DEFEATED hidden — AC-HUD-12..16 PASS
- [ ] **Idempotence respawn** : `Checkpoint._restore_from_snapshot()` ne réémet pas `credits_changed` (Credit Rule 2) → counter reste pré-mort `N` ; pas de re-pull `get_total()` au retour PLAYING — AC-HUD-21..22 PASS
- [ ] **Layer ordering (R-HUD-11)** : `CanvasLayer.layer == HUD_CANVAS_LAYER == 50` ; `< HUD_LAYER_MAX == 100` (GSM owns 100) — AC-HUD-25..26 PASS
- [ ] **Performance (R-HUD-13)** : handler `_on_credits_changed` ≤ 0.5 ms wall-clock ; 1000 events `credits_changed` `MEMORY_STATIC` delta < 64 KB — AC-HUD-27..28 PASS
- [ ] **Resize tolerance** : 1080p → 1440p programmatique — Label reste in-bounds, lisible ; anchor `PRESET_TOP_RIGHT` Godot natif — AC-HUD-29 PASS
- [ ] **Anti-patterns (R-HUD-12/14/15 + Pillars 1/3/4)** : grep statique zero match `death_screen|game_over|respawn_countdown|minimap|radar|enemy_marker|health_bar|shield_bar|ammo_counter` dans HUD scene tree ; zero `AudioServer|AudioStreamPlayer|play_2d|play_3d` ; zero `CombatSystem|LevelSystem|MovementController|EnemySystem|AudioSystem|Player\.|InputManager|SaveLoad` references — AC-HUD-31..35 PASS
- [ ] **Visual/Feel ADVISORY (Pillar 2)** : playtest evidence frame-by-frame screencap démontre `delta = F1 - F0 ∈ [0, 1]` (HUD update même frame que kill ou 1 frame tolérance ≤ 16.6 ms) — AC-HUD-23 PLAYTEST + cross-reference credit-008 close-out
- [ ] **MANUAL ADVISORY** : toggle plein écran ↔ fenêtré — counter reste positionné selon anchor, observateur humain confirme lisibilité sans dérive — AC-HUD-30 MANUAL sign-off
- [ ] **Bidirectional integration vérifié** : credit-economy story-008 (`Visual/Feel ADVISORY frame-perfect`) close-out par evidence shared avec hud-006 ; Audio Rule 17 cohérence cross-system (SECRET pulse +50% durée HUD ↔ clac aigu pitch +5 semitones bus SFX Audio).

## Cross-references / Unblocks

- **Unblocks** : `production/epics/credit-economy-system/story-008-visual-feel-hud-frame-perfect.md` (Blocked sur absence epic HUD avant 2026-05-04). Story HUD-002 (listener `_on_credits_changed`) + Story HUD-006 (playtest frame-perfect evidence) couvrent l'AC-CRD-46 ; credit-008 reste Ready en attente convergence HUD-002 + HUD-006 OU subsumé par HUD-006 (à clarifier au moment de close-out).
- **Cross-references Audio (r2.2)** : Audio Rule 17 (clac aigu pitch +5 semitones bus `SFX` pour `secret_collected`, sidechain n'arme pas, pas de ducking) cohérent avec HUD r1.1 R-HUD-5 (SECRET pulse +50% durée). Cascade NB-CRD-6 Option A creative-director adjudication 2026-04-28.
- **Layer convention preserved** : HUD=50 < Pause=80 (Menu R-MNU-14) < GSM fade=100 (GSM ligne 395 ownership).

## Cluster décomposition Stories MVP (~6 stories)

| # | Cluster | Story | Type | ACs couvertes |
|---|---------|-------|------|---------------|
| C1 ✅ | Architecture / Boot | story-001 autoload skeleton + CanvasLayer layer=50 + Label anchor PRESET_TOP_RIGHT + pattern pull GSM/Credit boot **(Complete 2026-05-05 — 6/6 PASS)** | Logic | AC-HUD-01/02/03/04/17/18 |
| C2 ✅ | Pull pattern credits_changed | story-002 listener `_on_credits_changed(total, delta, source)` SYNC same-frame Label.text update + hard set BOOT_HYDRATE / SPEND_SHOP / multi-kill collision tween.kill() **(Complete 2026-05-05 — 12/12 PASS — AC-CRD-46 unblocked)** | Integration | AC-HUD-05/06/07/08/09/10/11/19/20/21/22/24 |
| C3 ✅ | Visibility State machine | story-003 listener `_on_state_changed` CONNECT_DEFERRED + visibility table PLAYING/RESPAWNING true / MENU/PAUSED/BOSS_DEFEATED false + tween kill PAUSED **(Complete 2026-05-05 — 6/6 PASS)** | Logic | AC-HUD-12/13/14/15/16 |
| C4 ✅ | Pulse différencié source r1.1 | story-004 tween durée KILL=100ms / SECRET=150ms + magnitude 1.05 + easing TRANS_SINE + set_ignore_time_scale(true) wall-clock + invariant balance secret > kill **(Complete 2026-05-05 — 6/6 PASS — AC-HUD-36 a/b/c/d/e + OQ-HUD-5)** | Logic | AC-HUD-36 (a)(b)(c)(d)(e) |
| C5 ✅ | Anti-patterns lint static | story-005 lint statique zero match outbound refs + zero shader/gradient + layer<100 enforce + zero SFX/Input/SaveLoad + alloc hot path **(Complete 2026-05-05 — 16/16 PASS — 7 lint static + 9 runtime AC-HUD-25/26/27/28/31/32/33/34/35 ; CI job `lint-hud-anti-patterns` actif ; rule file `.claude/rules/hud-anti-patterns.md` créé ; `no-alloc-hot-paths.md` étendu scope HUD)** | Logic | AC-HUD-25/26/27/28/31/32/33/34/35 + AC-HUD-LINT-1..7 |
| C6 | Visual/Feel frame-perfect playtest | story-006 evidence frame-by-frame screencap ADVISORY — close-out cross-reference credit-008 OR subsume | Visual/Feel ADVISORY | AC-HUD-23 PLAYTEST + AC-HUD-30 MANUAL + AC-CRD-46 cross-reference |

**Pickup order recommandé** : 001 (autoload skeleton — débloque toutes les autres) → 002 (listener credits_changed SYNC — débloque AC-CRD-46 cross-reference credit-008) → 003 + 004 parallèles (visibility state machine + pulse différencié indépendants) → 005 (lints CI activated post-impl) → 006 (playtest evidence — bloquée par recrutement panel Martin OU evidence frame-by-frame screencap autonome).

## Solo Mode Notes

- **PR-EPIC skipped** (review mode `solo` — `production/review-mode.txt`)
- Aucune entrée TR-hud-* dans `tr-registry.yaml` — **R-HUD-1..15** servent de stable IDs jusqu'à rotation `/architecture-review` post-Sprint 1 (pattern précédent : Combat / Shop / Upgrade / Credit / Menu / Save-Load / Audio epics)
- Engine Risk **LOW** confirmé — pas de breaking change Godot 4.4-4.6 sur APIs `Control` + `Label` + `CanvasLayer` + `Tween.tween_property` + `set_ignore_time_scale` (stables Godot 4.0+)
- 4 OQ-HUD critiques pour MVP (OQ-HUD-1 flash secret, OQ-HUD-2 room indicator, OQ-HUD-4 autoload order ADR, OQ-HUD-5 wall-clock pulse) sont latents au moment de création epic — convention par contrat MVP (assert dans `_ready` + `set_ignore_time_scale(true)` recommandé) ; décisions OQ déférées playtest 1 ou amendement r2

## Next Step

6/6 stories créées 2026-05-04 — fichiers `story-001-autoload-skeleton-canvaslayer.md` … `story-006-visual-feel-frame-perfect-playtest.md`. Démarrage Sprint HUD :
1. `/story-readiness story-001` puis `/dev-story story-001` (autoload skeleton + CanvasLayer + Label + pattern pull boot — débloque toutes les autres)
2. Story-002 listener credits_changed SYNC (débloque AC-CRD-46 cross-reference credit-008)
3. Stories 003 + 004 parallèles (visibility state machine + pulse différencié source)
4. Story-005 (lints CI activated) + Story-006 (Visual/Feel frame-perfect playtest evidence) close-out epic

---

**Status** : Ready (Created 2026-05-04, GDD r1.1 In Design + amendement NB-CRD-6 cascade Audio r2.2, 15/15 R-HUD ✅ contrats upstream + GDD self-contained, 6 stories décomposées, débloque credit-008 Blocked).
