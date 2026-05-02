# Story 004: Enable refcount multi-owner + auto-cleanup `tree_exited`

> **Epic**: input-system
> **Status**: Complete
> **Layer**: Foundation
> **Type**: Integration
> **Manifest Version**: 2026-04-21

## Context

**GDD**: `design/gdd/input-system.md`
**Requirement**: `TR-inp-005`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0004 Input API & Focus Handling D-4
**ADR Decision Summary**: Remplace `set_enabled(bool)` (race condition garantie multi-owner) par `request_disable(owner: Node)` / `release_enable_request(owner: Node)` refcount idempotent. `_enable_blockers: Dictionary<owner_id, true>` ; `_enabled` dérivé de `_enable_blockers.is_empty()`. Auto-cleanup via `owner.tree_exited.connect(..., CONNECT_ONE_SHOT)`. Quand on passe `enabled → false`, vider `_pressed_this_tick` et `_consumed_this_tick` pour éviter une press mémorisée qui traverserait la désactivation (Edge Case GDD l. 415, 420).

**Engine**: Godot 4.6 | **Risk**: MEDIUM
**Engine Notes**: `Node.get_instance_id() -> int` est stable pendant la vie du node. `tree_exited` émis avant destruction (Object encore vivant au callback). `CONNECT_ONE_SHOT` supprime la connexion après 1 firing — évite l'accumulation si un owner fait request_disable N fois.

**Control Manifest Rules (Foundation layer)**:
- Required: refcount `request_disable(owner: Node)` / `release_enable_request(owner: Node)` + auto-cleanup via `tree_exited.connect(..., CONNECT_ONE_SHOT)` + `enabled` read-only + clear flags à la transition disabled
- Forbidden: `InputManager.set_enabled(bool)` (supprimée)
- Guardrail: idempotent — même owner peut appeler N fois sans drift

---

## Acceptance Criteria

*From GDD `design/gdd/input-system.md`, scoped to this story:*

- [x] `_enable_blockers: Dictionary` membre (key: `int` owner_id, value: `true`)
- [x] `_enabled: bool` privé, dérivé via `_update_enabled_state()` quand les blockers changent
- [x] `enabled` getter public read-only (pas de setter)
- [x] `request_disable(owner: Node)` : assert owner non-null, ajoute `get_instance_id()` au dict (idempotent), connecte `owner.tree_exited` avec `CONNECT_ONE_SHOT` si pas déjà connecté
- [x] `release_enable_request(owner: Node)` : retire l'id du dict ; `push_warning` si owner n'avait pas de blocker actif ; safe si owner déjà `null` (auto-cleanup a tourné)
- [x] `_on_blocker_tree_exited(owner_id: int)` handler : retire l'id, trigger `_update_enabled_state()`
- [x] `_update_enabled_state()` : si nouveau `_enabled` différent → assigne + émet signal `enabled_changed(bool)` + si passage à `false`, clear `_pressed_this_tick[a] = false` et `_consumed_this_tick[a] = false` pour chaque action MVP
- [x] Signaux typés publics pour polling event-driven (règle 11 GDD) : `signal jump_pressed()`, `signal dash_pressed()`, `signal attack_pressed()`, `signal restart_pressed()`, `signal ui_cancel_pressed()`, `signal ui_confirm_pressed()` — émis depuis `_unhandled_input` APRÈS set du flag `_pressed_this_tick`
- [x] Override Edge Case : `ui_cancel_pressed` et `ui_confirm_pressed` sont émis **même quand `_enabled == false`** (sinon unpause impossible) ; `jump_pressed`, `dash_pressed`, etc. sont gated par `_enabled`
- [~] **AC-DS-1** : `_enabled == false`, action gameplay pressée → aucun signal typé gameplay émis, `was_pressed_this_tick(<any>) == false` ✓. Note: `get_movement_vector() == Vector2.ZERO` non testé (méthode non implémentée, à couvrir dans la story movement).
- [x] **AC-DS-2** : `_enabled == false`, `&"ui_cancel"` pressée → signal `ui_cancel_pressed` émis exactement 1×
- [x] **AC-DS-3** : `_enabled == false`, `InputEventMouseMotion` injecté → aucun `mouse_motion` émis
- [x] **AC-DS-4 / AC-CS-4** : `request_disable(A)` → press `&"jump"` (disabled, flag ghost possible) → `release_enable_request(A)` → `was_pressed_this_tick(&"jump") == false` au 1er tick enabled (flags vidés à la transition)
- [x] **AC-CS-2** : séquence 3 owners (Menu disable → Checkpoint disable → Menu release → Checkpoint release) → `_enabled` ne devient `true` qu'à la dernière release
- [x] **AC-CS-3** : owner `queue_free()` sans release → `tree_exited` émis → `_enable_blockers.size() == 0` → `_enabled == true` automatiquement
- [?] **AC-CS-5 (Advisory)** : playtest manuel pause menu 5 s + unpause → aucun saut caméra, pas d'input fantôme (evidence `production/qa/evidence/input-pause-unpause-*.md`) — DÉFÉRÉ à QA cycle

---

## Implementation Notes

*Derived from ADR-0004 D-4:*

```gdscript
signal enabled_changed(new_state: bool)
signal jump_pressed()
signal dash_pressed()
signal attack_pressed()
signal restart_pressed()
signal ui_cancel_pressed()
signal ui_confirm_pressed()

var _enable_blockers: Dictionary = {}
var _enabled: bool = true
var enabled: bool:
    get: return _enabled

func request_disable(owner: Node) -> void:
    assert(owner != null, "request_disable: owner must not be null")
    var id := owner.get_instance_id()
    if _enable_blockers.has(id):
        return
    _enable_blockers[id] = true
    # CONNECT_ONE_SHOT : après le firing, Godot supprime la connexion automatiquement
    owner.tree_exited.connect(_on_blocker_tree_exited.bind(id), CONNECT_ONE_SHOT)
    _update_enabled_state()

func release_enable_request(owner: Node) -> void:
    if owner == null:
        return
    var id := owner.get_instance_id()
    if not _enable_blockers.erase(id):
        push_warning("release_enable_request: owner %s n'avait pas de requête active" % owner)
    _update_enabled_state()

func _on_blocker_tree_exited(owner_id: int) -> void:
    if _enable_blockers.erase(owner_id):
        _update_enabled_state()

func _update_enabled_state() -> void:
    var new_state := _enable_blockers.is_empty()
    if new_state == _enabled:
        return
    _enabled = new_state
    enabled_changed.emit(_enabled)
    if not _enabled:
        for a in ACTIONS_MVP:
            _pressed_this_tick[a] = false
            _consumed_this_tick[a] = false
```

`_unhandled_input` gating (à intégrer avec story-002) :

```gdscript
# Signaux UI traversent toujours
if event.is_action_pressed(&"ui_cancel"):
    ui_cancel_pressed.emit()
if event.is_action_pressed(&"ui_confirm"):
    ui_confirm_pressed.emit()

# Actions gameplay gated
if not _enabled:
    return
for a in ACTIONS_MVP:
    if event.is_action_pressed(a):
        _pressed_this_tick[a] = true
        match a:
            &"jump": jump_pressed.emit()
            &"dash": dash_pressed.emit()
            &"attack": attack_pressed.emit()
            &"restart": restart_pressed.emit()
```

Notes clés :
- **3 owners légitimes MVP** : Menu (pause), Checkpoint (RESPAWN_DELAY), Cutscene (Tier 2). Chaque owner garde sa propre référence et appelle `release_enable_request(self)` à la sortie.
- **Idempotence** : même owner qui fait `request_disable(self)` 2× n'ajoute qu'une entrée, retire une fois → cohérent. Symétrie côté release via `Dictionary.erase()` qui retourne `false` sans erreur si la clé n'existait pas (juste un warning).
- **`ui_cancel` pass-through** (Edge Case GDD l. 415) : sinon un menu pause ouvrant `request_disable` bloque le Escape qui le ferme → deadlock. Aussi `ui_confirm` (nav menu).
- **Clear flags à la transition** (ADR-0004 D-4 + Edge Case GDD l. 420) : couvre AC-DS-4 / AC-CS-4. Scénario : un press arrive pendant disabled ; le flag est setté par `_unhandled_input` (dans `_pressed_this_tick`). Si on re-enable sans clear, au tick suivant le swap remonte `true` → ghost. Clear à la transition évite ça.
- **`Object` non-Node** (ADR-0004 Risk 4) : signature `owner: Node` **typée** pour bloquer les Resource / RefCounted qui n'ont pas `tree_exited`.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001-003 : boot + polling + mouse
- Story 005 : `application_focus_lost/gained` signaux (consumés par GameStateManager qui appellera `request_disable` sur son propre Node — testé par AC-MC-4 là)
- Checkpoint & Respawn System (hors epic) : owner `request_disable(self)` à l'entrée RESPAWN_DELAY

---

## QA Test Cases

- **AC-DS-1** : gameplay action bloquée pendant disabled
  - Given : `request_disable(A)` appliqué
  - When : `Input.parse_input_event(InputEventAction{&"jump", pressed=true})`, `physics_frame`
  - Then : `jump_pressed` non émis ; `was_pressed_this_tick(&"jump") == false` ; `get_movement_vector() == Vector2.ZERO`

- **AC-DS-2** : ui_cancel traverse
  - Given : `request_disable(A)` appliqué
  - When : `Input.parse_input_event(InputEventAction{&"ui_cancel", pressed=true})`
  - Then : `ui_cancel_pressed` émis 1×

- **AC-DS-3** : mouse_motion bloqué
  - Given : `request_disable(A)` appliqué
  - When : `Input.parse_input_event(InputEventMouseMotion{relative=Vector2(10,0)})`
  - Then : `mouse_motion` non émis

- **AC-DS-4 / AC-CS-4** : no ghost post-transition
  - Given : `request_disable(A)`, `_pressed_this_tick[&"jump"] = true` injecté pendant disabled
  - When : `release_enable_request(A)`, `physics_frame`
  - Then : `was_pressed_this_tick(&"jump") == false` (flags vidés)
  - Edge cases : press au tick de transition → assert reste `false`

- **AC-CS-2** : refcount multi-owner
  - Given : 3 Node mocks Menu, Checkpoint, Cutscene
  - When : séquence (Menu.request_disable → Checkpoint.request_disable → Menu.release → Checkpoint.release)
  - Then : `enabled` states observés : `false, false, false, true`
  - Edge cases : release dans l'ordre inverse → même résultat (ordre indifférent)

- **AC-CS-3** : auto-cleanup tree_exited
  - Given : Mock Node appelle `request_disable(self)`, puis `queue_free()` sans release
  - When : `await owner.tree_exited` (ou avancer jusqu'à destruction)
  - Then : `InputManager._enable_blockers.size() == 0` ET `enabled == true`
  - Edge cases : 2 owners, un free, l'autre reste → `enabled` reste `false`

- **AC-CS-5 (Advisory manual)** : pause/unpause playtest
  - Setup : scène MVP, ouvrir pause menu (Escape), attendre 5 s, unpause
  - Verify : caméra n'a pas sauté ; aucun jump/dash fantôme déclenché
  - Pass condition : vidéo ou screenshot séquence, lead sign-off dans `production/qa/evidence/input-pause-unpause-{date}.md`

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- `tests/integration/input/enable_refcount_test.gd` — AC-DS-1..4, AC-CS-2, AC-CS-3 (ADR-0004 VC-5, VC-6)
- `production/qa/evidence/input-pause-unpause-{date}.md` — AC-CS-5 advisory

**Status**: [x] Implemented — `tests/integration/input/enable_refcount_test.gd` (8 tests, 330 lignes)

---

## Dependencies

- Depends on: Story 001 (bootstrap), Story 002 (polling hot path), Story 003 (mouse signal, à gater)
- Unlocks: Story 005 (GameStateManager consumera `application_focus_lost` via son propre `request_disable`)

---

## Completion Notes

**Completed**: 2026-04-23
**Criteria**: 14/15 passing ; 1 partiel (AC-DS-1 : get_movement_vector skippé, méthode future story) ; 1 advisory différé (AC-CS-5 playtest manuel)
**Verdict**: COMPLETE WITH NOTES
**Files modifiés**:
- `src/core/input_manager.gd` (169 → 268 lignes) — signal `enabled_changed(bool)` + 6 signaux typés gameplay/UI ; `_enable_blockers: Dictionary` + getter public read-only `enabled` ; `request_disable(owner)` idempotent + auto-cleanup `tree_exited.connect(..., CONNECT_ONE_SHOT)` ; `release_enable_request` null-safe + `push_warning` desynchro ; `_update_enabled_state` avec clear flags à la transition disabled ; `_unhandled_input` réécrit pour émettre ui_cancel/ui_confirm AVANT gate `_enabled`

**Files créés**:
- `tests/integration/input/enable_refcount_test.gd` (330 lignes, 8 fonctions GdUnit4)

**Deviations (ADVISORY)**:
- Nommage : TR-inp-005 registry utilise `request_enable(owner)` mais ADR-0004 + story + code utilisent `release_enable_request(owner)` (plus symétrique). Non bloquant — envisager update du texte de tr-registry.yaml pour refléter l'API implémentée.
- AC-DS-1 partiel : `get_movement_vector() == Vector2.ZERO` non testable (méthode future). Documenté ligne 67 du test.
- AC-CS-5 : playtest manuel pause/unpause différé au QA cycle (evidence à produire : `production/qa/evidence/input-pause-unpause-{date}.md`).

**Test Evidence**: Integration — `tests/integration/input/enable_refcount_test.gd` ; advisory playtest différé.
**Code Review**: Skipped (mode solo).
**Untested criteria**: AC-CS-5 (advisory playtest) — recommander d'ajouter evidence au prochain QA cycle.
