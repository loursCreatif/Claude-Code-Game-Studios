# Architecture Review Report — Single-GDD Camera

**Date** : 2026-04-21
**Mode** : `/architecture-review single-gdd camera` (fresh session, post-arbitrage 3-tier ADR-0002)
**Engine** : Godot 4.6 (Forward+ / Jolt)
**GDDs Reviewed** : 1 (`design/gdd/camera-system.md`)
**ADRs Reviewed** : 1 primaire (ADR-0002) + 3 connexes (ADR-0001, ADR-0003, ADR-0004)
**Verdict** : **PASS** (sur périmètre ADR-0002)

---

## Contexte

Re-review fresh-session obligatoire suite à la réécriture substantive d'ADR-0002 en session précédente (arbitrage caméra 3-tier `CharacterBody3D → CameraArm → CameraEffects → Camera3D → AudioListener3D` remplaçant le design initial 2-tier). Le session-state de 2026-04-21 notait explicitement : « ADR-0002 reste Proposed (substantively réécrit → fresh re-review obligatoire) ».

Cette review valide que :
1. ADR-0002 couvre toutes les TRs caméra MVP.
2. ADR-0002 ne contredit aucun ADR coexistant (ADR-0001 autorité, ADR-0003 rendering, ADR-0004 input).
3. Les APIs utilisées sont compatibles Godot 4.6.

---

## Traceability Matrix

| TR-ID | Requirement | ADR Coverage | Status |
|---|---|---|---|
| TR-cam-001 | Ownership par étage : yaw=player, pitch=camera_arm, tilt=camera_effects, fov+shake=camera3d | ADR-0002 §Decision + Implementation Guidelines | ✅ Covered |
| TR-cam-002 | `aim_forward` forme close trigonométrique ignore tilt | ADR-0002 §Key Interfaces + VC-4 | ✅ Covered |
| TR-cam-003 | Logique caméra en `_process` (pas `_physics_process`) | ADR-0001 (autorité) + ADR-0003 (60+ fps render) | ✅ Covered |
| TR-cam-004 | Tilt 95% cible ≤ 200 ms | — (tuning target, hors périmètre architecture) | ✅ N/A |
| TR-cam-005 | Budget caméra ≤ 0.5 ms/frame p99 | ADR-0002 §Performance Implications + VC-6 | ✅ Covered |
| TR-cam-006 | Lifecycle save/load `camera_settings.tres` | — | ⚠️ GAP (G-2, Feature tier non-MVP-blocker) |
| TR-mov-004 | Hiérarchie 3-étages (amont Camera) | ADR-0002 | ✅ Covered |

**Totaux** : 5 ✅ / 1 ⚠️ non-blocker / 0 ❌.

---

## Cross-ADR Conflict Detection

| Cross-check | Résultat |
|---|---|
| ADR-0002 ↔ ADR-0001 : autorité `_process` pour caméra cosmétique | ✅ Cohérent — ADR-0001 liste explicitement Camera yaw/pitch en `_process` cosmetic |
| ADR-0002 ↔ ADR-0003 : rendu Camera3D + fov dynamique en Forward+ | ✅ Cohérent — ADR-0003 ligne 241 atteste compatibilité |
| ADR-0002 ↔ ADR-0004 : consommation `mouse_motion` signal + lecture `InputManager.enabled` | ✅ Cohérent — Camera ne modifie JAMAIS l'état Input (contrat unidirectionnel) |

**Aucun conflit détecté.**

**Dependency ordering** : ADR-0002 `Depends On: None` est correct côté strict, mais l'ADR s'appuie implicitement sur l'autorité `_process` posée par ADR-0001. Relation documentée dans `Related` (§228). Non bloquant.

---

## Engine Compatibility Audit (Godot 4.6)

| Check | Résultat |
|---|---|
| `Node3D` + `Camera3D` + `AudioListener3D` API stability 4.0→4.6 | ✅ Stable (aucun changement breaking-changes.md) |
| Rotation Euler YXZ convention | ✅ Inchangée |
| 3D interpolation rearchitected (4.5) | ✅ API unchanged, internals only — `physics_interpolation_mode = OFF` Player root (ADR-0001) neutralise |
| `Camera3D.fov` assignation frame-per-frame | ⚠️ MEDIUM (validé macOS Metal prototype uniquement ; Windows DX12 / Linux Vulkan à re-valider — Open Question line 425 Camera GDD) |
| `AudioListener3D` auto-current sans `make_current()` | VC-5 couvre |

**Knowledge Risk global ADR-0002** : LOW — justifié.
**Post-Cutoff APIs Used** : aucune (tout Godot 4.0-compatible).
**Deprecated API References** : zéro.

---

## GDD Revision Flags (ARCHITECTURE → DESIGN)

4 incohérences Camera GDD détectées. **Toutes GDD-side**, aucune n'invalide ADR-0002. À traiter via `/consistency-check` avant la première story Camera Sprint 1.

| # | Domaine | Constat | Action |
|---|---|---|---|
| **F-1** | Signal name | Camera GDD lignes 91, 213, 341, 373, 400 utilisent `wall_jump_performed(wall_normal)` ; Rule 7 (line 55) et Movement GDD (line 88) utilisent `wall_jumped(wall_normal, launch_velocity)`. Incohérence interne. | `wall_jump_performed` → `wall_jumped` (5 occ), param `launch_velocity` ignoré via `_` |
| **F-2** | Stale node refs | Formules 1-4 (lignes 105-149), Edge Cases 197-198, Interactions 216, ACs 355-383 utilisent `camera.rotation.*` / `camera.fov` au lieu des noeuds dédiés post-ADR-0002. Risque : VC-2/VC-3 grep échoueraient si code copié littéralement. | Migration `camera.rotation.x` → `camera_arm.rotation.x`, `camera.rotation.z` → `camera_effects.rotation.z`, `camera.fov` → `camera3d.fov` |
| **F-3** | Open Question stale | Question #17 (line 423) prescrit « reset pitch à 0 » contredisant Question #3 (line 408) résolue « Préserver pitch ET yaw ». | Supprimer Question #17 |
| **F-4** | Timing tilt discordant | Rule 4 line 49 + TR-cam-004 disent « 95% ≤ 200 ms ». Formula 2 math (ln(20)/12 ≈ 250 ms) + AC line 361 + Animation Feel line 293 disent « 250 ms ». | Option A : corriger Rule 4 + TR-cam-004 → 250 ms. Option B : augmenter `TILT_LERP_SPEED` à 15. **Reco : Option A** (math correcte, valeur k=12 playtest-validée) |

---

## Verdict Detail

**PASS** sur le périmètre ADR-0002 :
- Toutes les TRs caméra MVP critiques sont couvertes.
- Cohérence cross-ADR confirmée (ADR-0001, ADR-0003, ADR-0004).
- Engine-compatibilité Godot 4.6 propre (Knowledge Risk LOW justifié).
- VC-1 à VC-6 testables.
- Alternatives rigoureusement documentées.
- Pattern CameraArm est l'idiom Godot standard FPS.

**CONCERNS hors périmètre ADR** :
- 4 flags F-1..F-4 côté GDD → `/consistency-check` session séparée.
- TR-cam-006 (save/load camera_settings) reste GAP G-2 registry (Feature tier, hors MVP-blocker).

---

## Actions

1. **ADR-0002 Proposed → Accepted** : transitionné en cette session. ✅
2. **Registry TR** : aucun append (TR-cam-001..006 déjà enregistrées par review précédente).
3. **`/consistency-check` session séparée** à lancer : F-1 (signal name 5 occ), F-2 (stale `camera.rotation.*` refs ~15 occ), F-3 (Q#17 retrait), F-4 (200→250 ms Rule 4 + TR-cam-004) + patches Movement déjà deferred (lignes 70, 319+334, 371, 386, 438).
4. **État des ADRs** : ADR-0001 Accepted / ADR-0002 Accepted (cette session) / ADR-0003 Accepted / ADR-0004 reste Proposed (out of scope ; re-review fresh session dédiée requise).

---

## Handoff

- **Prochain ADR à créer** : ADR-0005 Movement Signals Architecture (résout gap G-1, ~1 h).
- **Gate guidance** : ADR-0004 fresh re-review avant gate `/gate-check pre-production`.
- **Re-run `/architecture-review`** après traitement de F-1..F-4 et après ADR-0004 accepté.

---

*Auteur : `/architecture-review single-gdd camera`, 2026-04-21*
*Mode : fresh session (post-`/clear`), auto-mode actif, solo review*
