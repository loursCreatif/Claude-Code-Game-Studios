# Audio Listener 3D Verification — 2026-05-04 (Story-010)

> **Story** : `production/epics/audio-system/story-010-audiolistener3d-verification-adr-0002-chain.md`
> **ADR Governing** : ADR-0009 D-6 (1 listener unique) + ADR-0002 chain VC-5
> **Mode** : Solo dev (sound-designer + godot-specialist sign-off ADVISORY DEFERRED Sprint Audio playtest)
> **Date** : 2026-05-04

---

## AC-AUD-14 (c) — Single listener assertion (BLOCKING headless)

**Status** : ✅ PASS

**Test** : `tests/integration/audio/audio_listener3d_single_assertion_test.gd` (3/3 PASS, 80 ms)
- `test_single_audio_listener_3d_in_player_scene_tree` — `find_children("*", "AudioListener3D", true).size() == 1`
- `test_audio_listener_3d_parent_is_camera_3d` — listener parent `is Camera3D == true` (ADR-0002 chain)
- `test_audio_system_does_not_instantiate_second_listener` — AudioSystem autoload n'embarque aucun listener (defense-in-depth contre violation D-6 runtime)

**Scene tree audited** : `src/gameplay/player/Player.tscn`
```
Player (CharacterBody3D)
└── CameraArm (Node3D, group "camera_system")
    └── CameraEffects (Node3D)
        └── Camera3D (position Vector3.ZERO per ADR-0002)
            └── AudioListener3D  ← UNIQUE, auto-current Godot 4.6
```

**Notes** :
- AC-CAM-TREE-4 (Camera epic) note explicite ligne 55 `Player.tscn` : *"AudioListener3D is auto-current — make_current() must NOT be called."*
- Aucun appel `make_current()` dans `src/core/audio_system.gd` ni `src/gameplay/camera/` (vérifié grep).
- Lint statique story-009 (`AudioStreamPlayer.new() / AudioListener3D.new()` interdit hors `audio_system.gd`) garde l'invariant côté code source.

---

## AC-AUD-14 (a) — Panning stereo (ADVISORY playtest)

**Status** : ⏸ DEFERRED Sprint Audio (sound-designer playtest manuel casque)

**Protocol** :
1. Lancer scène `src/gameplay/player/Player.tscn` (Camera3D + AudioListener3D enfant actifs)
2. Depuis script test ou DebugScene, appel `AudioSystem.play_3d_at(clac_stream, Vector3(10, 0, 0), AudioBuses.COMBAT_KILL)`
3. Tourner Player 90° autour Y : `player.rotation.y = PI / 2`
4. Sound-designer écoute casque : son perçu côté gauche (position 3D relative à AudioListener3D Camera3D rotated)

**Expected** : panning stereo audible côté gauche après rotation Y 90° (Godot 4.6 auto-handle single listener).

**Sign-off requis** : sound-designer @TBD, godot-specialist @TBD (Sprint Audio playtest).

---

## AC-AUD-14 (b) — Distance attenuation (ADVISORY playtest)

**Status** : ⏸ DEFERRED Sprint Audio (sound-designer playtest manuel casque)

**Protocol** :
1. Sound-designer compare volume entre :
   - `play_3d_at(clac_stream, Vector3(1, 0, 0), AudioBuses.COMBAT_KILL)` (proche)
   - `play_3d_at(clac_stream, Vector3(10, 0, 0), AudioBuses.COMBAT_KILL)` (loin)
2. Différence perceptuelle attendue ~ -20 dB selon `unit_size` Godot 4.6 default (Inverse Distance model)

**Expected** : volume décroît avec distance (audible perceptuel).

**Sign-off requis** : sound-designer @TBD (Sprint Audio playtest).

---

## R-2 ADR-0009 — SubViewport edge case

**Status** : ✅ N/A MVP (pas de SubViewport actif)

**Notes** :
- Aucun `SubViewport` détecté dans `scenes/` ni `src/gameplay/` au 2026-05-04 (vérifié grep `SubViewport`).
- Re-vérification obligatoire **post-introduction** d'une UI minimap, mirror, picture-in-picture ou screen-effect basé sur SubViewport — ajouter `find_children` scope viewport racine pour assurer 0 listener supplémentaire dans SubViewport.

---

## Sign-off Solo MVP

| Role | Sign-off | Date | Notes |
|------|----------|------|-------|
| AC-AUD-14 (c) BLOCKING headless | ✅ Solo (Claude assist Sprint Audio story-010) | 2026-05-04 | 3/3 tests PASS, 80 ms |
| AC-AUD-14 (a) Panning ADVISORY | ⏸ DEFERRED | — | Sprint Audio sound-designer playtest |
| AC-AUD-14 (b) Distance attenuation ADVISORY | ⏸ DEFERRED | — | Sprint Audio sound-designer playtest |
| R-2 SubViewport edge case | ✅ N/A MVP | 2026-05-04 | Re-check post-minimap/mirror introduction |

**Verdict** : story-010 BLOCKING headless covered ; ADVISORY playtest tracking ouvert dans `production/qa/evidence/` pour Sprint Audio dédiée.
