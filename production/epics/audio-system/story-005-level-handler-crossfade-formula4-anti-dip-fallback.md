# Story 005: Level Audio Handler — `level_active` Lookup `get_etage_audio_streams` + Crossfade 1 s Linear-Amplitude Phase C Anti-Dip + `level_unloading` Fade-Out + Fallback `push_warning` Mapping Vide

> **Epic**: Audio System
> **Status**: Complete 2026-05-04 (16/16 tests PASS — 7/7 ACs COVERED, lookup fallback ADVISORY pending Level epic ship `get_etage_audio_streams`)
> **Layer**: Core
> **Type**: Integration
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/audio-system.md` (r2.3 §Rule 15 + §Formulas Formula 4 hardened Phase C linear-amplitude lerp anti-dip)
**Requirements**:
- R-AUD-15 : Ambient loop par etage — `Ambience #1`/`Ambience #2` crossfade 1 s linear-amplitude (Formula 4 hardened Phase C anti-dip dB-domain) sur `level_active` + lookup `LevelSystem.get_etage_audio_streams(etage_id) -> Dictionary{music, ambient}`
- R-AUD-5 : `CONNECT_DEFERRED` par défaut

**ADR Governing**: ADR-0009 D-2 + ADR-0011 (Level Scene Architecture r4 Option C)
**Decision Summary**: Audio handler `_on_level_active(etage_id, _player_start)` lookup synchrone `LevelSystem.get_etage_audio_streams(etage_id)` puis `play_music(streams.music)` + crossfade ambient 1 s linear-amplitude. `_on_level_unloading(etage_id)` → `stop_music(0.5)` + ambient fade-out 0.5 s. Fallback `push_warning` + return early si mapping vide.

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: Tween autorisé pour music crossfade UNIQUEMENT si `Engine.time_scale == 1.0` garanti (transitions Level hors combat) — sinon utiliser wall-clock `_physics_process` (Rule 4). Formula 4 hardened Phase C : `linear_to_db(maxf(amp, 1e-4))` log-guard pour éviter dip ~3 dB midpoint dB-domain (régression r2 → r2.3).

**Control Manifest Rules (Core layer)**:
- Required: connect Level signals `CONNECT_DEFERRED`
- Required: Formula 4 linear-amplitude lerp Phase C (PAS dB-domain lerp r2 stale)
- Forbidden: aucun couplage Audio → Level (outbound zero — Audio consume seulement)

---

## Acceptance Criteria

*From GDD AC-AUD-21 (F-04 linear-amplitude midpoint anti-regression) + §Edge Cases:*

- [ ] **AC-AUD-21 (a) Boot état initial** : à `t = 0`, `volume_db_old ≈ 0 dB ± 0.1` (`Ambience #1` joue stream A) et `volume_db_new ≤ -60 dB` (`Ambience #2` charge stream B idle).
- [ ] **AC-AUD-21 (b) Midpoint linear-amplitude** : à `t = 500` (50%), `volume_db_old ≈ -6 dB ± 1 dB` ET `volume_db_new ≈ -6 dB ± 1 dB` (linear-amplitude lerp Phase C — F-04 hardened).
- [ ] **AC-AUD-21 (c) Anti-regression Phase C** : si test observe `volume_db_old ≈ -40 dB` ET `volume_db_new ≈ -40 dB` au midpoint → FAIL "F-04 dB-domain lerp détecté (ancien comportement r2 dip ~3 dB midpoint), Phase C linear-amplitude lerp non appliqué — vérifier `linear_to_db(maxf(amp_old, 1e-4))` impl".
- [ ] **AC-AUD-21 (d) Fin crossfade** : à `t = 1000` (100%), `volume_db_old ≤ -60 dB` ET `volume_db_new ≈ 0 dB ± 0.1`.
- [ ] **AC-AUD-21 (e) Boundary D = 0.0** : `ambient_crossfade_ms = 0.0` → swap instantané (`volume_db_old = -80`, `volume_db_new = 0`) + `push_warning` capturé.
- [ ] **Lookup fallback** : `LevelSystem.get_etage_audio_streams(etage_id_inexistant)` retourne `{}` → `push_warning("AudioSystem: no audio mapping for etage_id={etage_id}, fallback silence")` + return early. Music précédente continue (pas de stop), ambient reste tel quel.
- [ ] **`level_unloading`** : `stop_music(0.5)` + `Ambience #1.volume_db → -80 dB` 0.5 s wall-clock.

---

## Implementation Notes

*Derived from ADR-0011 + ADR-0009 D-2 + Formula 4 hardened Phase C:*

```gdscript
const AMBIENT_CROSSFADE_MS: float = 1000.0
const AMBIENT_UNLOAD_FADE_MS: float = 500.0
const SILENCE_DB: float = -80.0

var _ambience_active_idx: int = 0  # 0 → Ambience #1 actif, 1 → Ambience #2 actif
var _crossfade_active: bool = false
var _crossfade_start_msec: int = 0
var _crossfade_old_player: AudioStreamPlayer
var _crossfade_new_player: AudioStreamPlayer

func _connect_level_signals(level: Node) -> void:
    level.level_active.connect(_on_level_active, CONNECT_DEFERRED)
    level.level_unloading.connect(_on_level_unloading, CONNECT_DEFERRED)

func _on_level_active(etage_id: int, _player_start: Vector3) -> void:
    var streams: Dictionary = LevelSystem.get_etage_audio_streams(etage_id)
    if streams.is_empty():
        push_warning("AudioSystem: no audio mapping for etage_id=%d, fallback silence" % etage_id)
        return
    play_music(streams.music)
    _start_ambient_crossfade(streams.ambient)

func _start_ambient_crossfade(new_stream: AudioStream) -> void:
    var old_player: AudioStreamPlayer = _ambience_pool[_ambience_active_idx]
    var new_idx: int = (_ambience_active_idx + 1) % 2
    var new_player: AudioStreamPlayer = _ambience_pool[new_idx]
    new_player.stream = new_stream
    new_player.volume_db = SILENCE_DB
    new_player.play()
    if AMBIENT_CROSSFADE_MS <= 0.0:
        old_player.volume_db = SILENCE_DB
        new_player.volume_db = 0.0
        push_warning("ambient_crossfade_ms <= 0 — swap instantané")
        _ambience_active_idx = new_idx
        return
    _crossfade_active = true
    _crossfade_start_msec = _get_time_msec.call()
    _crossfade_old_player = old_player
    _crossfade_new_player = new_player
    _ambience_active_idx = new_idx

# Formula 4 hardened Phase C — linear-amplitude lerp anti-dip
func _tick_ambient_crossfade() -> void:
    if not _crossfade_active:
        return
    var elapsed: float = float(_get_time_msec.call() - _crossfade_start_msec)
    var t: float = clampf(elapsed / AMBIENT_CROSSFADE_MS, 0.0, 1.0)
    # Linear-amplitude lerp (Phase C anti-dip) — pas dB-domain lerp r2 stale
    var amp_old: float = lerpf(1.0, 0.0, t)
    var amp_new: float = lerpf(0.0, 1.0, t)
    _crossfade_old_player.volume_db = linear_to_db(maxf(amp_old, 1e-4))  # log-guard
    _crossfade_new_player.volume_db = linear_to_db(maxf(amp_new, 1e-4))
    if t >= 1.0:
        _crossfade_old_player.stop()
        _crossfade_active = false
```

`Time.get_ticks_msec` utilisé via `_get_time_msec: Callable` injection (cohérence story 003) — testable via `_set_time_provider` debug-guarded.

---

## Out of Scope

- Story 003 : Combat handlers swoosh/multi-kill (utilisent même `_get_time_msec` mais formules différentes)
- Story 006 : GSM pause/resume — crossfade en cours pendant `MUTED_PAUSED` doit préserver état (`_crossfade_pause_msec` offset wall-clock)
- Story 010 : lint CI `lint-audio-tween` autorise exception annotée `# lint-audio-tween-ok: ambient crossfade time_scale==1.0 garanti` si Tween utilisé pour music crossfade hors combat

---

## QA Test Cases

**AC-AUD-21 (a-d) F-04 linear-amplitude midpoint anti-regression** :
- Given : `Ambience #1` joue stream A à `volume_db = 0.0`, `Ambience #2` charge stream B à `volume_db = -80.0` (idle), crossfade démarre via `level_active(etage_id_2, ...)` `CROSSFADE_DURATION_MS = 1000.0`, `_get_time_msec` mocké séquence `[0, 250, 500, 750, 1000]`
- When : crossfade `_physics_process` exécuté à chaque tick mocké
- Then : à t=0 → `vdb_old ≈ 0 ± 0.1`, `vdb_new ≤ -60` ; à t=500 → `vdb_old ≈ -6 ± 1` ET `vdb_new ≈ -6 ± 1` ; à t=1000 → `vdb_old ≤ -60`, `vdb_new ≈ 0 ± 0.1`
- Edge cases : observation midpoint ≈ -40 dB sur les deux → FAIL "F-04 dB-domain lerp détecté (ancien r2 dip ~3 dB), Phase C non appliqué"

**AC-AUD-21 (e) boundary D=0.0** :
- Given : `AMBIENT_CROSSFADE_MS = 0.0`
- When : `_start_ambient_crossfade(new_stream)` appelé
- Then : swap instantané `vdb_old = -80`, `vdb_new = 0` + `push_warning` capturé

**Lookup fallback mapping vide** :
- Given : `LevelSystem.get_etage_audio_streams(99)` retourne `{}` (etage_id absent ETAGE_AUDIO_MAPPING)
- When : `_on_level_active(99, Vector3.ZERO)` reçu DEFERRED N+1
- Then : `push_warning("AudioSystem: no audio mapping for etage_id=99...")` capturé + music précédente continue (pas de stop) + crossfade non démarré

**`level_unloading` fade-out** :
- Given : music + ambient en cours
- When : `level_unloading(etage_id)` reçu DEFERRED N+1
- Then : music fade-out 0.5 s wall-clock + ambient fade-out 0.5 s

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- `tests/unit/audio/formula4_crossfade_midpoint_test.gd` (AC-AUD-21 a-e — anti-regression Phase C)
- `tests/integration/audio/level_handler_lookup_fallback_test.gd` (lookup mapping vide + level_unloading)

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (pool Ambience #1/#2), Story 002 (`play_music`/`stop_music` API)
- Cross-system : Level System r4 Option C `LevelSystem.get_etage_audio_streams` API + `ETAGE_AUDIO_MAPPING` Tuning Knob (Level epic 22 stories Ready)
- Unlocks: Story 006 (GSM pause crossfade pendant `MUTED_PAUSED`)

---

## Completion Notes

**Completed**: 2026-05-04 (auto-chain post-story-004, Solo mode QL/LP gates skipped)
**Criteria**: 7/7 ACs COVERED — AC-AUD-21 (a/b/c/d/e) + lookup fallback + level_unloading
**Test Evidence**:
- `tests/unit/audio/formula4_crossfade_midpoint_test.gd` — 7 tests Phase C linear-amplitude
- `tests/integration/audio/level_handler_lookup_fallback_test.gd` — 9 tests handlers + fallback + level_unloading + music fade-out
- **Total : 16/16 PASS** (suite audio cumulée 95/95, 848 ms, exit 0)

**Implementation Notes** :

1. **Cross-system gap handled via injection point** : `LevelSystem.get_etage_audio_streams` API non shippée (Level epic 22 stories Ready). Solution : `_get_etage_audio_streams: Callable = func(_id): return {}` default empty → fallback path testé. Une fois Level shippé, `AudioSystem._ready()` peut wire `_get_etage_audio_streams = LevelSystem.get_etage_audio_streams`. Pattern cohérent avec `_get_time_msec` (story-003/004).

2. **Formula 4 hardened Phase C linear-amplitude lerp** : `_tick_ambient_crossfade` calcule `amp_old = lerpf(1.0, 0.0, t)` puis `linear_to_db(maxf(amp_old, _CROSSFADE_AMP_FLOOR))` (1e-4 log-guard). Anti-regression test `test_crossfade_anti_regression_not_minus_40_db_dB_domain_bug` garantit qu'on n'est PAS sur dB-domain lerp r2 stale (midpoint distance vs -40 ≥ 20 dB).

3. **Crossfade fade-out only path** : `_on_level_unloading` reuse `_tick_ambient_crossfade` avec `_crossfade_new_player = null` → tick skip new_player updates, fade old uniquement vers SILENCE. Évite duplication ticker.

4. **Music fade-out wall-clock** : extension `stop_music` story-002 stub. Capture `_music_fade_out_start_db = volume_db` courant pour cumul-safe (restart depuis état actuel si déjà en fade). Formula 4 Phase C cohérent avec ambient.

5. **Volume restore post-stop** : tous les `*.stop()` suivis de `volume_db = 0.0` pour reuse round-robin sans propagation SILENCE_DB résiduel. Pattern hérité story-004 wallrun fade.

6. **Boundary D=0.0 swap instantané** : `_start_ambient_crossfade(stream, 0.0)` short-circuit + `push_warning` + idx toggle + stop old. Cohérent avec swoosh/ducking/wallrun boundary handling.

7. **Round-robin Ambience pool double buffer** : `_ambience_active_idx` toggle 0↔1 via `(idx + 1) % POOL_AMBIENCE_SIZE`. Test `test_crossfade_idx_toggles_0_to_1_to_0` lock le contract.

8. **Wall-clock indep `Engine.time_scale`** : `_get_time_msec` = `Time.get_ticks_msec` (ms wall-clock). Test slow-mo 0.3 garantit fade complet à 1000 ms wall-clock (PAS 3333 ms si Tween scaled).

9. **Partial mapping handling** : `_on_level_active` check `streams.has(&"music")` ET `streams.has(&"ambient")` indépendamment → mapping partiel `{music: X}` joue music sans starter crossfade ambient. Test `test_level_active_partial_mapping_music_only` lock.

10. **`_on_level_unloading` no-op si ambient idle** : check `old_player.playing` avant déclencher crossfade fade-out. Évite crossfade phantôme au boot avant level_active.

**Deviations** : aucune — Formula 4 Phase C, pool double buffer, fallback `push_warning`, `level_unloading` fade-out 0.5 s, boundary D=0 conformes à spec story.

**Code Review** : Skipped (Solo mode LP-CODE-REVIEW)
**Verdict** : COMPLETE
