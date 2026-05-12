# Story 018: Accessibility reduce_motion + reduce_flash toggles

> **Epic**: player-movement-system
> **Status**: **Closed — WON'T FIX (résolu par ADR-0015 D-1 Option A canonical : bypass vit côté consumer — Movement n'a rien à implémenter)**
> **Layer**: Core
> **Type**: Config/Data
> **Manifest Version**: 2026-04-21

## Closed Resolution 2026-05-04

**ADR-0015 Accessibility Interface Layer Accepted 2026-05-02** ratifie exactement l'**Option A canonical** anticipée par cette story : `AccessibilityService` autoload single-source-of-truth, **propagation pull-pattern côté consumers** (Camera/Combat/Enemy/VFX/HUD lisent `reduce_motion`/`reduce_flash` et appliquent leurs multipliers localement), **outbound-zero côté Movement** (cohérent ADR-0005 D-10).

**Conclusion Movement-side** : `MovementController` n'expose **AUCUN** setter `set_reduce_motion(bool)` ni signal `accessibility_changed` ni multiplicateur interne. Movement continue d'émettre ses signaux standard (`dash_started`, `wall_run_entered(wall_normal)`, etc.) ; chaque consumer (Camera applique tilt × 0.25, FOV pulse × 0.5, shake × 0 ; VFX applique flash × 0) lit l'état accessibility via `AccessibilityService` au moment où il reçoit le signal Movement.

**Cross-references implémentation** (acceptance criteria portés par les bons epics) :
- **Camera AC-CAM-70/71/72** (Camera GDD r2 Rule 14, déjà BLOCKING) : tilt mult, FOV kick mult, shake mult — câblé via `AccessibilityService.tilt_mult/fov_kick_mult/shake_mult` au lieu d'un flag local.
- **Combat AC-CMB-19 r6 + story-022** : disable_slow_mo + slow_mo_scale_mult [1.0, 3.33] + flash_mult [0.0, 1.0] — câblé via `AccessibilityService` (story-022 Status débloqué par ADR-0015).
- **Enemy** : `DEATH_TWEEN_DURATION_MS` 150 → 400 ms variant — câblé via `AccessibilityService.enemy_death_tween_ms_override` (Tier 2+).
- **Future VFX flash mult** : reduce_flash propagé via `AccessibilityService.flash_mult` (VFX epic à venir).
- **Menu principal accessibility toggle** : Settings Menu UI Tier 2+ exposera les toggles ; MVP minimal = boolean unique `reduce_motion` accessible via le menu pause/principal selon les UX specs accessibility.

**Pas de regression feel** : ADR-0015 D-6 garantit l'**invariant defaults** par construction — toutes flags OFF → comportement bit-identical au MVP non-accessibility (test invariant cross-system requis dans story implémentation `AccessibilityService`).

**Action côté Movement epic** : aucune. Cette story est fermée sans code modifié, sans test ajouté. La traçabilité TR-mov-008 (G-4) est satisfaite via la couverture cross-system documentée par ADR-0015 (Camera + Combat + Enemy ACs portent les contrats consumer).

## Context

**GDD**: `design/gdd/player-movement-system.md` (Accessibility Options l.382-388)
**Requirements**: `TR-mov-008`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time.)*

**ADR Governing**: **ADR-0015 ABSENT** — phase Polish planned. Voir `design/accessibility-requirements.md` (tier Standard) et Gap G-4 tracé dans `docs/architecture/tr-registry.yaml`.

**Engine**: Godot 4.6 | **Risk**: LOW (toggles simples si interface définie, mais architecture propagation MVP-required selon Steam compliance WCAG)

**Control Manifest Rules**:
- Required (futur, dépend ADR-0015) : MovementController expose setter `set_reduce_motion(bool)` / `set_reduce_flash(bool)` ; toggles accessibles dès premier lancement (menu principal, pas seulement gameplay) ; defaults OFF.
- Forbidden (futur) : dépendre de `Input.mouse_mode` pendant toggle runtime.
- Guardrail : propagation cross-system sans coupling direct (pattern Observable/signal identique ADR-0004 one-way).

---

## Acceptance Criteria (tentative, à figer post-ADR-0015)

*From GDD Accessibility Options + WCAG 2.3.1 / 2.3.3 :*

- [ ] **reduce_flash OFF (default)** : fondu rouge mort ≤ 40 ms, haute saturation. Flash blanc respawn ≤ 30 ms.
- [ ] **reduce_flash ON** : fondu rouge remplacé par assombrissement progressif gris neutre non-saturé 80-120 ms, contraste ≤ 3:1. Flash blanc remplacé par fade-in neutre 100 ms. Aucun flash plein écran > 3 Hz autorisé.
- [ ] **reduce_motion OFF (default)** : tilt wall-run pleine valeur (WALL_RUN_TILT_ANGLE=0.35 rad). FOV pulse dash pleine valeur (10° kick). Shake wall-jump pleine valeur.
- [ ] **reduce_motion ON** : tilt × 0.25 (0.0875 rad), FOV pulse × 0.5 (peak ≤ 95°, kick ≤ 5°), shake × 0 (supprimé). Valeurs numériques owned par Camera GDD Rule 14.
- [ ] **Menu principal accessibility avant gameplay** : les 2 toggles exposés dès le premier lancement ; persistés dans `user://accessibility_settings.tres` (dépend ADR-0015 save/load).
- [ ] **Propagation MovementController** : setter `set_reduce_motion(bool)` mute un flag privé `_reduce_motion_multiplier: float` lu par Camera (consumer de `wall_run_entered(wall_normal)` signal Story 009). MovementController ne calcule pas le tilt (owned Camera) mais peut fournir un metadata optionnel via setter — à arbitrer ADR-0015.
- [ ] **Pas de regression feel OFF** : quand toggles à false (default), feel identique aux Stories 001-013.

---

## Implementation Notes (tentative, pending ADR-0015)

*Reste volontairement en suspens — les décisions architecturales (où vivent les flags, comment propagent, owner autoload vs per-node) sont traitées dans ADR-0015.*

- Spec implémentable existe : GDD l.382-388 + `design/accessibility-requirements.md` tier Standard.
- Dépendances probables :
  - Autoload `AccessibilityManager` (similaire `RenderingSettingsManager` autoload ADR-0003).
  - `user://accessibility_settings.tres` Resource avec migration versioning + fallback corruption (pattern identique ADR-0014 pour input/camera settings).
  - Signal one-way `accessibility_changed(setting: StringName, value: Variant)` consommé par Camera/VFX/Movement via `_ready().connect`.
- Propagation Camera : handler `_on_accessibility_changed` applique `tilt_multiplier = 0.25 if reduce_motion else 1.0` sur `WALL_RUN_TILT_ANGLE * tilt_multiplier` (owned Camera epic).
- Propagation Movement : a priori **aucune mutation directe** — Movement continue émettre `wall_run_entered(wall_normal)` standard ; Camera consumer applique multiplicateur. Pas besoin de setter dans Movement si l'arbitrage ADR-0015 confirme que le bypass vit côté consumer uniquement.
- **Option A unblock** : si on arbitre "bypass vit dans consumer", cette story ne requiert RIEN côté Movement — peut être reclassée WON'T FIX et retirée de Movement epic (déplacer vers Camera epic). À confirmer post ADR-0015.

---

## Out of Scope

- VFX flash bypass implementation → VFX epic (futur)
- Camera shake bypass + tilt multiplier implementation → Camera epic
- Audio mono option (Gap G-4 partiel, hors MVP-required toggles) → Audio epic

---

## QA Test Cases

*(Inline spec only, pending ADR-0015 arbitrage. Story peut changer significativement après décision architecturale.)*

**Tentative — reduce_flash toggle** :
- Setup : menu principal, toggle ON
- Verify : `die()` → fondu gris neutre 80-120 ms, pas rouge saturé ≤ 40 ms.
- Pass condition : screenshot + signature QA Lead.

**Tentative — reduce_motion toggle** :
- Setup : menu principal, toggle ON
- Verify : wall-run → tilt Camera ≤ 0.0875 rad ; dash → FOV peak ≤ 95° ; wall-jump → shake magnitude ≈ 0.
- Pass condition : mesures `camera3d.fov` + `camera_effects.rotation.z` + `camera3d.rotation` sur 20 samples chaque.

**Tentative — persistence cross-session** :
- Setup : toggle ON, quit, relaunch
- Verify : toggle ON au 2e lancement (depuis `user://accessibility_settings.tres`).
- Pass condition : dépend ADR-0014 save/load + ADR-0015.

---

## Test Evidence

**Story Type**: Config/Data
**Required evidence**: smoke check `production/qa/smoke-accessibility-toggles-[date].md` après unblock.

**Status**: [ ] Blocked — cannot create until ADR-0015 Accessibility Interface Layer Accepted.

---

## Dependencies

- **BLOCKED by**: ADR-0015 Accessibility Interface Layer (absent, Polish phase planned)
- Depends on (post-unblock): Stories 001-013, potentiellement Camera epic pour consumer implementation
- Unlocks: Steam release compliance WCAG 2.3.1 + 2.3.3 tier Standard

---

## Next Step

1. Option A (rapide) : `/architecture-decision` ADR léger setter `set_reduce_motion/set_reduce_flash` + signal `accessibility_changed`, unblock cette story avec implementation minimale MVP.
2. Option B (canonical) : `/architecture-decision` ADR-0015 complet avec AccessibilityManager autoload + save/load. Déverrouille TR-mov-008 + TR-cam-005 (partiel) + harmonise avec futur ADR-0014 save/load settings.
