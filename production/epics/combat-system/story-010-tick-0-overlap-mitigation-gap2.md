# Story 010: Tick-0 overlap mitigation + Gap 2 prelim test

> **Epic**: Player Combat System
> **Status**: **Complete 2026-05-04** (Gap 2 résolu Variante B empirique — mitigation `_tick0_intersect_shape_overlap()` REDONDANTE — 2/2 régression tests PASS — AUCUN code production ajouté)
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-04-23

> **UNBLOCKED + COMPLETE 2026-05-04** : Gap 2 résolu via `tests/empirical/shapecast_overlap_origin_test.gd`. Verdict empirique Godot 4.6.2-stable + JoltPhysics3D : **Variante B** — `ShapeCast3D.force_shapecast_update()` détecte nativement les overlaps à l'origine (`get_collision_count() == 1`, collider=CharacterBody3D). Cross-check `PhysicsDirectSpaceState3D.intersect_shape()` retourne aussi 1 hit (convergent). Documentation : `docs/engine-reference/godot/modules/physics.md` section "ShapeCast3D overlap at origin Godot 4.6 + Jolt empirical test".
>
> **Implication scope** : la mitigation `_tick0_intersect_shape_overlap()` proposée en Implementation Notes est **redondante**. AC-CMB-47 satisfait par le comportement natif Combat tick 0 (story-009 substeps base, substep 0 origin overlap détecté). **Aucun code production ajouté** — la story se ferme sur un test régression empirique sans modifier `src/gameplay/combat/combat_system.gd`.
>
> **Test régression livré** : `tests/integration/combat/tick_0_overlap_mitigation_regression_test.gd` (2/2 PASS, 147 ms) couvre AC-CMB-47 : (1) MockEnemy à `_prev + aim × 0.5` détecté par `_collect_swing_hits()` natif, (2) `_resolve_kills()` appelle `die()` 1× + populate `_hit_this_swing`. Si rouge futur → re-runner empirical + adopter Variante A.

---

## Completion Notes

1. **Empirical prelim** : `tests/empirical/shapecast_overlap_origin_test.gd` (~95 lignes, SceneTree subclass headless safe) — Variante B confirmée Godot 4.6.2-stable + JoltPhysics3D. Cross-check `intersect_shape()` retourne aussi 1 hit (convergent). Pattern réutilisable pour futures investigations physics empiriques (extends SceneTree + `_initialize()` + `_physics_process()` return-bool quit).
2. **Aucun code production ajouté** : la story se réduit à un test régression. Pas de `_tick0_intersect_shape_overlap()` dans `combat_system.gd` (redondant). Économie : ~25 lignes + 1 PhysicsShapeQueryParameters3D cached non-créé.
3. **Test régression** : `tests/integration/combat/tick_0_overlap_mitigation_regression_test.gd` (~135 lignes, 2 tests, 147 ms PASS). Couvre AC-CMB-47 (overlap origin native detection + die() contract résolu).
4. **Documentation engine-ref** : section "ShapeCast3D overlap at origin Godot 4.6 + Jolt empirical test" ajoutée à `docs/engine-reference/godot/modules/physics.md` — verdict + méthode + résultat brut + 3 pitfalls observés (global_transform pré-tree error, GDScript `%.2f`/`%05b` format edge cases, ≥2 physics frames d'attente AABB stabilization).
5. **Pitfall pré-tree global_transform** : `enemy.global_position = ...` AVANT `add_child()` produit ERROR `is_inside_tree()` car Node3D global transforms requièrent le tree. Solution : utiliser `enemy.position = ...` (local), ou setter global APRÈS add_child. Documenté inline.
6. **Pitfall GDScript format** : `%05b` (binary padding) et certains `%.Nf` peuvent émettre "String formatting error: unsupported format character" — préférer `str(val)` explicite. Documenté inline.
7. **Test signal scope** : MockEnemy n'émet PAS `enemy_killed` (signal réservé Grunt réel testé en suite Enemy — cf. `mock_enemy.gd` l.9-10). Combat émet `swing_ended` + `multi_kill` mais pas `enemy_killed`. Test simplifié sur die() count + `_hit_this_swing` populé — couvre AC-CMB-47 côté Combat.
8. **Default aim** : `_collect_swing_hits()` sans Camera utilise `Vector3.FORWARD = (0, 0, -1)` — test exploite ce defaut, pas besoin d'injecter mock CameraSystem.
9. **Sentinelle régression future** : si Jolt change le comportement (Variante A retournée), test rouge → re-runner `tests/empirical/shapecast_overlap_origin_test.gd` + adopter `_tick0_intersect_shape_overlap()` mitigation.
10. **Zéro régression** : suite combat (`tests/unit/combat` + `tests/integration/combat`) PASSE pour tous les fichiers canoniques. Les fails observés sont exclusivement sur les dupes Mac Finder `xxx 2.gd` (workspace cleanup item E pending autorisation Martin, non lié à cette story).

## Context

**GDD**: `design/gdd/player-combat-system.md`
**Requirement**: AC-CMB-47-Prelim + AC-CMB-47 (Edge Case overlap à l'origine)

**ADR Governing Implementation**: ADR-0006 (Combat Tick Model)
**ADR Decision Summary**: si Variante A confirmée (Godot 4.6 ShapeCast ne détecte pas overlaps initiaux), Combat précède chaque `force_shapecast_update()` du tick 0 d'un `_tick0_intersect_shape_overlap()` utilisant `PhysicsShapeQueryParameters3D` + `intersect_shape`. Si Variante B (overlap détecté natively), la mitigation est sécurité redondante / supprimable.

**Engine**: Godot 4.6 + Jolt | **Risk**: HIGH (Gap 2 + Gap 8 conjoints — comportement empirique post-cutoff)
**Engine Notes**: `intersect_shape` API stable Godot 4.0+. Ce qui change avec Jolt = Sweep behavior at origin overlap. À documenter dans `docs/engine-reference/godot/modules/physics.md`.

**Control Manifest Rules (Feature layer)**:
- Required: utiliser `CollisionLayers.build_mask([2])` pour PhysicsQueryParameters3D si helper Sprint 0 existant (ADR-0008 D-5)
- Forbidden: bitmask literal `query.collision_mask = 0b00010` direct (lint CI ADR-0008 D-6)
- Guardrail: `_tick0_intersect_shape_overlap()` ne doit PAS allouer plus que nécessaire (1 PhysicsShapeQueryParameters3D `_ready()` cached, réutilisé)

---

## Acceptance Criteria

*From GDD AC-CMB-47-Prelim + AC-CMB-47 + Gap 2 :*

- [ ] **AC-CMB-47-Prelim** (lead-programmer pré-Sprint 1) : scène minimale Godot 4.6 + Jolt avec ShapeCast3D + MockEnemy en overlap à origine — résultat `get_collision_count()` documenté dans `docs/engine-reference/godot/modules/physics.md` section "ShapeCast3D overlap at origin Godot 4.6 + Jolt empirical test"
- [ ] **Variante A confirmée** : si `get_collision_count() == 0` → `_tick0_intersect_shape_overlap()` load-bearing, AC-CMB-47 vérifie que désactiver la mitigation cause l'échec (collider raté)
- [ ] **Variante B confirmée** : si `get_collision_count() == 1` (MockEnemy détecté) → mitigation redondante, AC-CMB-47 vérifie que les 2 sources produisent même kill (union dedup O(1) par `get_instance_id()`)
- [ ] Si Variante A : pendant tick 0 du swing, `_tick0_intersect_shape_overlap()` exécuté AVANT `force_shapecast_update()`, hits unionisés dans le même Dictionary dedup (story-009 augmenté)
- [ ] Si Variante B : `_tick0_intersect_shape_overlap()` peut être supprimé OU laissé comme sécurité (décision lead-programmer)
- [ ] **AC-CMB-47** : MockEnemy à `_prev_position + aim_forward × 0.5` (overlap origine) → `die()` appelé, `enemy_killed` émis, `_hit_this_swing` contient son instance_id

---

## Implementation Notes

*Derived from ADR-0006 + GDD Edge Case hitbox 1 :*

**AC-CMB-47-Prelim (lead-programmer pré-Sprint 1)** :
```gdscript
# Scène minimale tests/empirical/shapecast_overlap_origin_test.gd
func _ready() -> void:
    var sc := ShapeCast3D.new()
    sc.shape = CapsuleShape3D.new()
    sc.shape.radius = 0.45
    sc.shape.height = 1.8
    sc.target_position = Vector3(0, 0, -0.5)
    sc.collision_mask = 0b00010  # ou via API helper
    var enemy := CharacterBody3D.new()
    var collision := CollisionShape3D.new()
    collision.shape = SphereShape3D.new()
    (collision.shape as SphereShape3D).radius = 0.35
    enemy.add_child(collision)
    enemy.global_position = Vector3(0, 0, -0.3)  # overlap à origin
    add_child(enemy)
    add_child(sc)
    sc.force_shapecast_update()
    print("Variante: ", "A (intersect_shape requis)" if sc.get_collision_count() == 0 else "B (force_shapecast suffit)")
```

**Si Variante A** : ajouter dans Combat
```gdscript
func _tick0_intersect_shape_overlap(hits: Dictionary, basis: Basis, sweep_origin: Vector3) -> void:
    var space_state := get_world_3d().direct_space_state
    var query := PhysicsShapeQueryParameters3D.new()
    query.shape = $ShapeCast3D.shape
    query.transform = Transform3D(basis, sweep_origin)
    query.collision_mask = $ShapeCast3D.collision_mask
    var results := space_state.intersect_shape(query, MAX_KILLS_PER_SWING + 4)
    for r in results:
        var c = r.collider
        if c != null:
            hits[c.get_instance_id()] = c
```

Appelé au tick 0 du swing (i.e. quand `_active_tick == 0` au début de `_collect_swing_hits()`) avant la boucle substeps story-009.

---

## Out of Scope

- Story 011 : résolution kills sur la liste retournée (cette story produit la liste tick 0)
- Story 009 : substeps anti-tunneling tick 1+ (cette story s'occupe seulement du tick 0 cas overlap)

---

## QA Test Cases

- **AC-1** Prelim empirical exists
  - Given: `docs/engine-reference/godot/modules/physics.md`
  - When: section "ShapeCast3D overlap at origin Godot 4.6 + Jolt" lue
  - Then: contient verdict (Variante A ou B), godot version, jolt version, commit SHA
  - Edge cases: si verdict absent — story BLOCKED

- **AC-2** Variante A — disable mitigation causes failure
  - Given: Variante A confirmée, MockEnemy à `_prev_position + aim*0.5` (overlap origin)
  - When: Combat tick 0 avec `_tick0_intersect_shape_overlap()` désactivé manuellement
  - Then: AC fail (collider raté, `enemy_killed` non émis)
  - Edge cases: réactiver mitigation → AC pass

- **AC-3** Variante B — both sources produce same kill
  - Given: Variante B confirmée, MockEnemy à overlap origin
  - When: Combat tick 0 avec mitigation activée + force_shapecast_update natif
  - Then: 1 seul `enemy_killed` émis (dedup instance_id), `_hit_this_swing` contient son ID
  - Edge cases: mitigation désactivée — toujours 1 kill (force_shapecast suffit)

- **AC-4** AC-CMB-47 main scenario
  - Given: swing tick 0, MockEnemy à `_prev_position + aim_forward × 0.5`
  - When: `_collect_swing_hits()` exécuté
  - Then: `MockEnemy.die()` appelé 1 fois, `enemy_killed` émis, `_hit_this_swing` contient instance_id
  - Edge cases: MockEnemy plus loin (1.5 m) — couvert par story-009 substeps

---

## Test Evidence

**Story Type**: Logic
**Required evidence** :
- `tests/empirical/shapecast_overlap_origin_test.gd` — **AC-1 / AC-CMB-47-Prelim ✅ Created 2026-05-04** (verdict Variante B empirique, runner SceneTree headless safe). Re-run via `godot --headless --script tests/empirical/shapecast_overlap_origin_test.gd`.
- `tests/unit/combat/tick_0_overlap_mitigation_test.gd` — AC-3 régression test, à créer dans Sprint Combat close-out (vérifie comportement natif sans code mitigation).
- Documentation engine-ref : `docs/engine-reference/godot/modules/physics.md` section "ShapeCast3D overlap at origin Godot 4.6 + Jolt empirical test" — verdict + méthode + résultat brut + pitfalls observés.

**Status** : [x] Empirical Prelim DONE (Variante B) ; [ ] Unit régression test AC-3 à écrire (~30 min, hors-blocker)

---

## Dependencies

- Depends on: Story 006 (collision layers), Story 008 (`_prev_position`), Story 009 (substeps base), ~~Gap 2 résolu (AC-CMB-47-Prelim — lead-programmer)~~ ✅ Résolu 2026-05-04 empiriquement (Variante B).
- Unlocks: Story 011 (kill resolution complète tous ticks).
