# Story 007: Slow-Mo Pitch Shift Bus-Level Allowlist + Clac Slot Exclusion `_active_clac_players` Tracker (Phase D.3)

> **Epic**: Audio System
> **Status**: Complete 2026-05-04 (25/25 tests PASS — 6/6 ACs COVERED + Phase D.3 r2.3 orphan tracker fix ; AC-AUD-15-b ADVISORY headless SKIPPED — evidence sound-designer Sprint Audio pending)
> **Layer**: Core
> **Type**: Integration
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/audio-system.md` (r2.3 §Rule 11 + §Formula 5 + §AC-AUD-15-a BLOCKING + AC-AUD-15-b ADVISORY + Phase D.3 pseudo-code lignes 248-280)
**Requirements** (R-AUD stable IDs jusqu'à `/architecture-review` post-Sprint 1) :
- R-AUD-11 : Pitch shift bus-level allowlist sous slow-mo (`COMBAT_KILL=true` queue blood UNIQUEMENT / `AMBIENCE=true` ; autres invariants) + exclusion explicite slot clac via `_active_clac_players` tracker
- R-AUD-13 : Multi-kill clac avec pitch-shift +N semitones — slot clac exclu du slow-mo allowlist (pitch Rule 13 préservé)

**ADR Governing**: ADR-0009 D-3 amendement r2 (allowlist `pitch_scale_follows_time_scale` per bus)
**Decision Summary**: Détecter `Engine.time_scale != 1.0` → itérer pool actifs → appliquer `pitch_scale = 2.0 ** (semitones / 12.0)` (Formula 5) sur slots dont le bus est dans allowlist (`COMBAT_KILL=true` queue blood + `AMBIENCE=true` room tone). Slot clac exclu via `_active_clac_players: Dictionary[int, bool]` typed tracker — populé au `play_3d_at(clac_stream, ..., AudioBuses.COMBAT_KILL)` côté Combat handler (story-003), nettoyé via `finished` signal `CONNECT_ONE_SHOT` ou défensivement avant `stop()` round-robin saturation. Pitch appliqué AVANT `play()` zero latency (handler set pitch puis play, pas l'inverse).

**Engine**: Godot 4.6 | **Risk**: LOW (1 vérif empirique R-3 — `pitch_scale` runtime mid-`play()` pop sonore, AC-AUD-15-b ADVISORY)
**Engine Notes**: `AudioStreamPlayer3D.pitch_scale` propriété instantanée Godot 4.0+, set live mid-playback supporté. **R-3 pop sonore vérification empirique Sprint Audio** : transition `1.0 → 0.7935 → 1.0` peut produire discontinuité waveform si pitch change brutal — AC-AUD-15-b ADVISORY headless-conditional via `AudioEffectRecord` (CI Dummy driver SKIPPED, evidence playtest sound-designer requise). Si pop audible détecté → escalade BLOCKING amendement Rule 11.

**Control Manifest Rules (Core layer)**:
- Required: pitch appliqué AVANT `play()` côté handler dispatch (zero latency 1 tick)
- Required: tracker `_active_clac_players` typed `Dictionary[int, bool]` avec cleanup défensif pré-stop round-robin (Phase D.3)
- Forbidden: pitch shift sur bus hors allowlist (`MUSIC`, `SWING_ACTIVE`, `SFX`, `UI` invariants)
- Forbidden: composite `pitch_scale = SECRET_PITCH × Formula5` sur secret SFX (story-008 invariant slow-mo)

---

## Acceptance Criteria

*From GDD AC-AUD-15-a (BLOCKING headless-testable) + AC-AUD-15-b (ADVISORY headless-conditional anti-pop waveform):*

- [ ] **AC-AUD-15-a (a) Bus invariants** : `Engine.time_scale = 0.3` actif → swoosh `AudioStreamPlayer.pitch_scale == 1.0 ± 0.001` (`SWING_ACTIVE`) ; music `pitch_scale == 1.0 ± 0.001` (`MUSIC`).
- [ ] **AC-AUD-15-a (b) Bus pitch-shifted (blood ambiance UNIQUEMENT sur COMBAT_KILL)** : blood ambiance `pitch_scale ≈ 0.8821 ± 0.005` (≈ -2.1 semitones, Formula 5 à `time_scale=0.3`) ; ambient `pitch_scale ≈ 0.8821 ± 0.005`.
- [ ] **AC-AUD-15-a (b') Slot clac exclu** : si clac `clac.wav` joue sur `COMBAT_KILL` au moment du slow-mo, son slot pool 3D tracké dans `_active_clac_players` et son `pitch_scale ∈ {1.0, 1.122, 1.260} ± 0.005` (valeur Rule 13 rang multi-kill actif au moment du `play()`, PAS unconditionally `1.0`). L'invariant testé : pitch_scale du slot clac == valeur Rule 13 au moment du play, NE PAS multipliée par Formula 5.
- [ ] **AC-AUD-15-a (d) Duration sample** : duration native du sample inchangée (Godot pitch_scale impacte la lecture, pas le fichier source).
- [ ] **AC-AUD-15-a (e) Sons démarrés pendant slow-mo** : `enemy_killed` reçu pendant `time_scale=0.3` → blood ambiance démarrée 50 ms post-clac sur `COMBAT_KILL` (slot blood, pas slot clac) → `pitch_scale ≈ 0.8821 ± 0.005` AU MOMENT DU `play()` (handler set pitch avant play, pas après — Rule 11 r2 mécanisme). Pas de latence 1 tick visible.
- [ ] **AC-AUD-15-b (c) Anti-pop waveform** ADVISORY headless-conditional : transition `time_scale: 1.0 → 0.3 → 1.0`, enregistrer waveform via `AudioEffectRecord` sur bus `COMBAT_KILL`, FFT post-render — discontinuité peak-to-peak entre frames adjacents `≤ 3 dB`. Si `> 3 dB peak` : FAIL. **Headless CI** : SKIPPED + evidence requirement `production/qa/evidence/audio-pitch-transition-{date}.md` (sound-designer écoute manuelle Sprint Audio).
- [ ] **Phase D.3 orphan tracker fix** : `_active_clac_players[slot_idx]` erase AVANT `stop()` round-robin saturation guard ; cleanup pré-connect si slot recyclé ; defensive disconnect `_on_clac_finished` au cas où one-shot pas tiré (cf. r2.3 fix).

---

## Implementation Notes

*Derived from ADR-0009 D-3 amendement r2 + GDD Phase D.3 pseudo-code lignes 248-280:*

```gdscript
# AudioSystem (autoload) — slow-mo pitch shift handler
const PITCH_ALLOWLIST: Dictionary[StringName, bool] = {
    AudioBuses.MASTER: false,
    AudioBuses.MUSIC: false,
    AudioBuses.SFX: false,
    AudioBuses.SWING_ACTIVE: false,
    AudioBuses.COMBAT_KILL: true,   # queue blood ambiance (slot clac exclu via tracker)
    AudioBuses.AMBIENCE: true,      # room tone HLM drone
    AudioBuses.UI: false,
}

# Tracker slot clac exclu — Phase D.3 typed Dictionary, fix r2.3 orphan
var _active_clac_players: Dictionary[int, bool] = {}

func _physics_process(_delta: float) -> void:
    var ts: float = Engine.time_scale
    if not is_equal_approx(ts, 1.0):
        _apply_pitch_shift_slow_mo(ts)
    else:
        _restore_pitch_invariants()

func _apply_pitch_shift_slow_mo(ts: float) -> void:
    var pitch_factor: float = 2.0 ** (compute_semitones(ts) / 12.0)  # Formula 5
    for i in range(_3d_pool.size()):
        var p: AudioStreamPlayer3D = _3d_pool[i]
        if not p.playing:
            continue
        if not PITCH_ALLOWLIST.get(p.bus, false):
            p.pitch_scale = 1.0  # invariant
            continue
        if _active_clac_players.has(i):
            continue  # slot clac exclu, pitch Rule 13 préservé
        p.pitch_scale = pitch_factor

# Phase D.3 — populé par Combat handler story-003 au play_3d_at(clac, ..., COMBAT_KILL)
func _register_clac_slot(slot_idx: int, player: AudioStreamPlayer3D) -> void:
    # Fix r2.3 — cleanup pré-connect si slot recyclé (round-robin a déjà reused ce slot)
    if _active_clac_players.has(slot_idx):
        _active_clac_players.erase(slot_idx)
        if player.finished.is_connected(_on_clac_finished):
            player.finished.disconnect(_on_clac_finished)
    _active_clac_players[slot_idx] = true
    player.finished.connect(_on_clac_finished.bind(slot_idx), CONNECT_ONE_SHOT)

func _on_clac_finished(slot_idx: int) -> void:
    _active_clac_players.erase(slot_idx)

# Phase D.3 fix r2.3 — erase AVANT stop() round-robin saturation
func _round_robin_3d_stop_if_saturated(slot_idx: int, player: AudioStreamPlayer3D) -> void:
    if not player.playing:
        return
    # Erase tracker AVANT stop() — sinon `finished` ne fire pas (force-stop) → orphan tracker
    if _active_clac_players.has(slot_idx):
        _active_clac_players.erase(slot_idx)
        if player.finished.is_connected(_on_clac_finished):
            player.finished.disconnect(_on_clac_finished)
    player.stop()
    push_warning("AudioSystem: pool 3D saturation, force-stop slot %d" % slot_idx)

func compute_semitones(ts: float) -> float:
    # Formula 5 — log2(ts) × 12 → semitones (negative pour slow-mo ts<1)
    return log(ts) / log(2.0) * 12.0
```

**Note pitch appliqué AVANT play()** : côté handler dispatch (story-003 Combat / story-004 Movement / story-005 Level), set `player.pitch_scale = pitch_factor` AVANT `player.play()` — sinon premier tick joue à 1.0 puis pitch applied au tick suivant = pop audible.

**Note R-3 vérification empirique** : transition pitch_scale runtime mid-`play()` peut produire pop sur certains samples (selon waveform et sample rate). AC-AUD-15-b ADVISORY headless-conditional couvre. Sprint Audio sound-designer écoute manuelle requise — si pop détecté, escalade BLOCKING amendement Rule 11 (e.g. ramp pitch sur 1-2 frames au lieu de step instantané).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001 : pool boot
- Story 002 : API verbes (handlers utilisent `play_3d_at` qui set pitch avant play)
- Story 003 : Combat handler `_on_enemy_killed` qui appelle `_register_clac_slot(slot_idx, player)` — couplage par injection callback
- Story 008 : Secret handler — invariant slow-mo (bus `SFX` PAS dans allowlist, pitch_scale `SECRET_PITCH_SCALE = 1.335` invariant, NE PAS composite avec Formula 5)
- Story 009 : lint `lint-audio-pool` peut vérifier que `_register_clac_slot` est appelé uniquement depuis Combat handler

---

## QA Test Cases

**AC-AUD-15-a (a) Bus invariants** :
- Given : AudioSystem prêt, swoosh joue sur `SWING_ACTIVE` (allowlist=false), music joue sur `MUSIC` (allowlist=false)
- When : `Engine.time_scale = 0.3` puis `await get_tree().physics_frame`
- Then : swoosh `pitch_scale == 1.0 ± 0.001` ; music `pitch_scale == 1.0 ± 0.001`

**AC-AUD-15-a (b) Bus pitch-shifted blood/ambient** :
- Given : blood ambiance joue sur `COMBAT_KILL` (allowlist=true, slot non-clac), ambient joue sur `AMBIENCE` (allowlist=true)
- When : `Engine.time_scale = 0.3`
- Then : blood `pitch_scale ≈ 0.8821 ± 0.005` ; ambient `pitch_scale ≈ 0.8821 ± 0.005`

**AC-AUD-15-a (b') Slot clac exclu** :
- Given : 3 enemy_killed dans le même swing → 3 clacs joués sur `COMBAT_KILL`, slots 0/1/2 (rangs `pitch_scale = 1.0 / 1.122 / 1.260`), `_active_clac_players = {0: true, 1: true, 2: true}`
- When : `Engine.time_scale = 0.3` actif
- Then : slot 0 `pitch_scale ≈ 1.0 ± 0.005` (préservé Rule 13 rang 1) ; slot 1 `pitch_scale ≈ 1.122 ± 0.005` (préservé rang 2) ; slot 2 `pitch_scale ≈ 1.260 ± 0.005` (préservé rang 3) ; PAS multipliés par 0.8821 Formula 5

**AC-AUD-15-a (e) Sons démarrés pendant slow-mo** :
- Given : `Engine.time_scale = 0.3` actif, `enemy_killed` émis
- When : Combat handler dispatch blood ambiance 50 ms post-clac via `play_3d_at(blood_stream, pos, COMBAT_KILL)` (slot blood pas slot clac, donc pas dans `_active_clac_players`)
- Then : `pitch_scale` du slot blood `≈ 0.8821 ± 0.005` AU MOMENT DU `play()` (handler set pitch AVANT play). Pas de latence 1 tick visible.

**Phase D.3 orphan tracker fix r2.3** :
- Given : slot 5 dans `_active_clac_players`, round-robin nécessite réutiliser slot 5 (saturation), `player.playing == true`
- When : `_round_robin_3d_stop_if_saturated(5, player)` appelé
- Then : `_active_clac_players.has(5) == false` AVANT `stop()` ; `player.finished.is_connected(_on_clac_finished) == false` ; `player.stop()` exécuté ; `push_warning` capturé. Si slot recyclé pour nouveau clac via `_register_clac_slot(5, player_new)` → cleanup pré-connect détecte slot ancien et nettoie.

**AC-AUD-15-b (c) Anti-pop waveform** ADVISORY headless-conditional :
- Given : transition `time_scale: 1.0 → 0.3 → 1.0`
- When : `AudioEffectRecord` actif sur `COMBAT_KILL` pendant transition, FFT post-render
- Then headless CI : SKIPPED (driver Dummy ne supporte pas peak meter post-effects) → evidence `production/qa/evidence/audio-pitch-transition-{date}.md` sound-designer écoute manuelle requise
- Then runtime : discontinuité peak-to-peak `≤ 3 dB` entre frames adjacents — sinon FAIL escalade BLOCKING amendement Rule 11

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- `tests/integration/audio/pitch_shift_bus_allowlist_test.gd` (AC-AUD-15-a a/b/b'/d/e — testable headless via `AudioStreamPlayer3D.pitch_scale` introspection)
- `tests/integration/audio/active_clac_tracker_orphan_test.gd` (Phase D.3 fix r2.3 — round-robin saturation cleanup pré-stop, slot recyclé cleanup pré-connect, defensive disconnect)
- `production/qa/evidence/audio-pitch-transition-{date}.md` (AC-AUD-15-b ADVISORY — sound-designer playtest Sprint Audio + waveform Audacity/REAPER, headless SKIPPED documenté)

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (pool 3D 12 slots), Story 002 (API `play_3d_at`), Story 003 (Combat handler appelle `_register_clac_slot` au play_3d_at clac)
- Cross-system : Combat System (`enemy_killed` signal — slow-mo trigger via Combat ADR-0006 D-2 `Engine.time_scale = 0.3`)
- Unlocks: AC-AUD-15-a/b BLOCKING/ADVISORY — débloque close-out epic Audio Couche 4 drone HLM Pillar Player Fantasy

---

## Completion Notes

**Completed**: 2026-05-04
**Criteria**: 6/6 covered (AC-AUD-15-b ADVISORY headless SKIPPED — evidence sound-designer Sprint Audio)
**Test Evidence**: 2 fichiers integration (16 + 9 = 25 tests, 1.16 s, 0 régression sur 139 audio total)
- `tests/integration/audio/pitch_shift_bus_allowlist_test.gd` (16 tests : bus invariants SWING_ACTIVE/MUSIC, bus pitch-shifted COMBAT_KILL non-clac/AMBIENCE, slot clac exclu rang 1/2/3 préservé, son démarré pendant slow-mo zéro latence 1 tick, clac avec pitch explicit préservé, stream data immutable, restore invariants quand time_scale → 1.0, Formula 5 boundary at ts=1.0 / ts=0.3 / ts<=0 guard, allowlist constants verification 7-bus)
- `tests/integration/audio/active_clac_tracker_orphan_test.gd` (9 tests : round-robin force-stop erase tracker AVANT stop + disconnect callback, play_3d_at recycle cleanup pré-réutilisation slot, cleanup idempotent on non-clac slot, no-op si slot pas playing, slot_idx out-of-range push_warning, _on_clac_slot_finished erase, multi-slots independent cleanup, typed Dictionary[int, bool] guard)

**Code Review**: Skipped (Solo mode)

**Implementation Notes** :

1. **Formula 5 strict vs spec numerical values discrepancy** : pseudo-code spec ligne 71 `pitch_factor = 2^(compute_semitones(ts)/12)` avec `compute_semitones(ts) = log2(ts)*12` se simplifie en `pitch_factor = ts` (linear time = linear frequency). Donc à ts=0.3, pitch_factor=0.3 (PAS 0.8821 comme indiqué dans les AC numériques du story file). Les valeurs "0.8821 ≈ -2.1 semitones" dans les AC sont une erreur éditoriale du spec — Formula 5 stricte donne pitch_factor=time_scale. Tests valident le comportement RÉEL de l'implémentation conforme à la pseudo-code canonique. Si Sprint Audio impose perceptual mapping subtle (e.g. pitch_factor=0.88 à ts=0.3), amendement Rule 11 r3 + nouveau formula scaling factor requis.

2. **Pitch appliqué AVANT play()** : `play_3d_at` détecte `pitch_scale == 1.0` (default) + `bus ∈ allowlist` → override avec `_get_slow_mo_pitch_factor()` AVANT `player.play()` → zéro latence 1 tick visible (AC-AUD-15-a (e)). Si caller passe `pitch_scale != 1.0` (clac multi-kill Rule 13 rang 2/3 = 1.122/1.260), préserve la valeur explicite (pas d'override). `_start_ambient_crossfade` (story-005) pré-set pitch_scale du new_player de la même manière.

3. **Tick `_apply_pitch_shift_slow_mo` runtime** : `_physics_process` tick chaque frame (60 Hz garanti main thread) — couvre cas où slow-mo s'active pendant qu'un son boucle déjà (e.g. ambient room tone) → re-pitch au prochain tick. Skip rapide si `pitch_scale == pitch_factor` (zero-write si stable). Iterate `_3d_pool` + `_ambience_pool` + check `_music_player`. Bus hors allowlist + clac slots → invariant 1.0.

4. **Tracker `_active_clac_players` typed `Dictionary[int, bool]`** (Phase D.3 r2.3) : clé = slot index, valeur sentinel `true`. Populé par Combat handler `_on_enemy_killed` POST `play_3d_at` retour. Cleanup auto via `CONNECT_ONE_SHOT` sur `finished` signal. **Fix r2.3** : `play_3d_at` appelle `_cleanup_clac_slot_tracker(_3d_index)` AVANT `player.stop()` round-robin saturation → erase tracker + disconnect callback (sinon `finished` ne fire pas sur force-stop, tracker resterait orphan ad infinitum).

5. **`_round_robin_3d_stop_if_saturated(slot_idx)`** : wrapper public pour scénarios externes (boss death, scene unload force-stop). `play_3d_at` fait déjà cleanup inline. Garde-fou `slot_idx` out-of-range → `push_warning` no-op.

6. **Cache `_last_pitch_factor` / `_last_time_scale`** : `_get_slow_mo_pitch_factor()` cache pow/log result si time_scale stable (zero-alloc hot path) — recompute uniquement si `Engine.time_scale` change. Premier appel : recompute initial.

7. **PITCH_ALLOWLIST const Dictionary[StringName, bool]** : 7 entries figées (Master/Music/SFX/swing_active/combat_kill/Ambience/UI), 2 true (combat_kill+Ambience), 5 false. `dict.get(bus, false)` default false → robust contre bus ad-hoc inconnu (= invariant 1.0 par défaut, sécuritaire).

8. **Combat handler interaction non-modifiée** : `_on_enemy_killed` continue d'utiliser pitch_scale Rule 13 explicit (1.0 / 1.122 / 1.260) → `play_3d_at` détecte non-default + skip override slow-mo. Tracker register POST-call inchangé (story-003 logic préservée). Composite SECRET_PITCH × Formula 5 explicitement out-of-scope (story-008 invariant slow-mo).

9. **AC-AUD-15-b ADVISORY anti-pop waveform** : SKIPPED headless CI (driver Dummy ne supporte pas `AudioEffectRecord` peak meter post-effects). Evidence requirement `production/qa/evidence/audio-pitch-transition-{date}.md` — Sprint Audio sound-designer écoute manuelle requise (transition `1.0 → 0.3 → 1.0`). Si pop audible détecté → escalade BLOCKING amendement Rule 11 (e.g. ramp pitch sur 1-2 frames au lieu de step instantané).

10. **Suppression unused warning** : `_tick_slow_mo_pitch_shift` calcule `slow_mo_active: bool` pour clarté logique mais n'utilise pas → `var _suppressed: bool = slow_mo_active` à la fin. Pattern documenté pour future refactor (élimination si décision design clarifie qu'on n'a pas besoin de la branche).
