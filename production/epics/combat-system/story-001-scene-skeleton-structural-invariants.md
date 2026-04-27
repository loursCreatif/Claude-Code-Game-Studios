# Story 001: Scene skeleton & structural invariants

> **Epic**: Player Combat System
> **Status**: Complete
> **Layer**: Feature
> **Type**: Logic
> **Estimate**: 3 hours (S) — structural setup, 2 asserts, 1 scene file, 1 unit test
> **Performance**: no performance impact expected — structural invariant setup only
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/player-combat-system.md`
**Requirement**: `TR-cmb-001`, `TR-cmb-002`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0006 (Combat Tick Model)
**ADR Decision Summary**: D-1 — CombatSystem est direct child du Player CharacterBody3D (DFS preorder garantit Player → Combat). D-2 — `physics_process_priority == 0` invariant structurel asserté à `_ready()`.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: DFS scene-tree ordering est stable Godot 4.0+. Comportement `physics_process_priority` documenté Node3D.

**Control Manifest Rules (Feature layer)**:
- Required: aucune règle Feature-layer required (couche encore vide)
- Forbidden: never introduire un 2e Player node sans refactor EventBus
- Guardrail: à définir post-MVP — respecter budget global 16.6 ms/frame

---

## Acceptance Criteria

*From GDD `design/gdd/player-combat-system.md`, scoped to this story (AC-CMB-49 Partie B + structural):*

- [ ] CombatSystem instancié comme direct child du Player CharacterBody3D
- [ ] À `_ready()` : `assert(get_parent() == player_node, "Combat must be direct child of Player")`
- [ ] À `_ready()` : `assert(physics_process_priority == 0, "Combat priority must remain default 0")`
- [ ] **AC-CMB-49 Partie A** (Rule 15) : grep statique confirme aucune connexion à layer 0b00100 (EnemyHitbox), aucune propriété `is_invulnerable` ou `invuln_timer`, aucune logique "pendant Swinging Player ne peut pas mourir"
- [ ] Scene file `combat_system.tscn` créé avec node racine `CombatSystem` (Node3D), child `ShapeCast3D` (placeholder, configuré story-006)

---

## Implementation Notes

*Derived from ADR-0006 D-1 / D-2 + Implementation Guidelines:*

- Créer `src/gameplay/combat/combat_system.gd` avec `class_name CombatSystem extends Node3D`
- Créer `src/gameplay/combat/combat_system.tscn` avec ShapeCast3D enfant (config dans story-006)
- Dans `_ready()`, assert structural invariants en debug build :
  ```gdscript
  assert(get_parent() is CharacterBody3D, "Combat parent must be CharacterBody3D (Player)")
  assert(physics_process_priority == 0, "Combat physics_process_priority must be default 0 (DFS preorder Rule 17)")
  ```
- **Forbidden** : ne jamais exposer `is_invulnerable: bool` ou équivalent — Rule 15 one-shot symétrie. Combat n'est pas responsable de la détection de mort joueur.
- Le node Player attache CombatSystem comme child direct dans `Player.tscn` (modification ownership Player scene — coordination Movement story-001).

---

## Out of Scope

- Story 002 : state machine (Idle/Swinging/Dead) + cooldown timer
- Story 006 : ShapeCast3D collision layers config
- Story 014 : `_death_pending` mutual kill end-of-tick handling

---

## QA Test Cases

- **AC-1** Scene skeleton parent invariant
  - Given: scène test instancie Player avec CombatSystem comme child direct
  - When: Player `_ready()` puis CombatSystem `_ready()`
  - Then: `combat.get_parent() == player_node`, aucun assert panic
  - Edge cases: re-parenting runtime (interdit) ; CombatSystem comme grandchild (assert panic)

- **AC-2** Priority invariant
  - Given: CombatSystem instancié
  - When: `_ready()` exécuté
  - Then: `combat.physics_process_priority == 0`
  - Edge cases: muter `physics_process_priority = 1` puis re-ready → assert panic

- **AC-3** Rule 15 grep
  - Given: source `src/gameplay/combat/combat_system.gd` complet
  - When: `grep -nE 'is_invulnerable|invuln_timer|connect.*0b00100' src/gameplay/combat/`
  - Then: zéro match
  - Edge cases: commentaires mentionnant "invulnerability" autorisés (Rule 15 doc) si lignes commentées

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/combat/scene_skeleton_invariants_test.gd` — must exist and pass

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: None (premier story Combat)
- Unlocks: Story 002 (state machine), Story 006 (ShapeCast3D config), toutes stories Combat ultérieures

---

## Completion Notes

**Completed**: 2026-04-27
**Criteria**: 5/5 passing (AC-1 happy + 2 edges, AC-2 happy + negative, AC-3 grep, AC-5 scene smoke — 100% test coverage)
**Deviations**:
- ADVISORY — `_ready()` configure `shape_cast.margin = 0.0` + `collision_mask/layer = CollisionLayers.build_mask([])` (zéro). Mandate ADR-0006 status preamble (Gap 8 résolu 2026-04-23) + defensive zero pour prévenir faux positifs runtime avant story-006 (lift recommandé par godot-specialist code review). Conforme ADR-0008 D-3 (helper API, pas de bitmask littéral).
**Test Evidence**: Logic — `tests/unit/combat/scene_skeleton_invariants_test.gd` (7 fonctions GdUnit4)
**Code Review**: Complete — verdict APPROVED WITH SUGGESTIONS (gdscript-specialist + godot-specialist + qa-tester en parallèle), 4 fixes appliqués (defensive ShapeCast3D zero, AC-5 scene smoke test ajouté, typo `charcterbody3d` corrigé, strip-comment AC-3 amélioré)
**Files**:
- Created: `src/gameplay/combat/combat_system.gd`, `src/gameplay/combat/combat_system.tscn`, `tests/unit/combat/scene_skeleton_invariants_test.gd`
- Modified: `src/gameplay/player/Player.tscn` (load_steps 2→3, instance CombatSystem comme direct child)
