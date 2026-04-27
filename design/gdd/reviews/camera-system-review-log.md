# Camera System — Review Log

## Review — 2026-04-21 — Verdict: MAJOR REVISION NEEDED

**Scope signal**: M (Medium)
**Specialists consulted**: game-designer, systems-designer, gameplay-programmer, godot-specialist, performance-analyst, ux-designer, qa-lead, creative-director (senior synthesis)
**Blocking items identified**: 7 | Recommended: 15 | Nice-to-have: 6
**Prior verdict resolved**: N/A — first review

### Summary

Premier design-review du GDD Camera System (auparavant "In Design", auto mode + solo review). Le GDD a de solides fondamentaux (Player Fantasy "caméra invisible", anti-références précises, ownership tilt 20° défendue playtest) mais souffrait de trous d'exécution cross-doc et algèbre :

- **Conflits cross-doc** : scene tree (Camera3D direct vs CameraArm intermédiaire Movement), signal name (`wall_jump_performed` vs canonique Movement `wall_jumped`), propriété `player.wall_side` consommée inexistante côté Movement, physics rate 120 Hz AC contredit ADR-0001 (60 Hz).
- **Erreur algébrique Formula 5 `aim_forward`** : la manipulation Basis (`Basis(UP, -roll) * basis_globale`) n'annule pas un roll local Z — hitbox katana orientée incorrectement pendant wall-run tilt, mécanique cœur cassée.
- **Conflit tilt 12° (Movement) vs 20° (Camera)** non résolu en aval : Movement GDD lignes 319 + 334 gardent "12°", Camera clame source de vérité sans patch appliqué.
- **Accessibility reduce_motion relégué Tier 3** alors que 15-25% public FPS est motion-sensitive — floor MVP, pas perk.
- **Respawn hybride sans précédent** (yaw préservé, pitch reset=0) — ni Ghostrunner ni Mirror's Edge.
- **Absent** : classification ACs par type, atomisation AC respawn (3 checks dans 1), evidence paths, AC focus-loss, AC scene reload, clamp yaw_delta magnitude, cap shake_offset.

Martin a tranché les 4 décisions CD via widget multi-tab :
1. **Physics rate 60 Hz canon** (ADR-0001 référence)
2. **Scene tree CameraArm intermédiaire** — creative-director recommande, adopté via ADR-0002 (upgradé 3-tier par process concurrent pendant la session : `CharacterBody3D → CameraArm → CameraEffects → Camera3D`)
3. **Reduce_motion MVP obligatoire** (toggle binaire unique, 3 multiplicateurs)
4. **Préserver pitch ET yaw au respawn** (Ghostrunner approach)

Plus :
- **Signal canon** : `wall_jumped(wall_normal: Vector3, launch_velocity: Vector3)` (Movement existant, Camera aligne)
- **`wall_side` dérivé par Camera** depuis `player.wall_normal` (pas de pollution API Movement)
- **Crosshair découplage** : reporté au HUD GDD futur

### Revisions applied (r1 — in this session)

| Item | Statut | Location |
|---|---|---|
| Header status → "Revised post r1 — pending re-review fresh session" | ✅ Applied | camera-system.md header |
| Scene tree 3-tier (CameraArm + CameraEffects) | ✅ Applied (concurrent process) | camera-system.md Rule 1 |
| Rule 2 yaw : clamp `MAX_ROT_PER_FRAME`, ownership Camera écrit / Movement lit seule | ✅ Applied | Rule 2 |
| Rule 3 pitch : clamp `MAX_ROT_PER_FRAME` | ✅ Applied | Rule 3 |
| Rule 4 tilt : target `camera_effects.rotation.z` (pas camera.rotation.z) | ✅ Applied (concurrent process) | Rule 4 |
| Rule 7 signal : `wall_jumped(wall_normal, launch_velocity)` + `sign_with_fallback` edge dot=0 | ✅ Applied | Rule 7 |
| Rule 9 respawn : préserve pitch ET yaw (Ghostrunner), reset tilt/FOV/shake uniquement | ✅ Applied | Rule 9 |
| Rule 13 aim_forward : forme close trigonométrique (archive Basis manipulation) | ✅ Applied (concurrent process) | Rule 13 |
| Formula 4 shake : `limit_length(MAX_SHAKE_MAGNITUDE)` cap obligatoire post-injection, assignation `camera3d.rotation = shake_offset` | ✅ Applied | Formula 4 |
| Formula 5 aim_forward : closed-form trigonométrique, remplace version r1 algébriquement incorrecte | ✅ Applied | Formula 5 |
| Tuning Knobs : `MAX_ROT_PER_FRAME`, `MAX_SHAKE_MAGNITUDE`, `reduce_motion` (MVP toggle) | ✅ Applied | Tuning Knobs |
| AC Performance : "120 Hz" → "60 Hz physique (ref: ADR-0001)" | ✅ Applied (concurrent process) | AC Performance |
| Open Questions : refondu, marque résolus post-r1 (reduce_motion MVP, pitch respawn, aim_forward, clamps) | ✅ Applied | Open Questions |
| ADR-0002 Camera Scene Tree 3-tier Proposed | ✅ Created (upgradé 2-tier → 3-tier par process concurrent) | `docs/architecture/adr-0002-camera-scene-tree-cameraarm.md` |

### Revisions deferred (to follow-up session — not blocking for fresh re-review of core design)

| Item | Raison defer | Action |
|---|---|---|
| Patches Movement GDD Visual/Audio (lignes 319 + 334 — tilt 12° → référence `WALL_RUN_TILT_ANGLE` Camera-owned) | Movement GDD modifié par process concurrent pendant cette session (Edit failures répétés) | `/consistency-check` ou session séparée |
| AC classification complète (Logic/Integration/Visual-Feel/Perf) + evidence paths + atomisation AC respawn + AC focus-loss + AC scene reload | Concurrent process actif sur Camera — rewrite massif bloqué | Session revision suivante sur standard Input GDD r2 |
| AC "moyenne" → p50+p99 avec scène test spec | Idem | Session revision suivante |
| Rule 10 reduce_motion dédié (actuellement Tuning Knobs + Open Question résolue) | Workaround : toggle documenté côté Tuning Knobs suffisant pour re-review core | Session revision suivante |
| Instrumentation ring buffer latence Camera (AC-PERF-2 non mesurable sans) | Sprint 1 impl | Pattern Input GDD à reproduire |
| Cleanup signals `_exit_tree` pattern documenté | Rule 15 à ajouter | Session revision suivante |
| FOV slider MVP UI Requirements + Tuning Knobs integration | Mentionné Open Questions résolu, Menu GDD owns spec | Menu GDD |

### Specialist findings summary

**game-designer** : Contradiction "raw" vs 3 lerps (reformuler PF), bouillie multi-effets (gouvernance), reset pitch hybride (Ghostrunner approach), lisibilité mort (freeze vers source).

**systems-designer** : Formula 5 algébriquement fausse (forme close proposée, AC vérifiable), flick extrême dégénéré (clamp), shake accumulation non bornée (cap), lerp framerate-dep (variance calculée 30/60/144 fps), AC 120 Hz non testable.

**gameplay-programmer** : CameraArm vs direct child (ADR), yaw ownership race, `wall_side` inexistant, signal signature fausse, désynchro `_process`/`_physics_process`, CanvasLayer parent, cleanup signals, ACs non testables headless.

**godot-specialist** : `Camera3D.fov` D3D12 Windows à vérifier, Forward+ cluster rebuild, CameraArm pattern idiomatique, AudioListener convention, Wayland mouse delta, CanvasLayer survie reload, signal disconnect, AccessKit 4.5 ne couvre pas reduce_motion.

**performance-analyst** : AC "120 Hz" ambigu, "moyenne" anti-pattern QA, scène test non spec, Forward+ cluster rebuild à profiler, latence non-instrumentable sans ring buffer, budget global absent, ColorRect fillrate respawn, calibrage debug/release.

**ux-designer** : Reduce_motion floor MVP (15-25% public), reset pitch flou, lisibilité mort "glitch vs mort", sensitivity mapping exponentiel ownership, FOV slider MVP attendu, mouse smoothing transparence, crosshair vs aim_forward (CRITIQUE), menu pause tilté, z-order CanvasLayer.

**qa-lead** : Zero classification par type (régression standard Input r2), AC katana "parallèle" ambigu + Formula 5 suspecte, AC respawn 3 checks dans 1 (anti-pattern), idempotence "non observable", ACs manquants focus-loss/scene reload, "moyenne" vs p99, evidence paths absents, contradiction 200ms/250ms tilt.

**creative-director senior** : Verdict MAJOR REVISION NEEDED. "Bons fondamentaux mais trous d'exécution cross-doc + algèbre". Scope M. Top 5 actions (~2h15 spec). Tranché 4 désaccords : 60 Hz, CameraArm, reduce_motion MVP, préserver pitch+yaw.

### Re-review required

**Fresh session obligatoire** (ce contexte biaisé par 7 specialists + synthesis + edits itératifs + concurrent process modifications).

Commandes :
```
/clear
/design-review design/gdd/camera-system.md
```

Prior revision history : r1 (cette entrée). Next entry : r2 post fresh re-review.

---

## Review — 2026-04-21 — Verdict: NEEDS REVISION (r2)

**Scope signal**: M (Medium)
**Mode**: `lean` — single-session delta analysis (re-review après r1 exhaustif, solo mode configuré)
**Specialists consulted**: Aucun spawn r2 — analyse structurelle directe + cross-doc bidirectionnel (Movement GDD, Input GDD, ADR-0002, ADR-0005 Proposed)
**Blocking items identified**: 5 | Recommended: 8 | Nice-to-have: 6
**Prior verdict resolved**: Partiellement — r1 patches structurels tiennent (signal canon `wall_jumped`, scene-tree 3-tier, `RESPAWN_DELAY=50ms`, `mouse_sensitivity` range, decisions creative-director), mais items "deferred" r1 sont redevenus blockers.

### Summary r2

Les 4 décisions creative-director r1 (60 Hz ADR-0001, scene-tree 3-tier ADR-0002, `reduce_motion` MVP, préserver pitch+yaw respawn) tiennent. Cross-doc bidirectionnalité confirmée pour Input GDD et ADR-0005 signatures. **Mais** :

- **B-1 BLOCKING** : `player.wall_side` consommé comme propriété Movement alors que Movement expose seulement `wall_normal: Vector3`. r1 review log mentionnait "wall_side dérivé par Camera" mais patch non appliqué.
- **B-2 BLOCKING** : Movement GDD lignes 70, 371, 373, 386, 420, 421 gardaient tilt=12° stale + nœud `CameraArm.rotation.z` wrong (canon = `CameraEffects.rotation.z`). Cross-doc drift r1 non résorbé.
- **B-3 BLOCKING** (nouvelle régression r2) : Formulas 1-3 utilisent `camera.rotation.x/z` et `camera.fov` sans préfixe — nomenclature pre-3-tier, ambiguë et implémentationellement incorrecte post-ADR-0002.
- **B-4 BLOCKING** : ACs sans classification `[Type — BLOCKING/ADVISORY] [Owner]`, sans evidence paths, AC respawn mélange 3 checks. "Deferred to follow-up session" r1 devenu blocker.
- **B-5 BLOCKING** (nouvelle régression r2) : State table Respawning row disait "Reset pitch/roll/FOV/shake" contredisant Rule 9 "pitch ET yaw préservés" et Open Question résolue.

### Revisions applied (r2 — in this session)

| Item | Statut | Location |
|---|---|---|
| Header status → "Revised post design-review r2 — pending fresh re-review" | ✅ Applied | camera-system.md header |
| B-1 — Rule 4 préambule : dérivation canonique `wall_side = sign((-wall_normal).dot(basis.x))` | ✅ Applied | Rule 4 |
| B-1 — Formula 2 table "wall_side" → "Dérivé Camera depuis `player.wall_normal` (cf. Rule 4)" | ✅ Applied | Formula 2 table |
| B-1 — Dependencies tables (inline + big) : retrait `player.wall_side`, ajout note dérivation | ✅ Applied | Dependencies |
| B-2 — Movement GDD 5 patches : Camera System row + Visual/Audio + reduce_motion + Impact Moments | ✅ Applied | player-movement-system.md L70, L371–373, L386, L420–421 |
| B-3 — Formulas 1-3 : `camera_arm.rotation.x`, `camera_effects.rotation.z`, `camera3d.fov` | ✅ Applied | Formulas section |
| B-3 — Edge Cases + HUD row : nomenclature alignée 3-tier | ✅ Applied | Edge Cases + HUD Dependencies row |
| B-4 — Section AC refondue : AC-CAM-01..92, `[Type — BLOCKING/ADVISORY] [Owner]`, evidence paths Visual/Feel, respawn atomisé 40/41/42/43, ACs focus-loss (64) et scene reload (63) ajoutés | ✅ Applied | Acceptance Criteria |
| B-5 — State table Respawning : "Reset roll/FOV/shake ; pitch ET yaw préservés (Ghostrunner, cf. Rule 9)" | ✅ Applied | States and Transitions |
| B-5 — Open Question redondante ligne 423 supprimée | ✅ Applied | Open Questions |
| R-1 — Rule 15 `is_mouse_captured()` gate + AC-CAM-62 | ✅ Applied | Rule 15 + AC |
| R-2 — Rule 14 `reduce_motion` gate multiplicateurs + AC-CAM-70/71/72 | ✅ Applied | Rule 14 + AC |
| R-3 — ADR-0005 Movement Signals ref dans Dependencies (inline + big) | ✅ Applied | Dependencies + Cross-References |
| R-4 — Signal `wall_jumped(wall_normal, launch_velocity)` canon partout (stale `wall_jump_performed` retiré) | ✅ Applied | Dependencies + Cross-References + AC |
| R-5 — AC Performance refondu p50/p99 + scène test spec + evidence path | ✅ Applied | AC-CAM-80/81 |
| R-6 — Rule 16 `_exit_tree()` cleanup + AC-CAM-63 | ✅ Applied | Rule 16 + AC |
| R-8 — Formula 2 note stabilité framerate | ✅ Applied | Formula 2 |

### Revisions deferred (to Sprint 1 or downstream GDDs)

| Item | Raison defer | Action |
|---|---|---|
| Instrumentation ring buffer impl | Impl time, spec AC-CAM-80/81 suffisante pour re-review | Sprint 1 story Camera |
| FOV slider dans Settings | Owned par Menu GDD | Menu GDD à écrire |
| Camera3D.fov stabilité Windows DX12 + Linux Vulkan | Test runtime, pas design | Sprint 1 story Camera |
| Head-bob / weapon sway post-MVP | Playtest-dependent | Playtest MVP |
| Crosshair vs aim_forward roll-corrigé wall-run | Owned par HUD GDD | HUD GDD à écrire |
| Gamepad right-stick look | Tier 2 post-MVP | Tier 2 |

### Scope signal

**M (Medium)** — 1 système, 5 formules, 10+ dépendances bidirectionnelles, 2 ADRs gouvernants (0002 Accepted path, 0005 Proposed). Pas de nouveau ADR requis r2.

### Re-review required

**Fresh session recommandée avant passage "Approved"** (Martin a opté pour "passer au système suivant" C — Camera reste "In Review (r2 revised)" dans systems-index). La re-review r3 sera courte (delta check) sauf si les patches downstream (`/design-system player-combat-system`) révèlent de nouveaux conflits.

Commandes quand re-review souhaitée :
```
/clear
/design-review design/gdd/camera-system.md --depth lean
```

Prior revision history : r1 (2026-04-21, MAJOR REVISION NEEDED, 7 BLOCKING + 15 RECOMMENDED) → r2 (2026-04-21, NEEDS REVISION, 5 BLOCKING + 8 RECOMMENDED résolus dans cette session). Next entry : r3 post fresh re-review.
