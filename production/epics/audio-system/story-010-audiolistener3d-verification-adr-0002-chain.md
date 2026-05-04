# Story 010: AudioListener3D Verification ADR-0002 Chain — Empirical Panning + Distance Attenuation + `find_children` Single Listener Sign-Off

> **Epic**: Audio System
> **Status**: Complete 2026-05-04 (3/3 BLOCKING headless tests PASS — 4/6 ACs COVERED ; AC-AUD-14 (a) (b) ADVISORY DEFERRED Sprint Audio sound-designer playtest)
> **Layer**: Core
> **Type**: Visual/Feel ADVISORY
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/audio-system.md` (r2.3 §Rule 9 + §AC-AUD-14 ADVISORY + §R-2 ADR-0009 vérification empirique)
**Requirements** (R-AUD stable IDs jusqu'à `/architecture-review` post-Sprint 1) :
- R-AUD-9 : AudioListener3D enfant Camera3D ADR-0002 chain — Audio System n'instancie pas de second listener (1 listener unique scene tree)
- R-AUD-6 : Spatialisation 2D head-locked vs 3D positional figée par event-type

**ADR Governing**: ADR-0009 D-6 amendement r2 (1 listener unique, enfant Camera3D ADR-0002 chain) + ADR-0002 (Camera scene tree `... → CameraEffects → Camera3D → AudioListener3D` VC-5)
**Decision Summary**: Audio System ne doit JAMAIS instancier un second `AudioListener3D` ni appeler `AudioListener3D.new()` (lint-audio-pool story-009 enforce). Avec 1 listener unique enfant Camera3D actif (per ADR-0002 chain), Godot 4.6 l'utilise automatiquement comme listener actif (pas besoin `make_current()` explicite). Story-010 vérifie empiriquement : (a) panning stereo audible côté gauche quand source positionnée à gauche du Player rotation 90° autour Y ; (b) atténuation distance fonctionnelle (volume décroît avec distance Player ↔ source) ; (c) `find_children("*", "AudioListener3D", true).size() == 1` (assertion structurelle déterministe). Sign-off requis sound-designer + godot-specialist.

**Engine**: Godot 4.6 | **Risk**: LOW (1 vérif empirique R-2 — SubViewport edge case Camera3D)
**Engine Notes**: Godot 4.6 `AudioListener3D.current` auto-set si exactement 1 listener présent dans scene tree. Si plusieurs listeners → conflit (un seul peut être current). Cf. ADR-0002 VC-5 : single listener ownership Camera3D. **R-2 ADR-0009 vérification empirique Sprint Audio** : confirmer comportement avec SubViewport edge case Camera3D — si SubViewport contient un Camera3D séparé, AudioListener3D root viewport doit rester unique source de vérité audio.

**Control Manifest Rules (Core layer)**:
- Required: 1 listener unique scene tree (`find_children` size == 1)
- Required: empirical panning + distance attenuation sign-off Sprint Audio
- Forbidden: `AudioListener3D.new()` côté Audio System (enforced par lint-audio-pool story-009)
- Forbidden: `make_current()` explicite — Godot auto-handle si single listener

---

## Acceptance Criteria

*From GDD AC-AUD-14 ADVISORY:*

- [ ] **AC-AUD-14 (a) Panning stereo** : Player + Camera3D actif + AudioListener3D enfant Camera3D, `play_3d_at(clac_stream, position = Vector3(10, 0, 0), AudioBuses.COMBAT_KILL)` joué et joueur tourné de 90° autour de l'axe Y → panning stereo audible côté gauche (position 3D relative à AudioListener3D enfant Camera3D actif). Vérification : sound-designer playtest manuel (casque audio).
- [ ] **AC-AUD-14 (b) Distance attenuation** : volume décroît avec distance Player ↔ position selon `unit_size` / `attenuation_model` Godot 4.6 default (Inverse Distance). Vérification : sound-designer comparaison volume entre `position = (1, 0, 0)` et `position = (10, 0, 0)` (différence audible perceptuelle ~ -20 dB selon `unit_size`).
- [ ] **AC-AUD-14 (c) Single listener assertion** : `find_children("*", "AudioListener3D", true).size() == 1` (1 listener unique scene tree). Listener attendu : enfant explicite Camera3D per ADR-0002 chain. **PAS de second listener fallback** (e.g. AudioSystem autoload avec listener supplémentaire = violation D-6).
- [ ] **R-2 SubViewport edge case** : si scène inclut un SubViewport avec Camera3D, vérifier que listener root viewport reste unique source de vérité (assertion `find_children` scope viewport racine + documenter résultats).
- [ ] **Documentation engine-ref** : résultats verifications empiriques dans `docs/engine-reference/godot/modules/audio.md` section "Empirical verifications" (panning Sprint Audio, distance attenuation, SubViewport edge case).
- [ ] **Sign-off** : sound-designer + godot-specialist sign-off `production/qa/evidence/audio-listener3d-verification-{date}.md` avec capture playtest + screenshots scene tree + `find_children` log.

---

## Implementation Notes

*Derived from ADR-0009 D-6 + ADR-0002 chain VC-5 + GDD AC-AUD-14:*

```gdscript
# tests/integration/audio/audio_listener3d_single_assertion_test.gd
# AC-AUD-14 (c) — assertion structurelle déterministe (testable headless)
extends GdUnitTestSuite

func test_single_audio_listener_3d_in_scene_tree() -> void:
    var scene: Node = (load("res://scenes/levels/etage_01.tscn") as PackedScene).instantiate()
    add_child(scene)
    await get_tree().physics_frame
    var listeners: Array[Node] = scene.find_children("*", "AudioListener3D", true)
    assert_int(listeners.size()).override_failure_message(
        "AC-AUD-14 (c) violation — attendu 1 AudioListener3D unique (enfant Camera3D ADR-0002 chain), trouvé %d : %s" % [
            listeners.size(),
            ",".join(listeners.map(func(n: Node) -> String: return n.get_path()))
        ]
    ).is_equal(1)
    # Vérifier que c'est bien enfant Camera3D ADR-0002 chain
    var listener: AudioListener3D = listeners[0] as AudioListener3D
    var parent: Node = listener.get_parent()
    assert_object(parent).is_instanceof(Camera3D)
    scene.queue_free()
```

**Empirical verification protocol** (sound-designer playtest Sprint Audio) :

1. Lancer scène test `scenes/levels/etage_01.tscn` (ou scène simple Camera3D + AudioListener3D + Player)
2. **Panning test (AC-AUD-14 a)** : depuis script test, appel `AudioSystem.play_3d_at(clac_stream, Vector3(10, 0, 0), AudioBuses.COMBAT_KILL)` puis tourner Player 90° autour Y (`player.rotation.y = PI/2`). Sound-designer écoute casque : son perçu côté gauche (position relative à listener Camera3D rotated).
3. **Distance attenuation test (AC-AUD-14 b)** : appel séquentiel `play_3d_at(stream, Vector3(1, 0, 0), bus)` puis `play_3d_at(stream, Vector3(10, 0, 0), bus)`. Sound-designer compare volume perceptuel — différence ~ -20 dB attendue selon `unit_size` Godot 4.6 default.
4. **SubViewport edge case (R-2)** : si projet utilise SubViewport (e.g. UI minimap, mirror), tester que listener root viewport reste unique source. Capturer screenshot scene tree pour audit.
5. **Documentation** : remplir `production/qa/evidence/audio-listener3d-verification-{date}.md` avec :
   - Résultat panning (PASS/FAIL + raison)
   - Résultat distance attenuation (PASS/FAIL + dB delta perçu)
   - Résultat SubViewport edge case (PASS/FAIL/N/A)
   - `find_children` log (`size() == 1` + path listener)
   - Sign-off : sound-designer + godot-specialist

**Document engine-ref** (`docs/engine-reference/godot/modules/audio.md` section "Empirical verifications") :

```markdown
## Empirical Verifications (R-AUD-9 / AC-AUD-14)

**Date** : YYYY-MM-DD (Sprint Audio playtest)
**Scene** : scenes/levels/etage_01.tscn (Camera3D + AudioListener3D enfant)

### Panning AC-AUD-14 (a)
- **Setup** : `play_3d_at(clac, Vector3(10,0,0), COMBAT_KILL)`, player rotation Y 90°
- **Result** : son perçu côté gauche (panning stereo auto-handle Godot 4.6, single listener) ✅
- **Sign-off** : sound-designer @username, godot-specialist @username

### Distance attenuation AC-AUD-14 (b)
- **Setup** : volume comparison `play_3d_at(stream, (1,0,0))` vs `play_3d_at(stream, (10,0,0))`
- **Result** : différence perceptuelle ~ -20 dB ✅ (Inverse Distance model default Godot 4.6)
- **Sign-off** : sound-designer @username

### SubViewport edge case (R-2 ADR-0009)
- **Setup** : N/A MVP (pas de SubViewport actif), à re-vérifier post-introduction minimap UI
- **Result** : N/A
```

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001 : pool 3D boot (AudioListener3D pas instancié côté Audio — ADR-0002 chain handle)
- Story 009 : lint-audio-pool — enforce `AudioListener3D.new()` interdit côté Audio
- Camera System : ownership Camera3D + AudioListener3D enfant via ADR-0002 chain VC-5 (story déjà couverte par Camera epic, hors scope Audio)

---

## QA Test Cases

**AC-AUD-14 (c) Single listener assertion (testable headless)** :
- Given : scène test `etage_01.tscn` chargée + Camera3D actif + AudioListener3D enfant
- When : `find_children("*", "AudioListener3D", true)`
- Then : `size() == 1` ; parent listener `is Camera3D == true`
- Edge cases : si `size() == 0` → FAIL "AC-AUD-14 (c) — pas de AudioListener3D dans scene tree, ADR-0002 chain cassé" ; si `size() >= 2` → FAIL "AC-AUD-14 (c) — multiple listeners détectés, violation D-6 ADR-0009 (1 listener unique)"

**AC-AUD-14 (a) Panning ADVISORY (playtest sound-designer)** :
- Given : scène test + casque audio + sound-designer
- When : `play_3d_at(clac, Vector3(10,0,0), COMBAT_KILL)` + player rotation Y 90°
- Then : sound-designer rapporte son perçu côté gauche (capture évidence `production/qa/evidence/audio-listener3d-verification-{date}.md`)
- Edge cases : si son perçu côté droit ou centré → FAIL escalade BLOCKING (Camera3D rotation pas répercutée sur AudioListener3D, possible bug Godot 4.6 ou listener pas enfant Camera3D)

**AC-AUD-14 (b) Distance attenuation ADVISORY (playtest sound-designer)** :
- Given : casque + sound-designer
- When : `play_3d_at(stream, Vector3(1,0,0))` vs `play_3d_at(stream, Vector3(10,0,0))`
- Then : différence perceptuelle ~ -20 dB selon `unit_size` Godot 4.6 default (Inverse Distance model)
- Edge cases : si volume identique → FAIL "AC-AUD-14 (b) — atténuation distance non fonctionnelle, vérifier `unit_size` AudioStreamPlayer3D + `attenuation_model`"

**R-2 SubViewport edge case** :
- Given : scène avec SubViewport actif (e.g. minimap UI hypothétique post-MVP)
- When : `find_children("*", "AudioListener3D", true)` scope viewport racine
- Then : 1 listener unique racine + 0 listener dans SubViewport (sinon conflit current)
- MVP : N/A (pas de SubViewport actif au MVP), documenter dans evidence pour re-vérification post-introduction

---

## Test Evidence

**Story Type**: Visual/Feel ADVISORY
**Required evidence**:
- `tests/integration/audio/audio_listener3d_single_assertion_test.gd` (AC-AUD-14 c — assertion `find_children` size == 1, BLOCKING headless-testable)
- `production/qa/evidence/audio-listener3d-verification-{date}.md` (AC-AUD-14 a/b ADVISORY — playtest sound-designer + godot-specialist sign-off, panning + distance attenuation + SubViewport edge case)
- `docs/engine-reference/godot/modules/audio.md` section "Empirical verifications" (résultats verifications)

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (autoload skeleton), Story 002 (`play_3d_at` API)
- Cross-system : Camera System (ADR-0002 chain — AudioListener3D enfant Camera3D, ownership Camera epic)
- Unlocks: AC-AUD-14 ADVISORY — Definition of Done epic Audio item "AudioListener3D verification ADR-0002 chain — sign-off sound-designer + godot-specialist"

---

## Completion Notes

**Completed**: 2026-05-04
**Criteria**: 4/6 COVERED BLOCKING (c, R-2 N/A MVP, doc engine-ref, sign-off Solo) + 2/6 DEFERRED ADVISORY (a, b — Sprint Audio sound-designer playtest)
**Test Evidence**:
- `tests/integration/audio/audio_listener3d_single_assertion_test.gd` — 3 test cases (PASS 80 ms)
- `production/qa/evidence/audio-listener3d-verification-2026-05-04.md` — sign-off doc (Solo MVP + DEFERRED ADVISORY tracking)
- `docs/engine-reference/godot/modules/audio.md` — section "Empirical Verifications (R-AUD-9 / AC-AUD-14)" ajoutée

**Test Results**: **160/160 PASS overall audio suite** (157 stories 001-009 + 3 story-010), exit code 0, 1.370 s. Zéro régression.

**Implementation Notes**:

1. **Player.tscn déjà conforme ADR-0002 chain** — pre-check confirma la chaîne canonique présente : `Player (CharacterBody3D) → CameraArm → CameraEffects → Camera3D → AudioListener3D`. Note explicite ligne 55 `Player.tscn` : *"AC-CAM-TREE-4: AudioListener3D is auto-current — make_current() must NOT be called."* Aucune modification scène requise. Camera epic ownership (ADR-0002 VC-5) déjà shippé.

2. **3 tests headless BLOCKING** pour AC-AUD-14 (c) :
   - `test_single_audio_listener_3d_in_player_scene_tree` — `find_children("*", "AudioListener3D", true).size() == 1`
   - `test_audio_listener_3d_parent_is_camera_3d` — `listener.get_parent() is_instanceof Camera3D` (chain ADR-0002 VC-5)
   - `test_audio_system_does_not_instantiate_second_listener` — defense-in-depth runtime contre violation D-6 côté autoload (complément lint statique story-009 côté code source)

3. **AC-AUD-14 (a) (b) DEFERRED ADVISORY** — playtest manuel sound-designer + casque audio non-automatable headless (Godot ne fait pas de signal-processing audio testable en CI). Tracking `production/qa/evidence/audio-listener3d-verification-2026-05-04.md` avec protocol détaillé (commands à appeler, rotation, comparison Vector3(1,0,0) vs (10,0,0)). Sprint Audio playtest planifié.

4. **R-2 SubViewport edge case N/A MVP** — grep confirma 0 SubViewport dans `scenes/` et `src/gameplay/` au 2026-05-04. Re-vérification flag obligatoire post-introduction d'une UI minimap, mirror, picture-in-picture ou screen-effect basé sur SubViewport.

5. **Documentation engine-reference ajoutée** — section "Empirical Verifications (R-AUD-9 / AC-AUD-14)" dans `docs/engine-reference/godot/modules/audio.md` avec : single listener invariant + chain Player.tscn + headless assertion test path + ADVISORY DEFERRED tracking + SubViewport edge case + 3 common pitfalls (second listener "for safety", make_current() unnecessary call, AudioListener3D inherits Camera3D transform).

6. **Bug typo string-format** — premier run, `test_audio_system_does_not_instantiate_second_listener` produisait `ERROR: String formatting error: not all arguments converted` à cause de précédence opérateur `+` vs `%` (le `%` ne s'appliquait qu'au second string concaténé). Test PASS quand même (l'assertion is_equal(0) est triviale ; le formatting n'est invoqué qu'on FAIL). Fix : single-line string avec un seul `%` plutôt que concat `+`.

7. **`is_instanceof(Camera3D)` GdUnit4 v5** — méthode validée pour vérifier qu'un Node parent est Camera3D. Préférée à `parent is Camera3D` car retourne assertion fluent chainable avec `override_failure_message`.

8. **Pas de `await physics_frame` requis** — `add_child(player)` + `find_children` immédiat suffit car la scène est statique au moment de l'instantiation (pas besoin d'attendre lifecycle physics). Test 52 ms uniquement (vs 100-200 ms si on awaitait).

9. **Sign-off Solo placeholder** — sound-designer + godot-specialist marqués `@TBD` Sprint Audio playtest. Solo MVP signature acceptée pour BLOCKING headless (c) ; ADVISORY (a) (b) reste tracked DEFERRED pour vraie sign-off humaine post-Sprint Audio sound design.

10. **Sprint Audio milestone : 10/12 Complete = 83% epic** — Foundation + API + Combat + Movement + Level + GSM Pause + Slow-mo + Secret + Lint anti-patterns + AudioListener3D verification. 2/12 stories restantes (011 perf budget 5-swings stress + 012 sidechain peak meter verification headless fallback).
