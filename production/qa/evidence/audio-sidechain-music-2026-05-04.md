# Audio Sidechain MUSIC Verification — Story-012 — 2026-05-04

> **Story** : `production/epics/audio-system/story-012-sidechain-music-peak-meter-verification-headless-fallback.md`
> **ADR Governing** : ADR-0009 D-1 amendement r2 (sidechain `MUSIC ← combat_kill`)
> **Mode** : Solo dev (Claude assist Sprint Audio story-012)
> **Date** : 2026-05-04

---

## Setup

| Field | Value |
|-------|-------|
| Engine | Godot 4.6 |
| Runner | `godot --headless --script GdUnitCmdTool.gd` |
| Audio driver runtime | **Dummy headless** (auto-detected via probe `_supports_peak_meter` → peak ≤ -90 dB) |
| Test framework | GdUnit4 v5 |
| Test fixture | `tests/integration/audio/sidechain_music_ducking_test.gd` (3 test cases) |

**Compressor configuration (story-001 boot)** :
- Bus : `Music` (idx auto-resolved via `AudioServer.get_bus_index(&"Music")`)
- Effect : `AudioEffectCompressor` ; `threshold = -24.0` ; `ratio = 4.0` ; `attack_us = 5000` (5 ms) ; `release_ms = 200.0` ; `sidechain = "combat_kill"` (cast String, gotcha Godot 4.6)
- Idempotent guard : skip add si compressor déjà présent (R-AUD-20)

---

## Verdict per AC

### AC-AUD-16 (a) Mesure peak post-compressor — ⏸ ADVISORY DEFERRED

**Status headless** : SKIPPED automated (driver Dummy ne supporte pas peak meter post-effects ; probe `AudioServer.get_bus_peak_volume_left_db` retourne ≤ -90 dB sur music playing — pas de mix engine actif).

**Detection mecanism** : `_supports_peak_meter(audio, music_idx)` joue probe music sur Music bus, attend 6 physics frames + 60 ms wall-clock, puis lit peak. Seuil > -90 dB pour considérer driver compatible.

**Headless fallback** : push_warning + redirect evidence requirement → Sprint Audio sound-designer playtest (Core Audio macOS / WASAPI Windows / ALSA Linux) avec :
1. Stream music synthwave 120 BPM @ -3 dB nominal sur bus `Music`
2. `play_3d_at(clac.wav, Vector3.ZERO, &"combat_kill")` à t=0
3. Capture peak meter post-compressor MUSIC à t≈20 ms via `AudioEffectRecord` (insert sur Music bus post-compressor) ou Audacity loopback
4. FFT analysis Audacity/REAPER → peak attendu **-6 dB ± 1.5** (ducked)
5. Sign-off : sound-designer @TBD

**Sprint Audio TBD** : sound-designer playtest dédiée (post-Sprint MVP).

### AC-AUD-16 (b) Release exponentielle ~200 ms — ⏸ ADVISORY DEFERRED

**Status headless** : SKIPPED (même raison driver Dummy).

**Headless fallback** : Sprint Audio sound-designer playtest :
1. Suivi protocole AC-AUD-16 (a) précédent
2. Capture peak meter à t=240 ms post-clac
3. Peak attendu **-3 dB ± 1** (release exponentielle terminée, retour nominal)
4. Validation : `release_ms = 200.0` configuré story-001 → trajectoire courbe exp e^(-t/τ) avec τ = release_ms/3 ≈ 67 ms (5τ ≈ 335 ms pour 99% release ; cible 200 ms réelle = 3τ ≈ 95% release vers nominal)
5. Sign-off : sound-designer @TBD

**Sprint Audio TBD** : sound-designer playtest dédiée.

### AC-AUD-16 (c) Multi-kill reset — ⏸ ADVISORY DEFERRED

**Status headless** : SKIPPED (même raison driver Dummy).

**Headless fallback** : Sprint Audio sound-designer playtest :
1. `play_3d_at(clac, Vector3.ZERO, &"combat_kill")` à t=0
2. Attendre 50 ms (release partiellement avancé, peak vers -4 dB)
3. 2e clac à t=50 ms (multi-kill)
4. Mesure peak à t=70 ms (2e clac + 20 ms attack)
5. Peak attendu **-6 dB ± 1.5** (re-ducké, release redémarrée depuis zéro)
6. Edge case détection : si peak stagne à -3 dB → FAIL "sidechain re-trigger non fonctionnel sur 2e clac, vérifier `attack_us = 5000` config et que combat_kill bus reçoit bien le 2e signal" 
7. Sign-off : sound-designer @TBD

**Sprint Audio TBD** : sound-designer playtest dédiée.

### AC-AUD-16 (d) Continuité music — ✅ COVERED BLOCKING headless

**Status headless** : ✅ PASS automated (test boolean `music_player.playing` indépendant peak meter driver).

**Mesure** : `audio._music_player.playing` lu pré-clac, mid-ducking (t=30 ms), post-release (t=280 ms).

**Résultat** :
- pré-clac : `playing == true` ✅
- mid-ducking (t=30 ms) : `playing == true` ✅
- post-release (t=280 ms) : `playing == true` ✅

**Validation Player Fantasy Couche 3** : sidechain compressor duck volume_db post-effects, NE STOP PAS playback. Continuité musicale rituelle préservée (pas de coupure abrupte).

**Implementation note** : test utilise `_make_loopable_stream()` (AudioStreamWAV 1s + LOOP_FORWARD) pour garantir playback continu pendant les 280 ms du test. Stream vide (`PackedByteArray()`) terminait instantanément → `playing == false` post-quelques frames (bug fix premier run).

### AC-AUD-16 (e) Headless fallback — ✅ COVERED

**Status** : ✅ PASS — mécanisme detection + push_warning + evidence requirement opérationnel.

**Detection** : `_supports_peak_meter` probe-based runtime (pas hardcoded driver name) → robuste cross-platform (Dummy / Core Audio / WASAPI / ALSA).

**Behavior conditional** :
- Driver Dummy détecté → tests (a)+(b)+(c) `return` early + `push_warning(<AC> SKIPPED — evidence requirement Sprint Audio sound-designer playtest)`
- Driver supporté détecté → tests (a)+(b)+(c) exécutent assertions BLOCKING normales

**Evidence document** : ce fichier `production/qa/evidence/audio-sidechain-music-2026-05-04.md` (template prête à recevoir sign-off Sprint Audio post-playtest).

---

## Sign-off Solo MVP

| AC | Status | Date | Notes |
|----|--------|------|-------|
| AC-AUD-16 (a) Peak ducked | ⏸ DEFERRED Sprint Audio | — | Driver Dummy ; sound-designer playtest @TBD |
| AC-AUD-16 (b) Release ~200 ms | ⏸ DEFERRED Sprint Audio | — | Driver Dummy ; sound-designer playtest @TBD |
| AC-AUD-16 (c) Multi-kill reset | ⏸ DEFERRED Sprint Audio | — | Driver Dummy ; sound-designer playtest @TBD |
| AC-AUD-16 (d) Continuité music BLOCKING | ✅ Solo (Claude assist) | 2026-05-04 | `playing == true` constant pré/mid/post-ducking |
| AC-AUD-16 (e) Headless fallback | ✅ Solo | 2026-05-04 | Detection + push_warning + evidence requirement opérationnel |
| Test fixture | ✅ Solo | 2026-05-04 | `tests/integration/audio/sidechain_music_ducking_test.gd` 3/3 PASS 633 ms |

**Verdict story-012** : 2/5 ACs COVERED headless BLOCKING (d + e), 3/5 ACs ADVISORY DEFERRED Sprint Audio (a + b + c — driver Dummy fallback).

**Re-vérification obligatoire** : post-Sprint Audio sound-designer playtest (driver natif macOS / Windows / Linux), update sections (a)+(b)+(c) avec mesures réelles + sign-off sound-designer.

---

## Common Pitfalls Documentés

1. **`get_bus_volume_db()` ≠ peak meter** : `get_bus_volume_db(MUSIC_idx)` retourne le **fader nominal** (-3 dB constant), PAS la valeur post-effects. Toujours utiliser `get_bus_peak_volume_left_db(MUSIC_idx, 0)` pour mesurer ducking effectif.
2. **Sidechain field type String pas StringName** : `compressor.sidechain = "combat_kill"` (cast String explicite) — Godot 4.6 gotcha, accepter StringName silently fail sans warning.
3. **`attack_us` microsecondes pas millisecondes** : `attack_us = 5000.0` = 5 ms (gotcha nommage asymétrique avec `release_ms`).
4. **Driver Dummy peak meter NON supporté** : tous les tests peak-based doivent inclure detection probe + fallback evidence Sprint Audio playtest.
5. **Stream loopable obligatoire pour continuité test** : `AudioStreamWAV` vide termine instantanément → `playing == false` après quelques frames. Utiliser `loop_mode = LOOP_FORWARD` + data ≥ 1s pour test continuité ≥ 300 ms.
