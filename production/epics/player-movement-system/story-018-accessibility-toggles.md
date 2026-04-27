# Story 018: Accessibility reduce_motion + reduce_flash toggles

> **Epic**: player-movement-system
> **Status**: **Blocked**
> **Layer**: Core
> **Type**: Config/Data
> **Manifest Version**: 2026-04-21

## Blocked Reason

**BLOCKED: ADR-0015 Accessibility Interface Layer absent.**

La propagation cross-system des toggles `reduce_flash` (WCAG 2.3.1) + `reduce_motion` (WCAG 2.3.3) requiert un ADR formel d'architecture (Gap **G-4** identifié `/architecture-review` 2026-04-21, planned phase **Polish**). L'inline spec existe dans `design/gdd/player-movement-system.md` l.382-388 et `design/accessibility-requirements.md` tier **Standard** committed 2026-04-21, mais l'interface technique (`AccessibilityManager` autoload, setter `set_reduce_motion(bool)` sur MovementController, propagation Camera shake bypass + Movement tilt bypass + VFX flash bypass) n'est pas arbitrée.

**Unblock options** :
- **Option A (rapide)** : écrire un ADR léger formalisant le setter `set_reduce_motion(bool)` sur MovementController + signal `accessibility_changed` avant la story wall-run/dash qui touche le tilt bypass. Effort ~1h. Déverrouille propagation minimale MVP.
- **Option B (canonical)** : écrire ADR-0015 Accessibility Interface Layer complet (AccessibilityManager autoload + `user://accessibility_settings.tres` save/load + propagation 3 systèmes). Effort ~3h. Déverrouille G-4 entier + TR-mov-008 + TR-cam-005 (partiel).

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
