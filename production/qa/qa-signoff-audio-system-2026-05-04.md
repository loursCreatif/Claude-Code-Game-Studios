## QA Sign-Off Report: Epic Audio System (Sprint Audio CLOSE-OUT)

**Date**: 2026-05-04
**Branche**: chore/story-014-tech-debt-cleanup
**Commit milestone**: 6e5cf2b (`feat(epics/audio-system): Epic Audio System Complete 12/12 — 166/166 PASS`)
**Stage**: Pre-Production
**Review mode**: Solo MVP
**QA Lead sign-off**: Solo (Claude assist 2026-05-04)

---

### Smoke Check Result

**PASS WITH WARNINGS** — 4 warnings non-bloquants documentés.

| # | Warning | Impact | Tracking |
|---|---------|--------|----------|
| W-1 | Driver Dummy headless : peak meter post-effects non supporté | AC-AUD-16 (a/b/c) SKIPPED en CI | D-4 evidence doc + Sprint Audio playtest |
| W-2 | Asset pipeline non finalisé : stubs `AudioStreamWAV.new()` en test fixtures | Re-vérification post-import assets finaux | Sprint Audio post-sound-designer |
| W-3 | AudioListener3D panning + distance attenuation non vérifiés auditivement | AC-AUD-14 (a/b) ADVISORY DEFERRED | D-1 evidence doc + Sprint Audio playtest |
| W-4 | Sidechain CPU cost non mesuré (Godot n'expose aucun monitor per-AudioEffect) | AC-AUD-13 (g) ADVISORY DEFERRED | D-3 evidence doc + Profiler manuel Sprint Audio |

Zéro warning BLOCKING. Build stable. Sortie exit 0 sur tous les runs.

---

### Test Coverage Summary

| Story | Type | Auto Test | Manual QA | Result |
|-------|------|-----------|-----------|--------|
| 001 — Autoload + Bus layout + Pool + Sidechain idempotent | Logic | `audio_boot_test.gd` + `no_alloc_play_2d_test.gd` + `sidechain_idempotent_test.gd` | — | PASS |
| 002 — API verbes play/duck/paused | Logic | `api_play_2d_test.gd` + `api_play_3d_at_test.gd` + `api_null_guards_test.gd` + `api_set_paused_test.gd` | — | PASS |
| 003 — Combat handlers swing/multi-kill/ducking + boundary | Integration | `swoosh_fade_wall_clock_test.gd` + `multi_kill_pitch_shift_test.gd` + `ducking_release_wall_clock_test.gd` | — | PASS |
| 004 — Movement handlers dash/wallrun/walljump/death | Integration | `death_audio_duration_test.gd` + `wallrun_fade_out_test.gd` + `movement_dispatch_test.gd` | AC-AUD-07 (f) overlap respawn ADVISORY | PASS |
| 005 — Level handler crossfade Formula 4 + anti-dip + fallback | Integration | `formula4_crossfade_midpoint_test.gd` + `level_handler_lookup_fallback_test.gd` | — | PASS |
| 006 — GSM pause/resume Master mute + state preservation | Logic | `pause_resume_master_mute_test.gd` | — | PASS |
| 007 — Slow-mo pitch shift bus allowlist + clac exclusion | Integration | `pitch_shift_bus_allowlist_test.gd` + `active_clac_tracker_orphan_test.gd` | AC-AUD-15-b anti-pop waveform ADVISORY | PASS |
| 008 — Secret handler pitch +5st bus SFX invariant slow-mo | Logic | `secret_collect_pitch_shift_test.gd` | — | PASS |
| 009 — Anti-patterns lint static (pool/tween/deferred) | Config/Data | `audio_anti_patterns_lint_test.gd` (3 cases) | Validation auditive ADVISORY | PASS — 0 violation |
| 010 — AudioListener3D verification ADR-0002 chain | Visual/Feel ADVISORY | `audio_listener3d_single_assertion_test.gd` (3 cases) | AC-AUD-14 (a/b) panning + distance ADVISORY DEFERRED | PASS headless |
| 011 — Performance budget 5-swings stress + sub-budgets Phase D.4 | Performance | `audio_5_swings_stress_test.gd` (3 cases) | AC-AUD-13 (g) Sidechain CPU Profiler manuel ADVISORY DEFERRED | PASS (6/7 ACs headless) |
| 012 — Sidechain MUSIC peak meter verification + headless fallback | Integration | `sidechain_music_ducking_test.gd` (3 cases) | AC-AUD-16 (a/b/c) peak ducked + release + reset ADVISORY DEFERRED | PASS headless (2/5 ACs + fallback) |

**166/166 PASS** — exit 0 — durée 2.100 s — zéro régression cross-stories.

---

### ACs Coverage Summary

**BLOCKING headless : 21/21 COVERED**

| Groupe AC | Couverture |
|-----------|------------|
| AC-AUD-01/02/03/20 (Boot, pool, bus, idempotent guard) | ✅ BLOCKING PASS |
| AC-AUD-04/05/06/17 (Combat swoosh + multi-kill + ducking + boundary D≤0/R≤0) | ✅ BLOCKING PASS |
| AC-AUD-07/08/09 (Movement dispatch + pause/resume state preservation) | ✅ BLOCKING PASS |
| AC-AUD-10/11/12 (Lint static pool/tween/deferred — 0 violation) | ✅ BLOCKING PASS |
| AC-AUD-13 (a→f) (Perf 5-swings stress + sub-budgets Phase D.4) | ✅ BLOCKING PASS |
| AC-AUD-14 (c) (Single listener assertion headless) | ✅ BLOCKING PASS |
| AC-AUD-15-a (Slow-mo pitch shift bus allowlist) | ✅ BLOCKING PASS |
| AC-AUD-16 (d/e) (Music continuité + headless fallback probe) | ✅ BLOCKING PASS |
| AC-AUD-18/19/21 (Secret handler + fallback 2D + crossfade Formula 4 midpoint) | ✅ BLOCKING PASS |

**ADVISORY DEFERRED : 4 groupes** — sound-designer playtest @TBD post-MVP

| ID | ACs | Raison du report |
|----|-----|------------------|
| D-1 | AC-AUD-14 (a) panning stéréo + (b) atténuation distance | Validation perceptuelle casque stéréo requise, driver Dummy non représentatif |
| D-2 | Validation auditive lint (écoute swings/kills/dashs/wallruns) | Pipeline assets non finalisé — stubs WAV ne représentent pas l'espace fréquentiel final |
| D-3 | AC-AUD-13 (g) sidechain CPU profiler | Aucun monitor `Performance.*` par AudioEffect en headless — Godot Editor Profiler obligatoire |
| D-4 | AC-AUD-16 (a) peak ducked -6 dB + (b) release ~200 ms + (c) multi-kill reset | Driver Dummy ne supporte pas `get_bus_peak_volume_left_db` post-effects — Core Audio / WASAPI / ALSA requis |

---

### Bugs Found

**Aucun** — Solo MVP, pas de manual QA exécuté cette session. Zéro bug S1/S2 identifié en test automatisé.

Issues mineures résolues durant implémentation Sprint Audio (non bugs ouverts) :
- `sidechain = "combat_kill"` doit être cast String pas StringName (gotcha Godot 4.6, documenté evidence doc story-012)
- `attack_us` en microsecondes vs `release_ms` en millisecondes sur `AudioEffectCompressor` (nommage asymétrique — documenté engine-ref `audio.md` r3 Phase D.5)
- `AudioStreamWAV` vide termine en < 1 frame → test continuité music requiert `loop_mode = LOOP_FORWARD` + data ≥ 1s (documenté evidence doc story-012)

---

### Verdict: APPROVED WITH CONDITIONS

**Conditions** :

1. **Sound-designer playtest post-MVP** (1 session ≈ 90 min, setup unique Godot Editor + casque stéréo + AudioEffectRecord) pour lever les 4 ADVISORY DEFERRED :
   - D-1 (audio-listener3d) AC-AUD-14 (a) panning stéréo + (b) atténuation distance : rotation Player 90° Y, écoute positionnement gauche/droite/distance
   - D-2 (audio-anti-patterns-lint) validation auditive : écoute gameplay normal swings/kills/dashs/wallruns sur assets finaux importés
   - D-3 (audio-perf) AC-AUD-13 (g) sidechain CPU : Profiler tab Audio Godot Editor, bypass compressor ON vs OFF, Δ CPU attendu < 0.5%
   - D-4 (audio-sidechain-music) AC-AUD-16 (a/b/c) : peak meter post-compressor via AudioEffectRecord + Audacity loopback, FFT analysis, cibles -6 dB ± 1.5 / release ~200 ms / reset multi-kill

2. **Re-vérification post-asset-pipeline finalisé** : streams audio finaux (swoosh.wav / clac.wav / blood.wav / dash.wav / wallrun_loop.wav / walljump.wav / death.wav / room_tone_chrome_zen.wav / music_etage_NN.ogg) importés — tests unit/integration utilisent stubs MVP. Priorité : AC-AUD-15-b (anti-pop pitch transition 1.0→0.7935→1.0 sur assets réels)

3. **Cross-platform driver verification post-MVP** : Core Audio macOS / WASAPI Windows / ALSA Linux — CI headless driver Dummy ne valide pas le mix engine. Exécuter la suite `tests/integration/audio/` en mode Editor sur chaque OS cible.

---

### Next Step

APPROVED WITH CONDITIONS — Sprint Audio peut avancer vers le prochain workflow. Les 4 ADVISORY DEFERRED ne bloquent pas l'avancement du project stage car :
- Toutes les ACs BLOCKING headless sont COVERED (21/21)
- ADVISORY = qualité auditive subjective perceptuelle, dépend assets finaux + driver natif non disponibles en CI
- Tracking explicite dans 4 evidence docs avec protocoles de levée détaillés

Recommandation : avant `/gate-check pre-production-to-production`, exécuter `/smoke-check sprint` pour re-validation suite complète projet (pas seulement audio) + audit cross-system (notamment vérifier que autoload order Audio System est correct post-Sprint Audio — ADR-0007 D-1 TBD).

---

### Test Cases ADVISORY DEFERRED

Référence : `production/qa/test-cases-audio-advisory-deferred-2026-05-04.md` (généré par qa-tester Phase 4 — guide playtest sound-designer post-MVP pour D-1 / D-2 / D-3 / D-4).

---

### Patterns Quality Highlights (Sprint Audio)

Patterns nouveaux réutilisables introduits par Sprint Audio, éligibles comme références pour futurs epics :

1. **Wall-clock fade via Callable injection** (`_get_time_msec: Callable`) — pattern `_physics_process` + `Time.get_ticks_msec()` sans Tween, résiste aux variations `Engine.time_scale` (ADR-0009 D-3). Réutilisable par tout système à fade time-critical (VFX, camera shake, HUD transitions).

2. **Pool pré-alloué round-robin avec interrupt sur saturation** — 20 nodes instanciés au boot, réutilisés cycliquement, jamais étendus runtime. `push_warning` sur saturation (pas de crash). Pattern réutilisable pour tout pool de nodes Godot (VFX particles, hitboxes, projectiles).

3. **Sidechain compressor probe-based driver detection** (`_supports_peak_meter()`) — détection runtime via probe signal + fallback gracieux (pas de hardcode driver name). Pattern réutilisable pour toute feature dont la vérification automatisée dépend d'un driver matériel (GPU profiling, haptic feedback).

4. **`CONNECT_DEFERRED` comme défaut systémique** — tous les `connect()` vers handlers `_on_*` cross-system en DEFERRED par convention (lint CI enforce). Élimine les mutations cross-system mid-physics-frame sans overhead perceptible. Pattern recommandé pour tout autoload Core layer.

5. **Lint statique CI tri-gate** (pool / tween / deferred) — 3 grep gates indépendants du runtime, 0 dépendance Godot, exécutables en < 1 s. Pattern extensible : chaque couche architecture peut ajouter ses propres gates dans `.claude/rules/`.

6. **Position payload capturée au tick d'émission** — handler audio reçoit `position: Vector3` via payload signal, jamais `enemy.global_position` post-réception (queue_free race). Pattern obligatoire pour tout handler 3D positional consommant des signaux de nodes pouvant être libérés (ADR-0006 D-3).

---

### Risks Surfaced

Risques résiduels post-Sprint Audio à surveiller :

1. **Driver Dummy CI — couverture peak meter** : la suite CI ne peut pas valider le ducking effectif du sidechain compressor. Si la configuration `AudioEffectCompressor` est corrompue (merge conflict, régression story-001), le bug ne sera détecté qu'en playtest sound-designer. Mitigation : test AC-AUD-16 (d) `music_player.playing` (headless-testable) détecte une coupure abrupte mais pas un ducking insuffisant.

2. **Asset pipeline stubs** : tous les tests utilisent `AudioStreamWAV` vide ou minimal. Comportements fréquentiels réels (saturation clipping, phasing artifacts, loop glitch) ne seront révélés qu'avec assets finaux. Risque modéré — AudioStreamWAV format valide mais non représentatif.

3. **Sound-designer dépendance @TBD** : les 4 groupes ADVISORY DEFERRED ne peuvent pas être levés sans sound-designer disponible. Si le recrutement est retardé, les conditions de sign-off resteront ouvertes indéfiniment. Recommandation : fixer une date limite Sprint Audio playtest avant `/gate-check production`.

4. **Autoload order Audio System non finalisé** : ADR-0007 D-1 note "Audio position TBD post-Sprint Audio, après InputManager / GSM / SaveLoad". Si l'ordre dans `project.godot` est incorrect, les handlers `_on_state_changed` GSM peuvent s'exécuter avant qu'AudioSystem soit prêt. À vérifier lors du `/smoke-check sprint` prochain.
