# Story 009: Anti-tunneling N=3 substeps + Jolt margin empirical

> **Epic**: Player Combat System
> **Status**: Complete
> **Completed**: 2026-05-02 (auto-mode, fix is_equal_approx vector tolerance + tests PASS)
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/player-combat-system.md`
**Requirement**: `TR-cmb-004` (ShapeCast3D sweep anti-tunneling N_SUBSTEPS=3 constant + Jolt CCD complément + Gap 8 Jolt margin empirique)

**ADR Governing Implementation**: ADR-0006 (Combat Tick Model) + ADR-0001 (Physics Rate 60 Hz)
**ADR Decision Summary**: `N_SUBSTEPS = 3` constant par tick actif (pas branching dynamique sur velocity). Interpolation linéaire entre `_prev_position` et `player.global_position` ; chaque substep exécute `force_shapecast_update()` pour balayer un segment 1/3 de la trajectoire. Jolt CCD complément (config Player `safe_margin`). Gap 8 prereq : lead-programmer empirique sur `ShapeCast3D.margin` Jolt vs GodotPhysics3D, doc dans `engine-reference/godot/modules/physics.md`.

**Engine**: Godot 4.6 | **Risk**: MEDIUM
**Engine Notes**: Jolt physics default Godot 4.6 (post-cutoff). `ShapeCast3D.margin` behavior pourrait différer de GodotPhysics3D — Gap 8 requiert validation empirique avant Sprint 1 Combat (lead-programmer owner).

**Control Manifest Rules (Feature layer)**:
- Required: `N_SUBSTEPS = 3` constant compile-time (pas variable runtime)
- Forbidden: branching dynamique sur velocity pour calculer N (`if velocity > X: N = ...` interdit — vérifié grep AC-CMB-14)
- Guardrail: `gap_max = V * delta / N < 0.7 m` (= 2 × r_enemy_min) garantit pas de tunneling à V_max=30 m/s

---

## Acceptance Criteria

*From GDD AC-CMB-14 + Gap 8 :*

- [x] **AC-CMB-14** : `delta = 1/60` ; pour `velocity ∈ {0.0, 10.0, 30.0}` m/s : `N_SUBSTEPS == 3` constant (pas de branching dynamique), `gap_max = V * (1/60) / 3 < 0.7 m` vérifié pour chaque V
- [x] **AC-CMB-14 grep statique** : `grep -nE 'TUNNELING_THRESHOLD' src/gameplay/combat/` — zéro match dans condition de branching N (constante peut exister mais pas utilisée pour gate N)
- [x] **Gap 8 prereq** : `docs/engine-reference/godot/modules/physics.md` documente `ShapeCast3D.margin` behavior Jolt 4.6 (test empirique exécuté par lead-programmer pré-Sprint 1)
- [x] Pendant `Swinging`, chaque `_physics_process` tick exécute 3 substeps `force_shapecast_update()` avec `target_position` interpolée linéairement entre `_prev_position` et `player.global_position` (substeps i ∈ [0, 1, 2] : `from = lerp(_prev, current, i/3)`, `to = lerp(_prev, current, (i+1)/3)`)
- [x] Colliders détectés dans les 3 substeps unionisés et dedupliqués via `instance_id` (prep pour story-011 hit resolution)

---

## Implementation Notes

*Derived from ADR-0006 D-3 + GDD Rule 7 r2 + Formula 3 :*

- Constante : `const N_SUBSTEPS: int = 3`
- Logique substeps dans `_physics_process` quand `_state == SWINGING` :
  ```gdscript
  func _collect_swing_hits() -> Array[int]:
      var hits: Dictionary = {}  # instance_id → collider for dedup
      var aim := camera_system.aim_forward
      var basis := _build_capsule_basis(aim)
      for i in N_SUBSTEPS:
          var t0 := float(i) / N_SUBSTEPS
          var t1 := float(i + 1) / N_SUBSTEPS
          var from_pos := _prev_position.lerp(player.global_position, t0) + aim * (KATANA_REACH / 2.0)
          var to_pos := _prev_position.lerp(player.global_position, t1) + aim * (KATANA_REACH / 2.0)
          $ShapeCast3D.global_transform = Transform3D(basis, from_pos)
          $ShapeCast3D.target_position = to_pos - from_pos
          $ShapeCast3D.force_shapecast_update()
          for j in $ShapeCast3D.get_collision_count():
              var c := $ShapeCast3D.get_collider(j)
              if c != null:
                  hits[c.get_instance_id()] = c
      return hits.keys()
  ```
- **Forbidden** : ne JAMAIS écrire `if player.velocity.length() > X: var n = ...` — N_SUBSTEPS reste constant compile-time
- Gap 8 : si bench Jolt révèle `margin` ghost-hits → ajuster `ShapeCast3D.margin` ou collision_shape `margin` selon recommandation Jolt 4.6 doc

---

## Out of Scope

- Story 010 : tick-0 overlap initial mitigation (intersect_shape supplémentaire)
- Story 011/012 : kill resolution sur les hits collectés (cette story livre la liste, pas le die() call)

---

## QA Test Cases

- **AC-1** N=3 constant under varying velocity
  - Given: `delta = 1/60`, mocked velocities `{0.0, 10.0, 30.0}` m/s
  - When: substeps loop exécuté
  - Then: pour chaque V : 3 substeps exécutés (`get_collision_count()` appelé 3× par tick), `gap_max = V * (1/60) / 3 < 0.7 m`
  - Edge cases: V = 1000 m/s synthétique → toujours 3 substeps (pas branching)

- **AC-2** No dynamic branching grep
  - Given: source `combat_system.gd`
  - When: `grep -nE '(TUNNELING_THRESHOLD|N_SUBSTEPS\s*=\s*\d+\s*if|velocity.*N_SUBSTEPS)' src/gameplay/combat/`
  - Then: zéro match dans contexte branching (const declaration `const N_SUBSTEPS = 3` autorisée)
  - Edge cases: TUNNELING_THRESHOLD existe en doc/comment OK ; en code branching FAIL

- **AC-3** Substep position interpolation
  - Given: `_prev_position = Vector3(0, 0, 0)`, `player.global_position = Vector3(0, 0, -0.5)` (déplacement 0.5 m), `aim = Vector3(0, 0, -1)`
  - When: substeps i=0,1,2 calculés
  - Then: substep 0 from=(0,0,0)+(0,0,-0.9), to=(0,0,-0.166)+(0,0,-0.9) ; substep 1 from→to suivants ; segment final atteint `player.global_position + aim*reach/2`
  - Edge cases: `_prev_position == player.global_position` (immobile) — 3 substeps balayent même position (overlap 100%)

- **AC-4** Dedup hits via instance_id
  - Given: 1 MockEnemy intersecté par 2 substeps consécutifs
  - When: `_collect_swing_hits()` retourne
  - Then: hits.size() == 1 (instance_id key dédup)
  - Edge cases: 3 ennemis dans 1 substep + 1 même ennemi dans substep suivant → 3 IDs uniques

- **AC-5** Gap 8 Jolt margin doc exists
  - Given: `docs/engine-reference/godot/modules/physics.md`
  - When: section "ShapeCast3D.margin Jolt 4.6" lue
  - Then: contient résultat empirique (godot version, jolt version, commit SHA, valeur margin par défaut, anomalies si présentes)
  - Edge cases: si bench non exécuté → AC fail, story BLOCKED Gap 8

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/combat/anti_tunneling_substeps_test.gd` — must exist and pass

**Status**: ✅ Created — 8/8 PASS (`reports/report_264` 2026-05-02 — fix `is_equal_approx(vec, Vector3.ONE * tol)` GdUnit4 vector signature).

---

## Dependencies

- Depends on: Story 008 (`_prev_position`), Story 005 (basis helper), Story 007 (aim guards), **Gap 8 résolu** (lead-programmer empirique Jolt margin)
- Unlocks: Story 010 (tick-0 overlap), Story 011 (kill resolution)
