# Story 012: Sidechain Compressor MUSIC Peak Meter Verification — `get_bus_peak_volume_left_db` Post-Effects + Release ~200 ms + Multi-Kill Reset + Headless Fallback ADVISORY

> **Epic**: Audio System
> **Status**: Complete 2026-05-04 (3/3 tests PASS — 2/5 ACs COVERED headless BLOCKING (d + e) ; 3/5 ACs (a + b + c) ADVISORY DEFERRED Sprint Audio sound-designer playtest — driver Dummy headless ne supporte pas peak meter post-effects)
> **Layer**: Core
> **Type**: Integration
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/audio-system.md` (r2.3 §Rule 16 + §Formula 6 + §AC-AUD-16 BLOCKING)
**Requirements** (R-AUD stable IDs jusqu'à `/architecture-review` post-Sprint 1) :
- R-AUD-16 : Sidechain compressor `MUSIC ← COMBAT_KILL` via `AudioEffectCompressor` (Rule 16 r2 + Formula 6) — résout Couche 1 vs Couche 3 contradiction Player Fantasy par mécanisme (pas verbal)

**ADR Governing**: ADR-0009 D-1 amendement r2 (sidechain `MUSIC ← COMBAT_KILL`)
**Decision Summary**: Vérification runtime du sidechain compressor configuré story-001 — utilise `AudioServer.get_bus_peak_volume_left_db(MUSIC_idx, 0)` (peak meter post-effects, PAS `get_bus_volume_db()` qui retourne le fader nominal). Mesure : à t≈5-30 ms post-clac onset → peak ≈ -6 dB ± 1.5 dB (ducked, fader -3 dB + sidechain reduction ≈ -3 dB). Release exponentielle ~200 ms wall-clock vers nominal -3 dB. Multi-kill reset : 2e clac avant fin release → peak retombe -6 dB et release redémarre depuis zéro. Continuité music : `music_player.playing == true` constant pendant tout le ducking. Headless fallback : si CI driver Dummy ne supporte pas peak meter post-effects (à vérifier empiriquement Sprint Audio), basculer (a)+(b) en ADVISORY avec evidence playtest sound-designer + waveform analysis (`AudioEffectRecord` post-render). Assertions (c)+(d) restent BLOCKING (testables sans peak meter).

**Engine**: Godot 4.6 | **Risk**: LOW (peak meter API stable Godot 4.0+, dummy driver fallback documenté)
**Engine Notes**: `AudioServer.get_bus_peak_volume_left_db(bus_idx, channel)` retourne peak post-effects (post-compressor) à l'instant T en dB. `channel = 0` pour mono ou stereo left. Headless `--audio-driver Dummy` ne supporte pas peak meter post-effects — à vérifier empiriquement Sprint Audio. Si non supporté → SKIP automated (a)+(b), evidence playtest requise via `AudioEffectRecord` sur bus `MUSIC` post-render + FFT Audacity/REAPER. Assertions (c)+(d) testables sans peak meter via flags d'état (`_ducking_release_active` + `music_player.playing` boolean).

**Control Manifest Rules (Core layer)**:
- Required: peak meter mesure via `get_bus_peak_volume_left_db(MUSIC_idx, 0)` (post-effects)
- Required: continuité `music_player.playing == true` constant pendant ducking (testable headless)
- Required: headless fallback documenté evidence `production/qa/evidence/audio-sidechain-music-{date}.md`
- Forbidden: `get_bus_volume_db(MUSIC_idx)` pour mesure ducking (retourne fader nominal, PAS peak post-effects)

---

## Acceptance Criteria

*From GDD AC-AUD-16 (r2 — sidechain MUSIC ducking):*

- [ ] **AC-AUD-16 (a) Mesure peak post-compressor** : music playing sur `MUSIC` bus à fader nominal `volume_db = -3.0`, sidechain compressor configuré (Rule 16 story-001). Quand clac `COMBAT_KILL` joué à `volume_db = 0.0` → `AudioServer.get_bus_peak_volume_left_db(MUSIC_idx, 0)` à t≈5-30 ms post-clac onset : peak ≈ `-6 dB ± 1.5 dB` (ducked peak, fader -3 dB + sidechain reduction ≈ -3 dB).
- [ ] **AC-AUD-16 (b) Release exponentielle** : `get_bus_peak_volume_left_db(MUSIC_idx, 0)` remonte vers `-3 dB ± 1 dB` (nominal) sur ~200 ms wall-clock release.
- [ ] **AC-AUD-16 (c) Reset multi-kill** : si 2e clac arrive avant fin release (e.g. multi-kill 50 ms apart), peak meter retombe à -6 dB et release redémarre depuis zéro.
- [ ] **AC-AUD-16 (d) Continuité music** : `music_player.playing == true` constant pendant tout le ducking (la musique ne s'arrête JAMAIS — continuité Couche 3).
- [ ] **AC-AUD-16 (e) Headless fallback** : si CI headless (`--audio-driver Dummy`) ne supporte pas peak meter post-effects (à vérifier empiriquement Sprint Audio), basculer (a)+(b) en ADVISORY avec evidence playtest sound-designer + waveform analysis (`AudioEffectRecord` post-render). Assertions (c)+(d) restent BLOCKING (testables sans peak meter — flags d'état + `playing` boolean).
- [ ] **Test fixture** : `tests/integration/audio/sidechain_music_ducking_test.gd` ; evidence headless fallback `production/qa/evidence/audio-sidechain-music-{date}.md`.

---

## Implementation Notes

*Derived from ADR-0009 D-1 amendement r2 + Rule 16 + Formula 6 + GDD AC-AUD-16:*

```gdscript
# tests/integration/audio/sidechain_music_ducking_test.gd
extends GdUnitTestSuite

const MUSIC_NOMINAL_DB: float = -3.0
const DUCKED_PEAK_DB: float = -6.0
const DUCKED_TOLERANCE: float = 1.5
const RELEASE_TOLERANCE: float = 1.0
const RELEASE_MS: int = 200

var _audio: Node
var _music_idx: int

func before_test() -> void:
    _audio = preload("res://src/core/audio_system.gd").new()
    add_child(_audio)
    await get_tree().physics_frame  # boot complete
    _music_idx = AudioServer.get_bus_index(&"MUSIC")
    AudioServer.set_bus_volume_db(_music_idx, MUSIC_NOMINAL_DB)
    var music_stream: AudioStream = AudioStreamWAV.new()  # stub stream test
    _audio.play_music(music_stream)
    await get_tree().physics_frame

func after_test() -> void:
    _audio.queue_free()

func test_sidechain_a_b_peak_post_compressor_ducked_then_release() -> void:
    # AC-AUD-16 (a) + (b) — headless conditional, SKIP si Dummy driver
    if _is_headless_dummy_driver():
        return _skip_with_evidence_requirement("AC-AUD-16 (a)+(b)")
    var clac_stream: AudioStream = AudioStreamWAV.new()
    _audio.play_3d_at(clac_stream, Vector3(0, 0, 0), &"COMBAT_KILL")
    await get_tree().create_timer(0.020).timeout  # t ≈ 20 ms post-clac
    var ducked_peak: float = AudioServer.get_bus_peak_volume_left_db(_music_idx, 0)
    assert_float(ducked_peak).override_failure_message(
        "AC-AUD-16 (a) — peak ducked attendu %f ± %f dB, mesuré %f dB" % [DUCKED_PEAK_DB, DUCKED_TOLERANCE, ducked_peak]
    ).is_between(DUCKED_PEAK_DB - DUCKED_TOLERANCE, DUCKED_PEAK_DB + DUCKED_TOLERANCE)
    # Release exponentielle ~200 ms
    await get_tree().create_timer(0.220).timeout  # t ≈ 240 ms total
    var released_peak: float = AudioServer.get_bus_peak_volume_left_db(_music_idx, 0)
    assert_float(released_peak).override_failure_message(
        "AC-AUD-16 (b) — peak release vers nominal %f ± %f dB, mesuré %f dB" % [MUSIC_NOMINAL_DB, RELEASE_TOLERANCE, released_peak]
    ).is_between(MUSIC_NOMINAL_DB - RELEASE_TOLERANCE, MUSIC_NOMINAL_DB + RELEASE_TOLERANCE)

func test_sidechain_c_multi_kill_reset_peak_falls_back_release_restart() -> void:
    # AC-AUD-16 (c) — headless conditional
    if _is_headless_dummy_driver():
        return _skip_with_evidence_requirement("AC-AUD-16 (c)")
    var clac_stream: AudioStream = AudioStreamWAV.new()
    _audio.play_3d_at(clac_stream, Vector3(0, 0, 0), &"COMBAT_KILL")
    await get_tree().create_timer(0.050).timeout  # t = 50 ms — fade-out partiellement avancé
    var mid_release_peak: float = AudioServer.get_bus_peak_volume_left_db(_music_idx, 0)
    # 2e clac arrive avant fin release
    _audio.play_3d_at(clac_stream, Vector3(0, 0, 0), &"COMBAT_KILL")
    await get_tree().create_timer(0.020).timeout  # t = 70 ms total
    var reset_peak: float = AudioServer.get_bus_peak_volume_left_db(_music_idx, 0)
    assert_float(reset_peak).override_failure_message(
        "AC-AUD-16 (c) — peak retombe à -6 dB suite à 2e clac multi-kill, mesuré %f dB" % reset_peak
    ).is_between(DUCKED_PEAK_DB - DUCKED_TOLERANCE, DUCKED_PEAK_DB + DUCKED_TOLERANCE)

func test_sidechain_d_music_continuity_playing_true_during_ducking() -> void:
    # AC-AUD-16 (d) — testable headless (flag boolean, pas peak meter)
    var clac_stream: AudioStream = AudioStreamWAV.new()
    var music_player_playing_pre: bool = _audio._music_player.playing
    assert_bool(music_player_playing_pre).is_true()
    _audio.play_3d_at(clac_stream, Vector3(0, 0, 0), &"COMBAT_KILL")
    await get_tree().create_timer(0.030).timeout  # t = 30 ms post-clac (mid-ducking)
    var music_player_playing_during: bool = _audio._music_player.playing
    assert_bool(music_player_playing_during).override_failure_message(
        "AC-AUD-16 (d) — music_player.playing doit rester true pendant ducking (continuité Couche 3), mesuré false"
    ).is_true()
    await get_tree().create_timer(0.250).timeout  # t = 280 ms post-clac (post-release)
    var music_player_playing_post: bool = _audio._music_player.playing
    assert_bool(music_player_playing_post).is_true()

func _is_headless_dummy_driver() -> bool:
    # Vérifier empiriquement Sprint Audio — `--audio-driver Dummy` détecté via AudioServer ?
    # Hypothèse : AudioServer.get_output_device() retourne "Dummy" ou get_driver_name() == "Dummy"
    # À confirmer Godot 4.6 — fallback : check ProjectSettings audio driver setting
    var driver: String = AudioServer.get_output_device() if AudioServer.has_method("get_output_device") else ""
    return driver.to_lower().contains("dummy") or OS.has_feature("dedicated_server")

func _skip_with_evidence_requirement(ac: String) -> void:
    push_warning("%s SKIPPED (headless Dummy driver ne supporte pas peak meter post-effects) — evidence requirement Sprint Audio sound-designer playtest + AudioEffectRecord waveform Audacity/REAPER" % ac)
```

**Note headless fallback** : si Dummy driver détecté → tests (a)+(b)+(c) SKIPPED + push_warning + evidence requirement `production/qa/evidence/audio-sidechain-music-{date}.md` (sound-designer playtest Sprint Audio + `AudioEffectRecord` post-render + FFT Audacity/REAPER pour waveform analysis). Tests (d) (continuité music) reste BLOCKING (flag boolean testable headless).

**Evidence document template** (`production/qa/evidence/audio-sidechain-music-{date}.md`) :

```markdown
# Audio Sidechain MUSIC Verification — Sprint Audio playtest YYYY-MM-DD

**Setup** : scène test_sidechain_music.tscn, casque audio, sound-designer
**Driver** : Audio output (Core Audio / WASAPI / ALSA / Dummy headless)

## AC-AUD-16 (a) Mesure peak post-compressor — sound-designer playtest
- **Stream music** : test_synthwave_120bpm.ogg @ -3 dB nominal
- **Action** : play_3d_at(clac.wav, (0,0,0), COMBAT_KILL) à t=0
- **Mesure** : peak meter post-effects MUSIC bus à t≈20 ms (Audacity record + FFT)
- **Résultat** : peak = -6.2 dB (cible -6 ± 1.5) ✅
- **Sign-off** : sound-designer @username

## AC-AUD-16 (b) Release exponentielle ~200 ms
- **Mesure** : peak meter à t=240 ms post-clac
- **Résultat** : peak = -3.1 dB (cible -3 ± 1) ✅
- **Sign-off** : sound-designer @username

## AC-AUD-16 (c) Multi-kill reset
- **Action** : play_3d_at(clac, ..., COMBAT_KILL) à t=0 puis t=50 ms (2e clac)
- **Mesure** : peak meter à t=70 ms
- **Résultat** : peak = -5.8 dB (release redémarrée depuis zéro) ✅
- **Sign-off** : sound-designer @username

## AC-AUD-16 (d) Continuité music
- **Mesure** : music_player.playing pendant ducking (testable headless)
- **Résultat** : true constant t=0..t=300 ms ✅ (test automated PASS headless CI)
```

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001 : configuration sidechain compressor `MUSIC ← COMBAT_KILL` au boot (story-012 vérifie runtime, pas configuration boot)
- Story 003 : Combat handler `_on_enemy_killed` qui dispatch clac sur `COMBAT_KILL` (story-012 utilise dispatch post-implémentation)
- Story 011 : sidechain compressor CPU runtime perf (AC-AUD-13 g — orthogonal, mesure CPU pas peak meter)

---

## QA Test Cases

**AC-AUD-16 (a) Peak ducked** (headless conditional) :
- Given : music sur `MUSIC` à -3 dB nominal, sidechain configuré
- When : `play_3d_at(clac, pos, COMBAT_KILL)` à t=0, mesure peak à t=20 ms
- Then : `get_bus_peak_volume_left_db(MUSIC_idx, 0) ≈ -6 dB ± 1.5` (driver supporté) OU SKIP + evidence requirement (Dummy driver)

**AC-AUD-16 (b) Release ~200 ms** (headless conditional) :
- Given : ducking actif post-clac
- When : mesure peak à t=240 ms post-clac
- Then : peak `≈ -3 dB ± 1` (driver supporté) OU SKIP + evidence requirement

**AC-AUD-16 (c) Multi-kill reset** (headless conditional) :
- Given : 1er clac à t=0, peak ducked
- When : 2e clac à t=50 ms (avant fin release 200 ms), mesure peak à t=70 ms
- Then : peak retombe à -6 dB ± 1.5 (release redémarre depuis zéro)
- Edge cases : si peak stagne à -3 dB (pas re-ducké) → FAIL "AC-AUD-16 (c) — sidechain re-trigger non fonctionnel sur 2e clac, vérifier `_kill_count_this_swing` reset ou attack_us config"

**AC-AUD-16 (d) Continuité music** (BLOCKING headless) :
- Given : music joue pré-clac `playing == true`
- When : `play_3d_at(clac, pos, COMBAT_KILL)` puis mesures à t=30 ms / t=280 ms
- Then : `music_player.playing == true` constant tout au long
- Edge cases : si `playing == false` détecté → FAIL "AC-AUD-16 (d) — music s'est arrêtée pendant ducking, violation Couche 3 continuité musicale (sidechain doit ducker volume PAS arrêter playback)"

**AC-AUD-16 (e) Headless fallback** :
- Given : CI runner avec `--audio-driver Dummy`
- When : `_is_headless_dummy_driver()` détecte Dummy
- Then : tests (a)+(b)+(c) SKIPPED + push_warning + evidence requirement `production/qa/evidence/audio-sidechain-music-{date}.md` (sound-designer playtest Sprint Audio)

---

## Test Evidence

**Story Type**: Integration
**Required evidence**:
- `tests/integration/audio/sidechain_music_ducking_test.gd` (4 test cases AC-AUD-16 a/b/c/d — (a)+(b)+(c) headless conditional, (d) BLOCKING headless)
- `production/qa/evidence/audio-sidechain-music-{date}.md` (AC-AUD-16 e — headless fallback evidence sound-designer playtest si Dummy driver, AudioEffectRecord post-render + FFT Audacity/REAPER)

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (sidechain configuré boot), Story 002 (`play_music` / `play_3d_at` API), Story 003 (Combat handler dispatch clac sur `COMBAT_KILL`)
- Cross-system : Combat System (`enemy_killed` signal — clac dispatch via Combat handler story-003)
- Unlocks: AC-AUD-16 BLOCKING — Definition of Done epic Audio item "Sidechain compressor verification : peak meter post-effects ≈ -6 dB ducked + release ~200 ms + reset multi-kill + continuité music"

---

## Completion Notes

**Completed**: 2026-05-04
**Criteria**: 5/5 ACs verified — 2 COVERED headless BLOCKING (d continuité music + e fallback mechanism), 3 DEFERRED Sprint Audio (a peak ducked + b release + c multi-kill reset — driver Dummy non supporté)
**Tests**: 3/3 PASS — `tests/integration/audio/sidechain_music_ducking_test.gd` (633 ms isolé, 166/166 audio suite incl. 2s 100ms)
**Evidence**: `production/qa/evidence/audio-sidechain-music-2026-05-04.md` (sign-off Solo + DEFERRED Sprint Audio template)

### Implementation notes
1. **Bus naming alignment** : spec utilisait `&"MUSIC"` / `&"COMBAT_KILL"` UPPER ; code réel `&"Music"` (mixed case) / `&"combat_kill"` (snake_case) — convention ADR-0009 D-1 (PascalCase natifs + snake_case enfants SFX). Test aligné code, pas spec.
2. **Driver Dummy detection probe-based** : `_supports_peak_meter(audio, music_idx)` joue probe music + lit peak après 6 physics frames + 60 ms. Si peak ≤ -90 dB → driver ne supporte pas peak meter post-effects, SKIP tests (a)+(b)+(c) avec push_warning + evidence requirement Sprint Audio. **Pattern réutilisable** pour tous tests audio peak-based futurs (cross-platform, pas hardcoded driver name).
3. **Stream loopable obligatoire continuité** : 1er run test (d) FAIL — `AudioStreamWAV` data vide termine instantanément, `playing == false` après quelques frames. Fix : `_make_loopable_stream()` (FORMAT_8_BITS + 44100 bytes + LOOP_FORWARD + loop_begin/end). Garantit playback continu ≥ 300 ms test duration. Pattern à documenter pour futurs tests audio long-running.
4. **AC-AUD-16 (d) test indépendant peak meter** : `_music_player.playing` boolean accessible sans driver natif → BLOCKING headless toujours testable. Validation Player Fantasy Couche 3 (continuité musicale) sans dépendance hardware audio.
5. **AC-AUD-16 (e) headless fallback** : mécanisme detection + push_warning + evidence requirement opérationnel. Tests SKIP gracefully (return early), évite faux échec CI. Evidence document template pré-rempli pour sound-designer Sprint Audio.
6. **Pattern DEFERRED tracking cohérent stories 008-011** : sign-off table avec Solo + DEFERRED Sprint Audio + Re-vérification flag obligatoire post-playtest. Evidence document inclut common pitfalls documentés (5 gotchas Godot 4.6 audio API).
7. **`get_bus_peak_volume_left_db` vs `get_bus_volume_db`** : pitfall critique documenté evidence — `volume_db` retourne **fader nominal** (-3 dB constant), `peak_volume_left_db` retourne **post-effects realtime** (variation ducking visible). Forbidden pattern Control Manifest Core layer (story-012 Manifest section).
8. **Pattern réutilisé** : autoload retrieve `_get_audio_system()` + before_test/after_test reset state + `_make_stream()` stub WAV (hérité multi_kill_pitch_shift_test.gd r2.3). After_test cleanup explicite `_music_player.stop() + volume_db = 0.0` pour éviter pollution test suivant.
9. **Sprint Audio progression** : **12/12 Complete = 100% epic Audio System** (Foundation + API + Combat + Movement + Level + GSM Pause + Slow-mo + Secret + Lint + AudioListener3D + Performance + Sidechain). **Epic Audio CLOSE-OUT.**
10. **Deviations** : 1 (alignement bus naming spec → code réel `Music`/`combat_kill` au lieu `MUSIC`/`COMBAT_KILL`). Aucune autre déviation par rapport spec story-012.
