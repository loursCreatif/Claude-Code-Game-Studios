# QA Plan — Epic Audio System (Sprint Audio CLOSE-OUT) — 2026-05-04

> **Pipeline** : `/team-qa sprint` Phase 3
> **Branche** : `chore/story-014-tech-debt-cleanup`
> **Commit milestone** : `6e5cf2b` (Epic Audio System Complete 12/12)
> **Stage projet** : Pre-Production
> **Review mode** : Solo MVP

---

## 1. Scope

| Field | Value |
|-------|-------|
| Sprint | Audio System CLOSE-OUT |
| Stories | 12 (story-001 → story-012) |
| Period | 2026-04-23 (Foundation) → 2026-05-04 (Sidechain MUSIC) |
| Engine | Godot 4.6 + GDScript |
| ADR governing | ADR-0009 (Audio System) + amendement r2 sidechain MUSIC ← combat_kill |
| GDD reference | `design/gdd/audio-system.md` (R-AUD-1 → R-AUD-20, AC-AUD-1 → AC-AUD-16, VC-1 → VC-8) |

---

## 2. Story Classification Table

| Story | Title (court) | Type | Automated test path | Manual scope | Blocker |
|-------|---------------|------|---------------------|--------------|---------|
| 001 | Autoload + Bus layout + Pool 20 + Sidechain idempotent | Logic | `tests/integration/audio/audio_boot_test.gd` + `no_alloc_play_2d_test.gd` + `tests/unit/audio/sidechain_idempotent_test.gd` | — | NON |
| 002 | API verbes play/duck/paused | Logic | `tests/unit/audio/api_play_2d_test.gd` + `api_play_3d_at_test.gd` + `api_null_guards_test.gd` + `api_set_paused_test.gd` | — | NON |
| 003 | Combat handlers swing/multi-kill/ducking + boundary | Integration | `swoosh_fade_wall_clock_test.gd` + `multi_kill_pitch_shift_test.gd` + `ducking_release_wall_clock_test.gd` | — | NON |
| 004 | Movement handlers dash/wallrun/walljump/death | Integration | `death_audio_duration_test.gd` + `wallrun_fade_out_test.gd` + `movement_dispatch_test.gd` | AC-AUD-07 (f) overlap respawn ADVISORY | NON |
| 005 | Level handler crossfade Formula 4 + anti-dip + fallback | Integration | `formula4_crossfade_midpoint_test.gd` + `level_handler_lookup_fallback_test.gd` | — | NON |
| 006 | GSM pause/resume Master mute state preservation | Logic | `pause_resume_master_mute_test.gd` | — | NON |
| 007 | Slow-mo pitch shift bus allowlist + clac exclusion | Integration | `pitch_shift_bus_allowlist_test.gd` + `active_clac_tracker_orphan_test.gd` | AC-AUD-15-b anti-pop waveform ADVISORY | NON |
| 008 | Secret handler pitch +5st bus SFX invariant slow-mo | Logic | `secret_collect_pitch_shift_test.gd` | — | NON |
| 009 | Anti-patterns lint static (pool/tween/deferred) | Config/Data | `tests/static/audio_anti_patterns_lint_test.gd` (3 cases) | Validation auditive ADVISORY | NON |
| 010 | AudioListener3D verification ADR-0002 chain | Visual/Feel ADVISORY | `audio_listener3d_single_assertion_test.gd` (3 cases) | AC-AUD-14 (a/b) panning + distance ADVISORY DEFERRED | NON |
| 011 | Performance budget 5-swings stress + sub-budgets Phase D.4 | Performance | `tests/perf/audio_5_swings_stress_test.gd` (3 cases) | AC-AUD-13 (g) sidechain CPU Profiler manuel ADVISORY DEFERRED | NON |
| 012 | Sidechain MUSIC peak meter verification + headless fallback | Integration | `sidechain_music_ducking_test.gd` (2 BLOCKING headless + 2 conditional driver) | AC-AUD-16 (a/b/c) peak ducked + release + multi-kill reset ADVISORY DEFERRED | NON |

**Bilan** : 12/12 stories Complete | 12 tests automatisés (unit + integration + perf + static) | 4 groupes ADVISORY DEFERRED Sprint Audio sound-designer playtest @TBD post-MVP.

---

## 3. Automated Test Requirements

**Suite complète** : `godot --headless --script res://addons/gdUnit4/bin/GdUnitCmdTool.gd --add tests/integration/audio/ --add tests/unit/audio/ --add tests/perf/audio_5_swings_stress_test.gd --add tests/static/audio_anti_patterns_lint_test.gd --ignoreHeadlessMode`

| Catégorie | Path | Tests | Status |
|-----------|------|-------|--------|
| Unit audio | `tests/unit/audio/` | 7 fichiers | PASS |
| Integration audio | `tests/integration/audio/` | 14 fichiers | PASS |
| Performance audio | `tests/perf/audio_5_swings_stress_test.gd` | 3 cases | PASS |
| Static lint | `tests/static/audio_anti_patterns_lint_test.gd` | 3 cases | PASS |

**Résultat consolidé** : **166/166 PASS**, exit 0, 2.100 s, zéro régression sur stories 001-011 après ajout 012.

---

## 4. Manual QA Scope

**Solo MVP** : aucun manual QA exécutable cette session — sound-designer non disponible @TBD, driver natif (Core Audio macOS / WASAPI Windows / ALSA Linux) non utilisé en CI headless. **Tous les manual playtests sont DEFERRED post-MVP** vers une session dédiée Sprint Audio playtest sound-designer.

### 4 groupes ADVISORY DEFERRED — protocoles documentés

| # | Evidence doc | ACs DEFERRED | Setup playtest | Outils requis |
|---|---|---|---|---|
| D-1 | `audio-listener3d-verification-2026-05-04.md` | AC-AUD-14 (a) panning stéréo + (b) atténuation distance | Player rotation 90° Y dans `etage_01.tscn`, ennemi positionné à gauche/droite/avant/arrière, distance 5 m / 15 m / 30 m | Casque stéréo, Godot Editor mode |
| D-2 | `audio-anti-patterns-lint-2026-05-04.log` | Validation auditive lint ADVISORY | Écoute manuelle des swings/kills/dashs/wallruns en gameplay normal | Casque stéréo, Godot Editor mode |
| D-3 | `audio-perf-2026-05-04.md` | AC-AUD-13 (g) sidechain CPU profiler | 5-swings stress dans Editor, mesure CPU AudioEffectCompressor ON vs OFF via Godot Profiler tab `Audio` | Godot Editor + Profiler tab Audio |
| D-4 | `audio-sidechain-music-2026-05-04.md` | AC-AUD-16 (a) peak ducked -6 dB ± 1.5 + (b) release ~200 ms + (c) multi-kill reset | `AudioEffectRecord` post-render bus Music + capture loopback Audacity, FFT analysis, écoute casque | `AudioEffectRecord`, Audacity ou REAPER, casque stéréo |

**Effort estimé total** : **1 session playtest sound-designer ≈ 90 min** post-pipeline assets (couvre D-1 + D-3 + D-4 simultanément avec setup unique Godot Editor + casque + AudioEffectRecord) + 15 min D-2 écoute additionnelle.

---

## 5. Out of Scope

- **Multi-platform driver verification** : Core Audio macOS / WASAPI Windows / ALSA Linux non testés en CI headless. Tracking sound-designer playtest sur 3 OS post-MVP.
- **Asset pipeline final** : streams audio finaux (synthwave music, SFX katana, clac death sound) non importés MVP — tests utilisent stubs `AudioStreamWAV` + `_make_loopable_stream()`. Re-vérification obligatoire post-import assets finaux.
- **VR/Surround 5.1** : pas de support listener 5.1/7.1 — MVP stéréo only.
- **Playtest joueur** : tests perceptuels (sensation rituelle Couche 3 musique pendant ducking, satisfaction kill clac) hors scope cette QA cycle — réservés feel-playtest dédié.
- **Memory leak long-running** : soak test 60 min+ non couvert — couvert par AC-AUD-13 (a/b/c) 1000 frames stress (16.6 s wall-clock).

---

## 6. Entry Criteria

- [x] Smoke check Phase 2 : **PASS WITH WARNINGS** (4 warnings documentés non-bloquants)
- [x] 166/166 audio suite PASS, exit 0
- [x] 0 AC BLOCKING ouverte
- [x] Build stable sur branche `chore/story-014-tech-debt-cleanup`
- [x] Commit milestone `6e5cf2b` produit
- [x] 4 evidence docs ADVISORY DEFERRED écrits avec protocoles détaillés

---

## 7. Exit Criteria

- [x] Tous les tests BLOCKING headless PASS (12 stories couvertes)
- [x] 4 ADVISORY DEFERRED trackés dans evidence docs avec protocoles playtest
- [x] Story files Status: Complete avec Completion Notes
- [x] Sign-off report écrit (`production/qa/qa-signoff-audio-system-2026-05-04.md`)
- [ ] Playtest sound-designer Sprint Audio post-MVP : **DEFERRED Sprint Audio** — sound-designer @TBD (condition de sign-off APPROVED WITH CONDITIONS levée à cette étape)

---

## 8. Verdict Phase 3

**QA Plan APPROVED** pour exécution Phases 4-7. Mode solo MVP : Phase 6 manual QA execution = mark all DEFERRED Sprint Audio (sound-designer @TBD). Phase 7 sign-off attendu : **APPROVED WITH CONDITIONS** (condition = playtest sound-designer post-MVP pour lever 4 ADVISORY DEFERRED).
