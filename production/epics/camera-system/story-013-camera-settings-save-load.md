# Story 013: camera_settings.tres save/load lifecycle (persist + migration + corruption fallback)

> **Epic**: Camera System
> **Status**: Blocked
> **Layer**: Presentation
> **Type**: Config/Data
> **Manifest Version**: 2026-04-21

## BLOCKED

**Raison** : Gouvernée par **ADR-0014 Save/Load Settings Infrastructure** qui n'existe pas encore.

Cet ADR couvrira **de pair** TR-cam-006 (`camera_settings.tres` : mouse_sensitivity, mouse_y_inverted, fov_user_offset) et TR-inp-009 (`input_settings.tres`). Noté comme **G-2a post-MVP polish** dans l'epic Camera (Known Gaps) et dans le TR registry (`covered_by: []`).

**Résolution requise avant de démarrer** : exécuter `/architecture-decision` pour créer ADR-0014 Save/Load Settings Infrastructure (phase Polish). Sans cet ADR, toute implémentation embarquerait une architecture de persistance non validée (format resource, versioning, migration, fallback corruption — 4 décisions structurelles).

Lorsque ADR-0014 atteint `Accepted` :
1. Retirer le bloc BLOCKED ci-dessus
2. Mettre à jour le frontmatter header `Status: Ready`
3. Ajouter les sections ADR Governing Implementation + Implementation Notes + QA Test Cases
4. Mettre à jour EPIC.md (table stories : statut Ready) + `production/epics/index.md`

---

## Context (provisoire)

**GDD**: `design/gdd/camera-system.md`
**Requirement**: `TR-cam-006`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: **ADR-0014 Save/Load Settings Infrastructure** (ABSENT — à créer phase Polish)

**Engine**: Godot 4.6 | **Risk**: MEDIUM (post-cutoff `duplicate_deep()` 4.5+ pour nested resources à envisager dans l'ADR)

---

## Acceptance Criteria (provisoires — à figer dans ADR-0014)

*Issues directement de GDD Tuning Knobs + Dependencies Save/Load System :*

- [ ] **AC-CAM-SAVE-1** : `GIVEN` `mouse_sensitivity = 0.0040`, `mouse_y_inverted = true`, `fov_user_offset = +5°`, `WHEN` game save triggered, `THEN` `user://camera_settings.tres` contient les 3 valeurs sérialisées.
- [ ] **AC-CAM-SAVE-2** : `GIVEN` `user://camera_settings.tres` version 1, `WHEN` load avec nouveau format version 2 (champ ajouté), `THEN` migration effectue remplissage du champ nouveau avec default, pas de crash.
- [ ] **AC-CAM-SAVE-3** : `GIVEN` `user://camera_settings.tres` corrompu (bytes random, JSON invalide, etc.), `WHEN` load au boot, `THEN` fallback valeurs default (`mouse_sensitivity = 0.0022`, `mouse_y_inverted = false`, `fov_user_offset = 0°`) + `push_warning("[camera] settings file corrupted, using defaults")` + réécriture fichier propre au prochain save.
- [ ] **AC-CAM-SAVE-4** : `GIVEN` first launch (no settings file), `WHEN` boot, `THEN` defaults appliqués sans warning + création fichier au premier save event.

---

## Out of Scope

- Input settings persistence (`input_settings.tres` TR-inp-009) — story séparée mais ADR-0014 commune.
- Menu UI de toggle/slider pour édition settings — owned par Menu/Settings epic.

---

## Dependencies

- **BLOCKED BY** : ADR-0014 (absent). Pas d'ADR, pas d'implémentation.
- Depends on (une fois unblocked) : Story 002 (mouse_sensitivity consommé via InputManager), Story 006 (`fov_user_offset` appliqué sur `BASE_FOV`), toute l'infrastructure Menu/Settings.
- Unlocks (une fois implémenté) : Settings menu persistence cohérente ; Pillar UX « settings respectés entre sessions ».

---

## Notes pour le lecteur

Cette story reste dans l'epic pour traçabilité du TR-cam-006 ; elle ne sera pas travaillée avant création ADR-0014 (phase Polish). Aucun test evidence path n'est défini tant que l'architecture de persistance n'est pas figée.
