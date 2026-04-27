# Story 005: `_build_capsule_basis()` helper + 100-sample sphere test

> **Epic**: Player Combat System
> **Status**: Done
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/player-combat-system.md`
**Requirement**: `TR-cmb-005` (capsule basis helper cross-product direct)

**ADR Governing Implementation**: ADR-0006 (Combat Tick Model) D-7
**ADR Decision Summary**: Helper privé `_build_capsule_basis(forward) -> Basis` construit via cross product direct (PAS `Basis.looking_at * from_euler(+PI/2)` qui inverse Y 180° — bug CONV-1 r5.2 fix). Garde colinéarité UP/DOWN via `safe_up = Vector3.FORWARD` si `|dot(forward, UP)| > 0.999`. Garde déterminant quasi-singulier → fallback `Basis.IDENTITY` + `push_error`.

**Engine**: Godot 4.6 | **Risk**: LOW (mais Gap 7 prereq — pattern à documenter dans engine-reference)
**Engine Notes**: `Basis` constructor `Basis(x, y, z)` colonnes stable Godot 4.0+. `Vector3.cross` stable. `Basis.determinant()` stable.

**Control Manifest Rules (Feature layer)**:
- Required: aucune Feature-layer
- Forbidden: utiliser `Basis.looking_at(forward, up) * Basis.from_euler(Vector3(PI/2, 0, 0))` (inverse Y 180° — bug r5.2 CONV-1)
- Guardrail: helper inline ≤ 20 lignes, zéro alloc heap (Basis stack-allocated)

---

## Acceptance Criteria

*From GDD AC-CMB-08 (r6 CONV-1 FIX) + Gap 7 :*

- [ ] **AC-CMB-08 (orientation)** : pour 100 échantillons `aim_forward` sur sphère unitaire (pitch ∈ `[-PITCH_LIMIT + 0.01, PITCH_LIMIT - 0.01]`), `(_build_capsule_basis(aim) * Vector3.UP).angle_to(aim) < 0.001 rad`
- [ ] **AC-CMB-08 (position)** : pour `aim_forward = Vector3(1, 0, 0)`, `ShapeCast3D.global_transform.origin.distance_to(player.global_position + Vector3(0.9, 0, 0)) < 0.001 m`
- [ ] **Garde colinéarité** : `aim_forward = Vector3(0, 1, 0)` ou `Vector3(0, -1, 0)` (pitch = ±PITCH_LIMIT) → fallback `safe_up = Vector3.FORWARD` activé, basis encore valide non-singulière
- [ ] **Garde déterminant** : si `b.determinant() < 0.01` → return `Basis.IDENTITY`, `push_error` émis
- [ ] **Gap 7 prereq** : pattern documenté dans `docs/engine-reference/godot/modules/physics.md` section "ShapeCast3D + CapsuleShape3D basis orientation" avec snippet helper complet (owner lead-programmer pré-Sprint 1)

---

## Implementation Notes

*Derived from ADR-0006 D-7 + GDD Addendum r5.2 CONV-1 FIX:*

```gdscript
# src/gameplay/combat/combat_system.gd
func _build_capsule_basis(forward: Vector3) -> Basis:
    assert(forward.is_normalized(), "aim_forward doit etre unit vector (Camera Rule 13)")
    var safe_up: Vector3 = Vector3.UP
    if absf(forward.dot(Vector3.UP)) > 0.999:
        safe_up = Vector3.FORWARD  # fallback pitch +/- PITCH_LIMIT
    var right: Vector3 = safe_up.cross(forward).normalized()
    var local_z: Vector3 = right.cross(forward)
    var b := Basis(right, forward, local_z)  # axe Y = forward par construction
    if absf(b.determinant()) < 0.01:
        push_error("_build_capsule_basis: basis quasi-singuliere, fallback IDENTITY — forward=%v" % forward)
        return Basis.IDENTITY
    return b
```

- Helper privé (`_` préfixe) à l'intérieur de `combat_system.gd`
- Documentation Gap 7 résolue : ajouter section dans `docs/engine-reference/godot/modules/physics.md` avec snippet + 100-sample test pattern (owner lead-programmer)

---

## Out of Scope

- Story 007 : intégration helper dans positionnement ShapeCast3D
- Story 009 : utilisation dans substeps anti-tunneling

---

## QA Test Cases

- **AC-1** 100-sample sphere orientation
  - Given: `_build_capsule_basis(forward)` implémenté
  - When: 100 forward vectors sampleées sphère unitaire (yaw ∈ [0, 2π], pitch ∈ [-PITCH_LIMIT+0.01, PITCH_LIMIT-0.01])
  - Then: pour chaque sample : `(b * Vector3.UP).angle_to(forward) < 0.001 rad`
  - Edge cases: 1 seul sample `Vector3(0, 0, -1)` ne détecte PAS le bug CONV-1 (symétrie cardinale) — 100 samples load-bearing

- **AC-2** Position cardinal
  - Given: `aim_forward = Vector3(1, 0, 0)`, `player.global_position = Vector3.ZERO`
  - When: ShapeCast3D origin = `player.global_position + aim_forward * (KATANA_REACH/2)` = `Vector3(0.9, 0, 0)`
  - Then: distance < 0.001 m
  - Edge cases: aim aux 6 directions cardinales — toutes < 0.001 m

- **AC-3** Colinearity guard
  - Given: `aim_forward = Vector3(0, 1, 0)` (pitch +PITCH_LIMIT, regard zenith)
  - When: `_build_capsule_basis(forward)`
  - Then: basis non-singulière, `det > 0.01`, `(b * Vector3.UP).angle_to(forward) < 0.001`
  - Edge cases: `Vector3(0, -1, 0)` (regard nadir) — même comportement

- **AC-4** Determinant degenerate fallback
  - Given: forward construit pour produire basis quasi-singulière (forward parallèle à `safe_up.cross` impossible — cas synthétique en mock)
  - When: `_build_capsule_basis(degenerate_forward)`
  - Then: return `Basis.IDENTITY`, `push_error` émis
  - Edge cases: forward avec composantes NaN/inf — assert panic en debug (couvert story-007)

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/combat/build_capsule_basis_test.gd` — must exist and pass (100-sample loop)

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (scene skeleton), **Gap 7 résolu** (lead-programmer doc engine-reference)
- Unlocks: Story 007 (sweep position), Story 009 (anti-tunneling substeps)
