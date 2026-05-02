# Camera Respawn Fade + Flash — Evidence Document (AC-CAM-42 + AC-CAM-FLASH-1)

> **Story** : `production/epics/camera-system/story-009-respawn-fade-flash-visual.md`
> **Type** : Visual/Feel — ADVISORY (ne bloque pas /story-done)
> **Status** : SCAFFOLD — sign-off Martin Sprint 1 (etage_01.tscn requis)
> **Date** : 2026-05-02

---

## Reference

GDD `design/gdd/camera-system.md` Rule 9 + Visual/Audio Requirements — Mirror's Edge inspiration.
Pillar 3 « UNE SECONDE CHANCE » : respawn total ≤ 400 ms perçu.

## Implementation Summary

`src/gameplay/camera/camera_system.gd` étend la séquence `_on_respawned` :

```
Phase 0 (post-died)  : overlay rouge Color(0.4, 0, 0, 0.6) plein écran, visible
Phase 1 (respawned + 0 ms)   : snap couleur → Color(1, 1, 1, 0.9) (flash blanc)
Phase 2 (flash + 50 ms hold) : intervalle, couleur flash blanc maintenue
Phase 3 (fade 100 ms)        : interpolation vers Color(0.4, 0, 0, 0.0) (rouge transparent)
Phase 4 (callback final)     : _overlay.visible = false (clear monde normal)
```

**Timing théorique** : 50 ms flash + 100 ms fade = **150 ms overlay-side**.
Avec RESPAWN_DELAY=50 ms côté Movement, gross total = **200 ms** — bien sous Pillar 3 cible 400 ms.

**Tween Godot 4** : `create_tween().tween_property + tween_interval + tween_callback`. API stable ≤ 4.3, pas de post-cutoff. Edge case died→respawned→died < 200 ms : kill du tween précédent dans `_on_died` ET dans `_animate_respawn_overlay` (double-safety).

---

## Automated Evidence (objective, headless smoke test)

**Test file** : `tests/integration/camera/story_009_respawn_fade_flash_test.gd`
**Run** : `reports/report_147` — 5/5 PASSED 410 ms 0 errors 0 failures.

| Test | AC couvert | Status |
|------|-----------|--------|
| `test_ac_cam_42_respawn_animation_starts_with_white_flash` | AC-CAM-42 Phase 1 | PASSED — overlay.color == Color(1,1,1,0.9) post-respawned |
| `test_ac_cam_42_respawn_animation_ends_with_overlay_hidden` | AC-CAM-42 Phase 4 | PASSED — overlay.visible == false post-tween.finished |
| `test_ac_cam_42_tween_is_valid_during_animation` | AC-CAM-42 séquence | PASSED — _respawn_tween.is_valid() pendant animation |
| `test_ac_cam_flash_2_total_animation_duration_under_pillar3_budget` | **AC-CAM-FLASH-2** | PASSED — durée mesurée ≤ 400 ms (cible 150 ms ± 50 ms) |
| `test_died_during_respawn_animation_kills_tween_and_resets_overlay` | edge case rapide | PASSED — second died kill tween + reset overlay |

**Verdict objective** : 4/4 AC-structurels + 1 edge case PASSED. Couvre AC-CAM-42 Phase 1 + Phase 4 + structure tween + AC-CAM-FLASH-2 timing.

---

## Manual Evidence — ⚠️ MARTIN REQUIRED Sprint 1

Les ACs Visual/Feel suivants nécessitent capture vidéo OU 5 screenshots espacés ~50 ms — **bloqué par `scenes/levels/etage_01.tscn` empty au MVP**. À déclencher quand etage_01 est chargeable + WorldBoundsVolume Sprint 1 livré.

### Setup (Martin) Sprint 1
1. Build dev OR export Player.tscn dans etage_01.tscn (avec WorldBoundsVolume sous le sol).
2. Run game, déclencher die intentionnel (chute via WorldBoundsVolume OR `MovementController.die()` debug binding).
3. Capture vidéo 60 fps OU 5 screenshots espacés ~50 ms (t=0, t=60, t=110, t=200, t=250 ms post-died).

### Expected Frames

| Frame | Timestamp post-died | Expected overlay state | Visual |
|-------|---------------------|------------------------|--------|
| 0 | t = 0 ms | Color(0.4, 0, 0, 0.6) plein écran | rouge sombre opaque ⚠️ TODO screenshot |
| 1 | t ≈ 60 ms (mid-red, respawn pas encore) | Color(0.4, 0, 0, 0.6) identique | rouge sombre ⚠️ TODO screenshot |
| 2 | t ≈ 110 ms (juste après respawned + flash snap) | Color(1, 1, 1, 0.9) | blanc presque opaque — flash visible ⚠️ TODO screenshot |
| 3 | t ≈ 200 ms (mid-fade) | Color(0.4, 0, 0, ~0.3) | rouge semi-transparent ⚠️ TODO screenshot |
| 4 | t ≈ 250 ms (clear) | overlay invisible | monde normal ⚠️ TODO screenshot |

### Pass Conditions (Martin sign-off)

- [ ] **AC-CAM-42 Phase Distinct** : 3 phases perceptuellement distinctes (rouge → flash blanc → clear). Pas de confusion entre les phases.
- [ ] **AC-CAM-FLASH-1** : pas de jump cut brutal entre flash et clear — transition continue (interpolation fluide).
- [ ] **AC-CAM-FLASH-2 perceptuel** : totalité observable < 300 ms (cible 200 ms gross, budget 400 ms Pillar 3).

### Sign-Off Required

- [ ] **creative-director** Pillar 3 « UNE SECONDE CHANCE » — séquence respawn lisible, pas désorientante.
- [ ] **lead QA** validation 5 frames captures conformes au tableau ci-dessus.

---

## Engine + ADR Compliance Checklist

- [x] ADR-0002 ownership : overlay owned par Camera (CanvasLayer enfant CameraArm), VFX System ne duplique pas — verified `src/gameplay/camera/camera_system.gd:_setup_overlay()`
- [x] Manifest 2026-04-23 Presentation layer — animation en Tween async (équivalent `_process` cosmetic) NOT `_physics_process` ✓
- [x] Tween Godot 4 API stable (`create_tween`, `tween_property`, `tween_interval`, `tween_callback`) — pas de post-cutoff API
- [x] Pillar 3 budget ≤ 400 ms — théorique 150 ms + 50 ms RESPAWN_DELAY = 200 ms gross, smoke test confirme < 400 ms
- [x] Edge case died→respawned→died rapide : kill tween + reset overlay testé (story_009 test #5)

---

## Tech Debt / Follow-ups

- **Sprint 1** : Martin capture 5 frames + sign-off creative-director + QA lead (etage_01 + WorldBoundsVolume requis).
- **Future** : si reduce_motion (story 010) nécessite désactiver le flash blanc (épilepsie warning), gate via `if InputManager.reduce_motion: skip Phase 1`. Hors scope story-009.
- Pattern test camera tech debt (`%CameraEffects` sans scene owner) reste flagué pour refacto post-MVP (commun stories 005-009).
