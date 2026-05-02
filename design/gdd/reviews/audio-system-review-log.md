# Audio System — Review Log

## Review — 2026-04-27 (r2.1 re-review post A+B) — Verdict: NEEDS REVISION → APPROVED r2.1 (14 fixes appliqués directement)

**Scope signal**: M (surgical — ~30 lignes GDD + 1 amendment ADR-0009 D-6, aucun redesign architectural)
**Specialists**: game-designer, audio-director, qa-lead, godot-specialist (4 agents parallèles adversariaux — creative-director synthesis skipped, CD adjudications r1 vérifiées appliquées)
**Mode**: `/design-review` fresh session focused — re-review uniquement Phase A+B per CD locked order r1 (Phase C+D explicitly DEFERRED)
**Blocking items identifiés**: 14 | Recommended: 8 | Action: 14/14 fixes appliqués immédiatement (Option A)
**Prior verdict resolved**: MAJOR REVISION NEEDED r1 (16 BLOCKING, scope XL) → fully resolved r2 Phase A+B vision/spec, partial application surfaced 14 résidus surgicaux r2.1.

### Summary

Le GDD r2 a correctement adressé les 6 adjudications CD r1 dans les sections normatives (Rules 11/13/14/16, Formulas 5/6, ACs reformulés, OQs résolus). Les 4 specialists ont convergé sur **14 BLOCKING surgicaux** — aucun redesign architectural, tous corrigeables ≤ 30 min :

**(A) Éditorial r1 résidu (5 items)** :
1. Bus naming UPPER_SNAKE_CASE half-applied — Rule 3 hierarchy + AC-AUD-01 + Mix hierarchy §1-5 + Visual/Audio table en mixed lowercase ; Rules 11/16/Tuning Knobs en UPPER. Risk CI : AC-AUD-01 faux négatif/positif selon implémentation `.tres`. **FIX** : grep-replace systématique vers `SWING_ACTIVE`/`COMBAT_KILL`/`MUSIC`/`AMBIENCE`/`UI`/`SFX`/`MASTER` (`replace_all` Edit + Player Fantasy Couche 1 + Formulas).
2. Mix hierarchy §4 (L401) "Pas de ducking automatique combat" contredit Rule 16 sidechain. **FIX** : réécriture §4 reflétant compressor sidechain ducked peak -6 dB / atténuation moyenne -3 dB / release 200 ms.
3. Header L22 + Cross-Refs L428 citent "≤ 40 ms" obsolète vs Rule 14 (60-80 ms). **FIX** : remplacement valeurs r1.
4. Formula 3 (L218) `pool_size: 4/8` (r1) vs Rule 2/Tuning Knobs/AC-AUD-02 (5/12 r2). AC-AUD-03 cycle round-robin `0→1→2→3→0` (pool 4) erroné. **FIX** : Formula 3 → 5/12, AC-AUD-03 (c) cycle → `0→1→2→3→4→0`.
5. Mix hierarchy §5 UI mute phrase auto-contradictoire ("Indépendant Master mute (toujours audible — non, mute Master coupe UI aussi MVP, simplification)"). **FIX** : réécriture propre selon OQ#6 résolu (mute total MASTER MVP, Tier 2 reconsidéré).

**(B) Spec gaps Phase A (4 items)** :
6. Rule 11 ne clarifiait pas explicitement que Formula 5 sur `COMBAT_KILL` exclut le slot clac (préserver Couche 1 invariance). Risk : implémenteur applique pitch au clac → casse Fantasy Couche 1. **FIX** : ajout `_active_clac_players: Dictionary[int, bool]` tracker per slot + boucle pitch-shift skip ces indexes ; AC-AUD-15 (b') "slot clac exclu" testé.
7. Rule 11 L94 "sons démarrés pendant slow-mo héritent du `pitch_scale` au `play()`" ambigu — mécanisme `_physics_process` polling = latence 1 tick. **FIX** : préciser handler dispatch détecte `Engine.time_scale != 1.0` AVANT `play()` et set `pitch_scale` directement (zero latency) ; AC-AUD-15 (e) couvre le cas.
8. Rule 16 prose "ducking déclenche immédiatement" / "instantané" incorrect avec attack 5 ms (peak ducking atteint à t≈5 ms post-onset, pas pendant le transient < 5 ms). **FIX** : Rule 16 prose perceptuelle correcte ("amorce l'atténuation à l'onset, peak à ~5 ms") + edge case swings 170 ms apart documenté + guard double-add_bus_effect Phase D + clarification effective ducking peak -6 dB vs atténuation perçue moyenne -3 dB.
9. **Contradiction inter-ADR ADR-0002 vs ADR-0009 D-6 + AC-AUD-14 (c)** : ADR-0002 (Accepted) prescrit `AudioListener3D` enfant explicite Camera3D (chain `... → Camera3D → AudioListener3D`, VC-5). ADR-0009 D-6 + GDD Rule 9 disaient "NE PAS instancier d'AudioListener3D dédié" + AC-AUD-14 (c) testait `size() == 0` — contradiction directe. **FIX** : amendment ADR-0009 D-6 r2 reconnaissant ADR-0002 chain (1 listener explicite, pas zéro) + Rule 9 GDD alignée ("enfant explicite Camera3D per ADR-0002, pas de second listener") + AC-AUD-14 (c) corrigé `size() == 1`.

**(C) Testability ACs Phase A+B (5 items)** :
10. AC-AUD-16 utilisait `AudioServer.get_bus_volume_db()` (fader nominal, pas post-compressor) → test passait silencieusement à `-3.0 dB` même sans compressor. **FIX** : `AudioServer.get_bus_peak_volume_left_db(bus_idx, channel)` (peak meter post-effects) + headless fallback ADVISORY si `--audio-driver Dummy` ne supporte pas peak meter post-effects.
11. AC-AUD-15 (c) "transition mid-`play()` ... pas de pop sonore" placeholder non-testable. **FIX** : protocole déterministe — `AudioEffectRecord` sur `COMBAT_KILL` pendant transition `1.0→0.3→1.0`, FFT post-render, seuil discontinuité ≤ 3 dB peak entre frames adjacents → FAIL. Headless fallback ADVISORY si CI ne supporte pas record.
12. AC-AUD-02 (e) `Performance.OBJECT_COUNT` delta ±0 non-déterministe en multi-autoload boot. **FIX** : remplacé par `AudioSystem.get_child_count() == 20` (assertion structurale directe).
13. AC-AUD-05 testait 1er/2e/3e kill mais pas le cap 4e kill (Rule 13 dit `4e+` capé +4 semitones). **FIX** : ajout scenario 4e `enemy_killed` injecté → counter `4`, pitch_scale ≈ 1.260 ± 0.01 (cap, pas +6 carry-over).
14. AC-AUD-07 manquait precheck asset existence + clarification overlap automatisable vs evidence playtest. **FIX** : (a) `ResourceLoader.exists("res://.../death.wav")` precheck en tête + (f) "overlap respawn frame intentionnel" explicitement marqué non-automatisable headless → evidence playtest dossier `production/qa/evidence/audio-death-overlap-{date}.md`.

### Specialists' BLOCKING tally (14 total — convergence forte)

| Source | Count | Top finding |
|---|---|---|
| game-designer | 5 | Bus naming half-applied (BLOCKING-01), Mix hierarchy §4 contradiction, header ≤ 40 ms, Formula 3 stale, clac slot exclusion ambiguous |
| audio-director | 8 | Mix hierarchy §4 contradiction (cross-flagged), §5 phrase auto-contradictoire, attack 5 ms prose, sidechain swings 170 ms apart pumping, Formula 6 -3 dB peak vs -6 dB confusion, audio.md référence factuellement fausse |
| qa-lead | 5 | AC-AUD-16 mesure post-compressor manquante, AC-AUD-15 (c) anti-pop placeholder, AC-AUD-02 (e) OBJECT_COUNT non-déterministe, AC-AUD-05 cap 4e kill non testé, AC-AUD-07 ResourceLoader precheck manquant |
| godot-specialist | 3 | ADR-0002 vs ADR-0009 D-6 contradiction (cross-ADR), AC-AUD-16 `get_bus_peak_volume_left_db` API correcte, Formula 3 pool_size stale (cross-flagged) |

(Items cross-flagged par plusieurs specialists agrégés en 14 unique.)

### Adjudications r2.1 — Action immédiate (skip re-review fresh)

Pas d'adjudication CD nécessaire (r1 adjudications déjà tranchées et appliquées correctement dans les sections normatives r2 ; r2.1 est purement application/correction surgicale des résidus). Verdict skill : NEEDS REVISION → fixes appliqués directement Option A (auto-approve solo mode + collab protocol "auto-approve recommended proposals") → **status APPROVED r2.1**. Re-review fresh skip car :
- Tous fixes scope-bounded (1-3 lignes max chacun, pas de redesign).
- 4 specialists ont identifié et caractérisé chaque fix précisément.
- Cohérence inter-document validée (Rule 9 GDD ↔ ADR-0009 D-6 ↔ ADR-0002 chain).

### Files modified r2.1

- `design/gdd/audio-system.md` : ~30 lignes éditées (Status header r2.1, Player Fantasy Couches 1+4, Rule 3 hierarchy UPPER, Rule 9 listener alignment ADR-0002, Rule 11 clac slot exclusion + pitch AVANT play, Rule 16 attack 5 ms perceptuel + edge cases, Formula 3 pool_size 5/12, Formula 6 example UPPER, Mix hierarchy §1-5 réécrites, Visual/Audio table buses UPPER + room tone row ajoutée, Interactions Combat clarifié, Cross-Refs L428 + L434, AC-AUD-01/02/03/05/07/14/15/16 corrigés/enrichis, Status final r2.1).
- `docs/architecture/adr-0009-audio-system-architecture.md` : D-6 amendé r2.1 (reconciliation ADR-0002 chain AudioListener3D explicite enfant Camera3D — 1 listener, pas zéro).

### Phase C/D restantes (non-blocking r2.1, scope clairement délimité)

- **Phase C (formules + ACs hardening)** : F-01 div par zéro guards Formules 1/2/4 (knob hits 0), F-02 Formule 4 perceptual conversion ≥ 1 s, F-04 double atténuation player+bus documentée, AC-AUD-04/06/08/09/11/13 reformulations observable, AC-AUD-14 promotion ADVISORY → BLOCKING (post-AC-AUD-14 size==1 fix), 5 ACs manquants r1 (null stream, invalid bus, pool saturation, F4 boundaries, Master mute UI).
- **Phase D (impl)** : pool 3D parenting `get_tree().root` ou set `global_position` avant `play()`, fade timestamp capture `_physics_process` premier tick, perf metric split (handler GDScript vs AudioServer mixer thread), `_active_clac_players` tracker impl + lifecycle, double-add_bus_effect guard `get_bus_effect_count(MUSIC_idx) == 0` avant add, ADR-0009 Architecture Diagram + Consequences + Performance Implications mis à jour pool 20 nodes (~20 KB), `audio.md` engine reference section `AudioEffectCompressor` (`.threshold`, `.ratio`, `.attack_us` µs, `.release_ms`, `.sidechain` String).

### Cross-system insights

- **ADR-0002 chain** : reconnaissance explicite `AudioListener3D` enfant Camera3D (VC-5 ADR-0002) dans ADR-0009 D-6 + GDD Rule 9 + AC-AUD-14 (c) — supprime contradiction inter-ADR Accepted.
- **ADR-0006 D-4 pattern partagé** : `_set_time_provider` debug-guarded test-only (OQ#9 résolu Phase B) cohérent Combat Callable injection.
- **Story-020 Combat (BLOCKED)** : **DÉBLOQUÉE** par audio-system APPROVED r2.1.
- **Registry SLOW_MO_SCALE** : Open Question divergence 0.15 (registry) vs 0.3 (Combat r6 + Audio Formula 5) toujours ouverte. À résoudre via `/consistency-check` avant Sprint Audio (mentionné REC-04 r2.1).

### Key insight (carry forward)

Le pattern "vision adjudiqué CD → application incomplete par sections normatives only → résidu éditorial dans sections descriptives parallèles" est récurrent. **Pour futurs re-reviews post-CD adjudications** : grep-check systématique de TOUS les references aux concepts ré-adjudiqués (header, Cross-Refs, Mix hierarchy descriptive, Formula tables, AC bodies) — pas seulement les sections normatives Rules. Un fix de Rule sans propagation aux sections descriptives crée des contradictions internes silencieuses. Lint authoring possible Phase D : grep "≤ 40 ms" / lowercase bus names / pool 4/8 / "Pas de ducking" → fail si match dans GDDs APPROVED.

### Reports

- Synthesis r2.1 : ce review log (creative-director skipped — convergence specialists forte, adjudications r1 déjà tranchées)
- ADR-0009 binding : `docs/architecture/adr-0009-audio-system-architecture.md` (Accepted 2026-04-27 + r2 amendements D-1/D-3 + r2.1 amendment D-6)

---

## Review — 2026-04-27 — Verdict: MAJOR REVISION NEEDED

**Scope signal**: XL
**Specialists**: audio-director, game-designer, systems-designer, qa-lead, performance-analyst, godot-specialist, creative-director (synthesis)
**Mode**: `/design-review` full fresh session (multi-specialist parallel)
**Blocking items**: 16 | Recommended: 15 | Nice-to-have: 10
**Prior verdict resolved**: First review

### Summary

Le GDD r1 (404 lignes, 8 sections requises + 4 bonus) opérationnalise ADR-0009 (Accepted 2026-04-27 même jour) mais expose 4 contradictions vision-level non résolues :

1. **Couche 1 vs Couche 3** — la Fantasy "silence rythmique post-clac" et "continuité musicale invisible" s'annulent au mix actuel (Music -3 dB jamais auto-ducked vs clac 0 dB). Fix CD : sidechain compressor sur bus `Music` feed depuis `combat_kill` (mécanisme, pas verbal). Amende ADR-0009 D-1.
2. **Multi-kill noop MVP** — différer le climax sonique du jeu one-shot katana au Tier 2 est un trou Fantasy MVP, pas un compromis de scope. Fix CD : pitch-shift +2 semitones existing clac sur 2e/3e kill du même swing.
3. **death.wav ≤ 40 ms** — physiquement impossible (seuil reconnaissance timbre 60-100 ms). Fix CD : raise 60-80 ms + overlap on first respawn frame allowed (ne pas extend RESPAWN_DELAY).
4. **Decision Martin D3 pitch invariance vs HLM** — référence sonique Hotline Miami incompatible avec D3 (HLM tire 40% de son identité du pitch-down synthwave en slow-mo). **Décision Martin pendante** — reco CD = REOPEN D3, autoriser pitch-shift -2..-4 semitones sur `combat_kill` + `Ambience` sous slow-mo, Music bus protégé.

S'ajoutent 4 BLOCKING formules (division par zéro non gardée, Formule 4 viole sa propre règle ligne 81, pool 2D min insuffisant MVP, double atténuation Formule 1+2 non documentée), 2 BLOCKING impl Godot (pool 3D parenting fragile, timestamp race CONNECT_DEFERRED↔_physics_process), 6 BLOCKING ACs (Open Question #9 gate, tolerances dB non validées, mécanismes assertion manquants, state interne privé, méthodologie mesure absente), promotion AC-AUD-14/15 ADVISORY→BLOCKING, 5 ACs manquants, et 4 BLOCKING perf (mixer thread budget, faux positifs CI, isolation, cold-cache).

### Specialists' BLOCKING tally (16 total)

| Source | Count | Top finding |
|---|---|---|
| audio-director | 3 | Music sans sidechain HLM pump |
| game-designer | 3 | Couche 1 vs Couche 3 contradiction |
| systems-designer | 4 | F-01 div par zéro Formules 1/2/4 |
| qa-lead | 7 (+ promotion) | OQ#9 Callable injection gate AC-04/06 |
| performance-analyst | 4 | AudioServer mixer thread budget undefined |
| godot-specialist | 2 | Pool 3D parented to Node autoload (spatial fragile) |

(Some BLOCKING flagged by multiple specialists overlap — agrégé 16 unique items.)

### Adjudications creative-director (5 vision calls tranchées)

1. **death.wav** : 60-80 ms + overlap on respawn frame (pas 40 ms, pas extend RESPAWN_DELAY).
2. **multi_kill** : pitch-shift +2 semitones existing clac (pas asset nouveau, pas Tier 2 deferral).
3. **Music ducking** : sidechain compressor sur `combat_kill` bus (résout Couche 1 vs Couche 3 au mix, pas en prose).
4. **Pool sizing** : appliquer les deux — 3D 8→12 ET 2D min 3→5.
5. **Bus naming** : standardiser UPPER_SNAKE_CASE (`SWING_ACTIVE`, `COMBAT_KILL`, `MUSIC`, `AMBIENCE`, `UI`, `MASTER`).

### Adjudication pendante (1 vision call user)

- **Decision Martin D3 (pitch invariance under slow-mo)** : reco CD = REOPEN, autoriser pitch-shift -2..-4 semitones sur `combat_kill` + `Ambience` sous slow-mo, `Music` bus protégé. Action requise : décision Martin avant Phase A r2.

### Revision order locked (CD)

- **Phase A (vision)** : décision D3 → Fantasy rewrite (résoudre Couche 1 vs Couche 3, choisir réf HLM/Sekiro) → ADR-0009 amendment (D-1 sidechain compressor).
- **Phase B (spec)** : death.wav (60-80 ms + overlap), multi_kill (pitch-shift), pools (2D min 3→5 + 3D 8→12), résoudre Open Questions #6 (UI mute exclusion), #7 (room tone Chrome Zen spec), #9 (Callable injection API stable vs test-only).
- **Phase C (formules + ACs)** : F-01 div par zéro guards, F-02 Formule 4 perceptual conversion, F-04 double atténuation documentée. AC-04/05/06/08/09/11/13 reformulés observable. AC-14/15 promotion BLOCKING avec tests déterministes. 5 ACs manquants ajoutés.
- **Phase D (impl, parallèle C)** : pool 3D parenting → `get_tree().root`, fade timestamp capture en `_physics_process` premier tick (pas idle frame DEFERRED), perf metric split (handler GDScript vs AudioServer mixer thread), bus naming UPPER_SNAKE_CASE, fichiers `src/core/audio_buses.gd` + `src/core/audio_system.gd` nommés explicitement.

**Re-review uniquement après A+B**. Phase C/D ne nécessite pas re-review si A shift (cascade impacts).

### Dependency graph

- ✓ game-state-manager.md (APPROVED r1)
- ✓ camera-system.md (In Review r2)
- ✓ level-system.md (APPROVED r3 → r4 surgical 2026-04-27) — Open Question #1 ✅ **RÉSOLU r4 Option C** : Audio consume `level_active` existant + lookup synchrone `LevelSystem.get_etage_audio_streams(etage_id)`. Pas de signal `etage_loaded` créé. Level r4 §Interactions Audio + pseudocode `get_etage_audio_streams` + Tuning Knob `ETAGE_AUDIO_MAPPING` + §Dependencies Downstream Audio updated. Phase B audio spec peut procéder.
- ✓ player-combat-system.md (APPROVED r6)
- ✓ player-movement-system.md (In Review r3 — Movement `dash_rejected` Open Question #3)
- ✓ input-system.md (NEEDS REVISION r4)

### Cross-system insights

- **Registry divergence connue** : `SLOW_MO_SCALE = 0.15` registry / `0.3` Combat r6 / `0.3` Audio formules. Audio Open Question #2 reconnaît. Combat r6 + Audio aligned, registry stale. À corriger via `/consistency-check` ou amendement registry.
- **AC-AUD-04/06 cross-system contracts** : mirror AC-CMB-51, AC-CMB-audio-01, AC-CMB-audio-02 préservés côté Audio. Pattern `_get_time_msec` Callable injection partagé Combat ADR-0006 D-4 ↔ Audio ADR-0009 D-3.
- **Story-020 Combat (BLOCKED)** : reste BLOCKED jusqu'à audio-system APPROVED — promu testable post-Audio GDD per ADR-0009 promotion notes.

### Key insight (carry forward)

La Couche 1 ("silence rythmique") + Couche 3 ("continuité musicale invisible") contradiction était écrite comme couches parallèles dans le GDD. Le vrai fix est le *mécanisme* (sidechain compressor), pas la *prose*. **Pour futurs audio GDDs** : spec le mix, pas la liste de couches. Le GDD doit produire un fichier `default_bus_layout.tres` opérationnel avec effects (Compressor, Limiter, EQ) — pas seulement une hiérarchie de noms.

### Reports

- Synthesis CD memory : `~/.claude/agent-memory/creative-director/project_chrome_ascent_audio_r1.md`
- Performance memory : `~/.claude/agent-memory/performance-analyst/feedback_audio_review.md`
- ADR-0009 binding : `docs/architecture/adr-0009-audio-system-architecture.md` (Accepted 2026-04-27)
