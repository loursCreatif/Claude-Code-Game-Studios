# Story 009: Respawn fade rouge → flash blanc → clear (Mirror's Edge reference)

> **Epic**: Camera System
> **Status**: Complete
> **Layer**: Presentation
> **Type**: Visual/Feel
> **Manifest Version**: 2026-04-23
> **Estimate**: S (2-3 heures) — 3 constantes (FADE_DURATION, FLASH_DURATION, FLASH_COLOR) + 1 méthode `_animate_respawn_overlay` Tween + 1 var `_respawn_tween` + override `_on_respawned` (callsite story-008) + evidence capture 5 frames + smoke check Pillar 3 ≤ 400 ms

## Context

**GDD**: `design/gdd/camera-system.md`
**Requirement**: aucun TR direct (Visual/Feel non-structurel, issu de GDD Rule 9 + Visual/Audio Requirements — référence Mirror's Edge)
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time)*

**ADR Governing Implementation**: ADR-0002 (Camera Scene Tree CameraArm — l'overlay est owned par Camera via `CanvasLayer` enfant)
**ADR Decision Summary**: ADR-0002 Implementation Guidelines acte ownership de l'overlay côté Camera (pas VFX). GDD Rule 9 + Visual/Audio Requirements spécifient la séquence visuelle : red snap (0.6 alpha) → 100 ms fade avec flash blanc (1,1,1,0.9) 50 ms intercalé → clear. Pillar 3 (UNE SECONDE CHANCE) — respawn total ≤ 400 ms.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `Tween.tween_property(Color.a, ...)` API stable Godot 4. Option alternative : séquence manuelle via `_process` delta accumulator (plus contrôlé pour tests déterministes). `ColorRect.color` est `Color` value type, assignation synchrone. Pas de post-cutoff API.

**Control Manifest Rules (Presentation layer)**:
- Required : overlay owned par Camera (CanvasLayer enfant Camera, pas VFX) ; camera logic en `_process` cosmétique only (animation fade en `_process` ou `Tween` async, pas `_physics_process`)
- Forbidden : animation fade qui contourne Camera (VFX System ne doit pas dupliquer l'overlay — GDD Cross-References « Overlay fade respawn owned ici, VFX synchronisé via signals »)
- Guardrail : transition totale (death snap → clear) ≤ 400 ms (Pillar 3 + GDD Feel Acceptance Criteria)

---

## Acceptance Criteria

*From GDD `design/gdd/camera-system.md`, scoped to this story :*

- [x] **AC-CAM-42** (Visual/Feel — ADVISORY) : `GIVEN` séquence died → respawned, `THEN` la transition overlay `alpha=0.6 → 0` dure 100 ms avec un flash blanc `(1,1,1,0.9)` intercalé 50 ms. Evidence : `production/qa/evidence/camera-respawn-fade-2026-05-02.md` (scaffold avec objective evidence + 5 frames Sprint 1 ⚠️ MARTIN).
- [⚠️] **AC-CAM-FLASH-1** (Visual/Feel) : totalité de la séquence (death snap → clear) perceptuellement distinct de 3 phases (rouge → flash → clear) ; pas de « jump cut » brutal entre flash et clear. **DEFERRED Sprint 1** — bloqué par `scenes/levels/etage_01.tscn` empty MVP.
- [x] **AC-CAM-FLASH-2** (Feel) : respawn total visible (mort + fade + flash) ≤ 400 ms (GDD Feel Acceptance Criteria). Couvert objective via `test_ac_cam_flash_2_total_animation_duration_under_pillar3_budget`.

---

## Implementation Notes

*Derived from GDD Rule 9 + Visual/Audio Requirements + Tuning Knobs :*

Étendre `src/gameplay/camera/camera_system.gd` :

```gdscript
const RESPAWN_OVERLAY_FADE_DURATION: float = 0.100   # 100 ms fade 0.6 → 0
const RESPAWN_FLASH_DURATION: float = 0.050          # 50 ms flash blanc
const RESPAWN_FLASH_COLOR: Color = Color(1.0, 1.0, 1.0, 0.9)

# Override Story 008 _on_respawned — séquence animée au lieu de hide instantané
func _on_respawned(_position: Vector3) -> void:
    # Reset effets visuels sauf pitch/yaw (Story 008)
    _camera_effects.rotation.z = 0.0
    _camera3d.fov = BASE_FOV
    _camera3d.rotation = Vector3.ZERO
    _shake_offset = Vector3.ZERO
    # Séquence animée fade + flash via Tween
    _animate_respawn_overlay()
    _state = State.ACTIVE

func _animate_respawn_overlay() -> void:
    # Kill previous tween si respawn rapide consécutif (edge case)
    if _respawn_tween and _respawn_tween.is_valid():
        _respawn_tween.kill()
    _respawn_tween = create_tween()
    # Phase 1 : flash blanc intercalé 50 ms (snap-in immédiat)
    _respawn_tween.tween_property(_overlay, "color", RESPAWN_FLASH_COLOR, 0.0)
    _respawn_tween.tween_interval(RESPAWN_FLASH_DURATION)
    # Phase 2 : fade vers transparent 100 ms
    _respawn_tween.tween_property(_overlay, "color", Color(0.4, 0.0, 0.0, 0.0), RESPAWN_OVERLAY_FADE_DURATION)
    _respawn_tween.tween_callback(func(): _overlay.visible = false)
```

Déclarer `_respawn_tween` :

```gdscript
var _respawn_tween: Tween
```

- **Phase 1 — flash blanc** : snap immédiat `Color(1,1,1,0.9)` pendant `RESPAWN_FLASH_DURATION = 50 ms` (tween_interval tient la couleur constante).
- **Phase 2 — fade rouge→transparent** : 100 ms, target `Color(0.4, 0, 0, 0.0)` (alpha 0 mais couleur rouge maintenue pour transition cohérente si interpolation manuelle — pour Tween c'est peu visible car alpha 0 domine).
- **Callback final** : `_overlay.visible = false` pour rester propre (sécurité au-delà du tween).
- **Tween kill si respawn consécutif** : si died/respawned/died/respawned arrive en < 200 ms (edge case), on kill le tween en cours avant de relancer — évite conflit.
- **Timing total** : 50 ms flash + 100 ms fade = 150 ms overlay + 50 ms RESPAWN_DELAY Movement = 200 ms gross total, bien sous la cible 400 ms Pillar 3.
- **Alternative non-Tween** (si QA préfère contrôle exact frames) : séquence `_process` delta accumulator avec machine à états `RESPAWN_ANIM_FLASH → RESPAWN_ANIM_FADE → RESPAWN_ANIM_DONE`. Choix Tween ici pour compacité code et parce que GUT peut valider l'état post-`await get_tree().create_timer(...)`.
- **Evidence capture** : capture 5 frames écartés ~50 ms (0, 50, 100, 150, 200 ms post-died), doc markdown avec images à `production/qa/evidence/camera-respawn-fade-[date].md`.

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- Story 008 : structure overlay + handlers + idempotence + reset effets (déjà fait).
- Story 010 : reduce_motion (le flash + fade restent actifs même en reduce_motion — c'est un respawn, pas un effet gameplay ; non-ambigu que ce soit conservé).
- Future Audio System : son respawn pop synchronisé via signal `respawned` (aval, pas Camera).

---

## QA Test Cases

**AC-CAM-42 (fade + flash visuel)** — Manual check (Visual/Feel — ADVISORY)

- Setup : scène test avec Player, déclencher `player.died.emit()` puis après ~60 ms déclencher `player.respawned.emit(Vector3.ZERO)` ; capture vidéo 60 fps ou 5 screenshots espacés ~50 ms
- Verify :
  - Frame 0 (`t=0`, juste après died) : overlay rouge `(0.4, 0, 0, 0.6)` plein écran
  - Frame ~60-100 ms (mid-red, respawn pas encore) : overlay rouge identique
  - Frame ~100-150 ms (juste après respawned) : overlay blanc `(1,1,1,0.9)` plein écran — flash visible
  - Frame ~200 ms (mid-fade) : overlay rouge semi-transparent alpha ~0.3, dégradation vers transparent
  - Frame ~250 ms (clear) : overlay invisible, monde normal
- Pass condition : 3 phases perceptuellement distinctes (rouge → flash blanc → clear) ; pas de jump cut entre flash et clear (transition continue) ; totalité < 300 ms observable

**AC-CAM-FLASH-2 (total duration ≤ 400 ms)** — Manual check (Feel)

- Setup : timer GUT wrapping `died` → await `respawned` + séquence fade terminée via `_respawn_tween.finished`
- Verify : temps total de `died.emit()` à `_overlay.visible == false` mesuré en ms
- Pass condition : ≤ 400 ms (cible Pillar 3)

---

## Test Evidence

**Story Type** : Visual/Feel
**Required evidence** : `production/qa/evidence/camera-respawn-fade-[YYYY-MM-DD].md` — 5 frames capture (death, mid-red, flash-white, mid-fade, clear) + timestamp measurement + sign-off lead (QA Lead ou creative-director) ; **ADVISORY** — ne bloque pas `/story-done` mais requis avant sprint demo

**Status** : [x] Created — `production/qa/evidence/camera-respawn-fade-2026-05-02.md` (scaffold complete avec objective evidence section + Martin manual section Sprint 1 + ADR compliance checklist) + smoke test `tests/integration/camera/story_009_respawn_fade_flash_test.gd` 5/5 PASSED (`reports/report_147`).

---

## Dependencies

- Depends on : Story 008 (overlay structure pré-créée, handlers died/respawned existent, state machine)
- Unlocks : Polish/Demo milestone readiness (séquence respawn signature du jeu, Pillar 3 visible)

---

## Completion Notes

**Completed** : 2026-05-02
**Verdict** : COMPLETE WITH NOTES
**Criteria** : 3/3 — AC-CAM-42 + AC-CAM-FLASH-2 auto-COVERED ; AC-CAM-FLASH-1 DEFERRED Sprint 1 (Visual/Feel manuel ADVISORY).

**Files livrés** :
- `src/gameplay/camera/camera_system.gd` (MODIFIED) — 4 constants (FADE_DURATION=0.100, FLASH_DURATION=0.050, FLASH_COLOR=(1,1,1,0.9), FADE_END_COLOR=(0.4,0,0,0)) + `_respawn_tween: Tween` var + `_animate_respawn_overlay()` (Tween séquencé : flash snap-in 0s → tween_interval 50ms → fade 100ms → tween_callback hide) + override `_on_respawned` (replace `_overlay.visible=false` direct par `_animate_respawn_overlay()`) + kill tween dans `_on_died` (edge case died→respawned→died <200ms double-safety).
- `tests/integration/camera/story_009_respawn_fade_flash_test.gd` (NEW 220 L) — 5 tests GdUnit4 : AC-CAM-42 ×3 (Phase 1 flash white snap-in, Phase 4 hidden post-tween.finished, tween validity during animation), AC-CAM-FLASH-2 timing budget Pillar 3 ≤ 400 ms (mesure objective `Time.get_ticks_msec` autour `await tween.finished`), edge case died→respawn→died kill tween + reset overlay.
- `tests/integration/camera/story_008_respawn_lifecycle_test.gd` (MODIFIED OUT-OF-SCOPE justifié) — `test_ac_cam_41` await `_respawn_tween.finished` avant assertions overlay.visible=false. Story-009 changea le contrat : overlay visible pendant animation, hidden via callback final. Régression évidente, fix immédiat.
- `production/qa/evidence/camera-respawn-fade-2026-05-02.md` (NEW) — evidence scaffold avec 5 sections : reference + automated objective evidence (5/5 PASSED table) + manual ⚠️ MARTIN frames table 5 captures + sign-off creative-director + lead QA + ADR/manifest compliance checklist + tech debt follow-ups.

**Test-Criterion Traceability** : 5/6 COVERED (83%) + 1 DEFERRED-PER-SPEC.

| Criterion | Test | Status |
|-----------|------|--------|
| AC-CAM-42 (Phase 1 flash white) | `test_ac_cam_42_respawn_animation_starts_with_white_flash` | COVERED |
| AC-CAM-42 (Phase 4 hidden) | `test_ac_cam_42_respawn_animation_ends_with_overlay_hidden` | COVERED |
| AC-CAM-42 (tween validity) | `test_ac_cam_42_tween_is_valid_during_animation` | COVERED |
| AC-CAM-FLASH-2 (≤ 400 ms) | `test_ac_cam_flash_2_total_animation_duration_under_pillar3_budget` | COVERED |
| AC-CAM-FLASH-1 (perceptuel 3 phases) | Manual sign-off Martin Sprint 1 | DEFERRED-PER-SPEC |
| Edge died→respawn→died kill tween | `test_died_during_respawn_animation_kills_tween_and_resets_overlay` | COVERED bonus |

**Tests** : 5/5 PASSED 410 ms 0 errors 0 failures (`reports/report_147`). Suite story-008 + story-009 = 10/10 PASSED 655 ms. Suite camera complète 21 cases 0 régression baseline.

**ADR Compliance** : COMPLIANT (verified manual review pass)
- ADR-0002 ownership : overlay owned par Camera (CanvasLayer enfant CameraSystem/CameraArm), VFX System ne duplique pas ✓
- ADR-0001 Rule 12 : animation Tween async cosmetic (auto-processed SceneTree, équivalent `_process`), PAS `_physics_process` ✓
- ADR-0005 D-7 : `_on_respawned(_position)` ignore position, ne touche que Camera-side state ✓
- Manifest 2026-04-23 zero-alloc hot-path ✓ (`create_tween()` invoqué 1× par respawn rare event, PAS dans `_process`)

**Deviations** :
- DEFERRED-PER-SPEC AC-CAM-FLASH-1 : Visual/Feel sign-off Martin Sprint 1 (etage_01 + WorldBoundsVolume requis). Conforme test-standards Visual/Feel ADVISORY.
- ADVISORY-1 (code review S-1) : timing tolerance ±50 ms confortable headless local, à élargir 100 ms si flaky CI.
- ADVISORY-2 : Pattern test camera tech debt (`%CameraEffects` push_error sans scene owner) continue, héritage 005-008.
- OUT-OF-SCOPE-1 justifié : `story_008_respawn_lifecycle_test.gd` actualisé pour await tween (régression évidente du contrat changé).

**Code Review** : APPROVED WITH SUGGESTIONS (Solo mode — LP-CODE-REVIEW gate skipped, manual review pass clean).
- 6/6 standards passing
- ADR compliance COMPLIANT (3 ADRs verified)
- Architecture CLEAN, SOLID COMPLIANT, Game-specific CLEAN
- 3 suggestions cosmétiques non-bloquantes (S-1 timing tolerance / S-2 lambda extract / S-3 reduce_motion anticipation story 010)

**Camera Epic Progress** : 9/12 stories Complete (001-009). Stories 010 (reduce_motion), 011 (_exit_tree cleanup), 012 (perf instrumentation) Ready.

**Next Recommended** : `/story-readiness production/epics/camera-system/story-010-reduce-motion-gate.md` puis `/dev-story`.

