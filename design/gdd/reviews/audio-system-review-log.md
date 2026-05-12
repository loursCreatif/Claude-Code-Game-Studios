# Audio System — Review Log

## Note — 2026-05-03 (Phase D.5 engine-ref dump RESOLVED, post-r2.3)

**Type**: Suivi engine-ref dump (pas une review). Action déclenchée par r2.3 review entry "Phase D.5 engine-ref pré-requis BLOCKING Sprint Audio".

**Action**: Section **AudioEffectCompressor (Sidechain Ducking)** ajoutée à `docs/engine-reference/godot/modules/audio.md` (+85 lignes). Contenu : table props Godot 4.6 (`threshold`, `ratio`, `gain`, `attack_us` µs, `release_ms` ms, `mix`, `sidechain`), Critical Naming Gotcha bloc, Sidechain Ducking Pattern Phase D.2 (boot guard idempotent type check `is AudioEffectCompressor`), Verification block AC-AUD-01 (d), Common Pitfalls.

**Réconciliation factuelle**: la review r2.3 émettait l'hypothèse d'un breaking change Godot 4.3→4.6 sur `attack` ms → `attack_us` µs. **Vérifié faux** : ces noms existent depuis Godot 3.x — gotcha nommage asymétrique long-standing, pas breaking 4.x. Setter sur `compressor.attack` ou `compressor.release` no-op silencieusement (sets non-existent prop sans erreur). AC-AUD-01 (d) assertions restent valides tel quel — seule la prose explicative GDD corrigée (ligne 3 status block + Phase D.5 block + footer Tracker bloc).

**Fichiers modifiés**: 4 (engine-ref `audio.md` +85 lignes ; `audio-system.md` 4 surgical edits Phase D.5 block + ligne 3 + ligne 767 + ligne 780 ; `systems-index.md` ligne 23 segment Phase D.5 ; `active.md` Session Extract prepend).

**Status**: Phase D.5 Tracker (Open Question) → ✅ RESOLVED. Pré-requis Sprint Audio implementation levé. Tests `tests/integration/audio/audio_boot_test.gd` débloqués pour AC-AUD-01 (d).

---

## Review — 2026-05-03 (r2.3 re-review post Phase C+D auto-completion) — Verdict: NEEDS REVISION → APPROVED r2.3 (8 fixes appliqués directement)

**Scope signal**: M (surgical — Phase C+D pure formalisation impl/hardening, pas de redesign architectural ; ~50 lignes GDD édités)
**Specialists**: audio-director, qa-lead, godot-specialist, game-designer (4 agents parallèles adversariaux — creative-director synthesis skipped, convergence forte specialists + Fantasy game-designer APPROVED dès le départ)
**Mode**: `/design-review audio-system` fresh session post Phase C+D auto-completion 2026-05-03 + `/consistency-check audio-system` PASS 2026-05-03
**Blocking items identifiés**: 8 (5 haute convergence multi-specialists + 3 qa-lead unique legitimate) | Recommended: 6 | Action: 8/8 fixes appliqués immédiatement (Option A, pattern r2.1)
**Prior verdict resolved**: APPROVED r2.1 Phase A+B (2026-04-27) → r2.2 amendement éditorial NB-CRD-6 secret collect (2026-04-28) → r2.2 Phase A+B+C+D complete + consistency PASS (2026-05-03) → r2.3 surgical Phase C+D coverage (2026-05-03 fresh re-review)

### Summary

Phase C+D (formules hardening F-01/F-02/F-04 + impl details D.1-D.5) auto-complétées 2026-05-03 en chain auto-mode post-Combat audit. `/consistency-check` a passé sans amendement registry. Fresh `/design-review` re-review déclenché pour verdict APPROVED formel sur r2.3 — convergence forte 4 specialists sur 5 BLOCKING + 3 qa-lead legitimate, tous corrigeables ≤ 30 min (pattern r2.1 réplique).

**Convergence multi-specialists** (5 BLOCKING) :

1. **D.3 `_active_clac_players` orphan tracker** (audio-director B-2 + godot-specialist B-3 + game-designer R-3) — round-robin `stop()` forcé sur slot avec clac actif n'émet pas `finished` signal, `CONNECT_ONE_SHOT` ne fire pas, `_active_clac_players[slot_idx]` reste `true` orphelin → slot exclu permanent du pitch shift slow-mo, casse Couche 4 intermittently. **FIX** : (a) `erase(slot_idx)` AVANT `stop()` dans saturation guard `play_3d_at` ; (b) cleanup pré-connect si `_active_clac_players.has(slot_idx)` (slot recyclé) ; (c) `Dictionary[int, bool]` typed Godot 4.4+ ; (d) defensive disconnect dans `_on_clac_finished` au cas où one-shot pas tiré.

2. **`attack_us` API verification trou** (audio-director #4 + qa-lead #7 + godot-specialist B-1 + game-designer R-4) — Godot 4.6 prop = `attack_us` (microseconds) vs Godot 4.3 = `attack` (ms), breaking change. Si impl utilise `.attack`, setter silently no-ops en GDScript (dynamic property), compressor s'instancie avec attack default ~10 ms, AC-AUD-01 passe car ne vérifie que `sidechain` — bug fonctionnel invisible. Engine-ref `audio.md` ne documente pas `AudioEffectCompressor` (Phase D.5 tracker open). **FIX** : AC-AUD-01 (d) enrichi `compressor.attack_us == 5000`, `compressor.release_ms == 200.0`, `threshold == -24.0`, `ratio == 4.0` avec failure message explicite si prop manquante. Formula 6 table renommée `attack → attack_us [1000, 20000] µs` + `release → release_ms`. Phase D.5 reste tracker pré-Sprint Audio engine-ref dump.

3. **F-04 swell midpoint** (audio-director #1 BLOCKING vs game-designer R-1 RECOMMENDED) — linear-amplitude lerp produit `+3 dB perçu` au midpoint pour signaux décorrélés (sub-bass synthwave Chrome Zen partiellement corrélés peuvent amplifier au-delà). Tuning knob `ambient_crossfade_curve LINEAR | EQUAL_POWER` existe mais default LINEAR + note "escalader si playtest" = bandaid systémique sur projet indie solo. **FIX compromis** : default reste LINEAR (impl simple Phase D), MAIS Sprint Audio Day 1 test A/B `LINEAR vs EQUAL_POWER` cosinus sur tracks réelles à -12 dB ambient **BLOCKING** ; bascule default `EQUAL_POWER` AVANT release candidate si swell détecté. Pas de "plus tard" — gate-checked Sprint Audio.

4. **AC-AUD-Sidechain double-boot non formalisé** (qa-lead #3 + game-designer R-2) — Phase D.2 mentionne en prose ligne 240 "VC-9 updated — double boot test" mais aucun AC numéroté formel. Section ACs (lignes 638-732) ne contenait pas AC pour idempotency Phase D.2. Régression silencieuse possible (compressor 2× ratio 8:1 en cascade → `-6 dB` ducking effective vs `-3 dB` nominal → music inaudible ~400 ms post-kill). **FIX** : **AC-AUD-20 nouveau** `[Logic — BLOCKING]` couvre (a) `effect_count == 1` après double-call, (b) `push_warning` capturé, (c) propriétés intactes (effet original pas écrasé), (d) failure mode message explicite si guard absent.

5. **F-04 midpoint AC manquant** (qa-lead #5 + audio-director #1 cross-flagged) — Phase C corrige le dip dB-domain (-40 dB midpoint old → -6 dB midpoint new linear-amplitude) mais aucun AC ne vérifie le fix. Régression silencieuse possible (impl utilise lerp dB-domain par habitude). **FIX** : **AC-AUD-21 nouveau** `[Logic — BLOCKING]` couvre (a) `t=0` baseline, (b) midpoint `-6 dB ± 1 dB` (proof Phase C linear-amplitude appliqué), (c) anti-regression message "F-04 dB-domain lerp détecté" si midpoint observé `-40 dB`, (d) `t=1.0` swap final, (e) boundary `D=0` swap instantané.

**Qa-lead unique BLOCKING legitimate** (3) :

6. **F-01/F-02 boundary ACs** — guards Phase C (`D ≤ 0 → SILENCE_DB`, `R ≤ 0 → NOMINAL_DB`) sans coverage AC = dead code non vérifié CI. **FIX** : AC-AUD-04 (e)(f) + AC-AUD-06 (e)(f) sous-assertions `D=0`/`D=-1`/`R=0`/`R=-1` boundary + `push_warning` capture.

7. **AC-AUD-13 sub-budgets handler isolés** — Phase D.4 spec budgets `_on_enemy_killed < 0.1 ms` + `play_3d_at < 0.05 ms` non couverts par AC-AUD-13 frame-global. **FIX** : sous-assertions (e)(f)(g) — handler isolé `Time.get_ticks_usec()` wrap, play_3d_at isolé, sidechain CPU `< 0.5%` (ADVISORY conditional Performance.AUDIO monitor).

8. **AC-AUD-15 split BLOCKING/ADVISORY mixed** — l'ancien AC-AUD-15 (a-e) était BLOCKING global avec (c) FFT `AudioEffectRecord` rétrogradant en ADVISORY conditional headless = contradiction Gate Level. **FIX** : split AC-AUD-15-a `[Integration — BLOCKING]` (a/b/b'/d/e — headless-testable, pitch_scale assertions) + AC-AUD-15-b `[Visual/Feel — ADVISORY]` (c — FFT anti-pop, evidence Sprint Audio playtest si headless). Tolérance (b') corrigée pour multi-kill rang `pitch_scale ∈ {1.0, 1.122, 1.260} ± 0.005` (pas unconditionally 1.0 qui ferait FAIL multi-kill slow-mo).

### Specialists' BLOCKING tally (8 total — convergence forte 5 multi + 3 qa unique)

| Source | Count | Top finding |
|---|---|---|
| audio-director | 2 BLOCKING + 3 RECOMMENDED + 3 NICE | F-04 EQUAL_POWER default + D.3 orphan tracker (verdict NEEDS_REVISION) |
| qa-lead | 7 BLOCKING + 3 RECOMMENDED | F-01/F-02 boundary ACs + AC-AUD-20 double-boot + AC-AUD-21 F-04 midpoint + AC-AUD-13 sub-budgets + AC-AUD-15 split + attack_us check (verdict NEEDS_REVISION) |
| godot-specialist | 2 BLOCKING + 5 RECOMMENDED | engine-ref `audio.md` AudioEffectCompressor manquant + D.3 orphan tracker (verdict NEEDS_REVISION) |
| game-designer | 0 BLOCKING + 4 RECOMMENDED + 3 NICE | Couches 1-4 préservées Phase C+D — APPROVED dès le départ (verdict APPROVED) |

(Items cross-flagged par plusieurs specialists agrégés en 8 unique : 5 haute convergence + 3 qa-lead legitimate unique.)

### Adjudications r2.3 — Action immédiate (skip re-review fresh, pattern r2.1)

Pas d'adjudication CD nécessaire — convergence forte specialists sur fixes surgicaux, aucun design re-decision. Phase A+B vision préservée intact (game-designer APPROVED). Tous les BLOCKING sont :
- Implementation hardening (D.3 orphan tracker, attack_us API check)
- AC coverage formel pour guards déjà spécifiés (F-01/F-02 boundary, AC-AUD-20 double-boot, AC-AUD-21 F-04 midpoint, AC-AUD-13 sub-budgets, AC-AUD-15 split)
- Tooling decision compromis (F-04 EQUAL_POWER Sprint Audio gate, pas re-design)

Verdict skill : NEEDS REVISION → fixes appliqués directement Option A (auto-approve solo mode + Martin standing directive auto-approve recommended) → **status APPROVED r2.3**.

### Files modified r2.3

- `design/gdd/audio-system.md` (~80 lignes éditées) :
  - Status block top (ligne 3 + ligne 20 dates) → r2.3
  - Phase D.1 `play_3d_at` pseudo-code (lignes 199-216) — `bus = bus` direct, `_active_clac_players.erase(slot_idx)` avant `stop()` saturation
  - Phase D.3 pseudo-code (lignes 248-280) — typed Dictionary, pre-connect cleanup, defensive disconnect
  - F-04 hardening note (ligne 410) — EQUAL_POWER compromis Sprint Audio test A/B BLOCKING
  - Formula 6 table (lignes 458-461) — `attack → attack_us [1000, 20000] µs` + `release → release_ms`
  - AC-AUD-01 (ligne 660) — enrichi attack_us/release_ms/threshold/ratio verification + failure message
  - AC-AUD-04 (ligne 670) — sous-assertions (e)(f) boundary `D=0`/`D=-1`
  - AC-AUD-06 (ligne 678) — sous-assertions (e)(f) boundary `R=0`/`R=-1`
  - AC-AUD-13 (ligne 692) — sous-assertions (e)(f)(g) sub-budgets handler/play_3d_at/sidechain CPU
  - AC-AUD-15 split (lignes 698-711) — 15-a BLOCKING headless-testable + 15-b ADVISORY FFT anti-pop
  - **AC-AUD-20 nouveau** (post-19) — Phase D.2 idempotent guard formal coverage
  - **AC-AUD-21 nouveau** (post-AC-AUD-20) — F-04 linear-amplitude midpoint anti-regression Phase C

### Cross-system insights

- **Engine-ref Phase D.5 tracker** : `docs/engine-reference/godot/audio.md` doit recevoir section `AudioEffectCompressor` AVANT Sprint Audio (props `attack_us` µs, `release_ms` ms, `threshold` dB, `ratio` float, `sidechain` String) — promu de "tracker open question" à **pré-requis BLOCKING Sprint Audio implementation**. AC-AUD-01 (d) failure message renvoie vers ce gap.
- **Combat 020 unblock** : Phase A+B+C+D + r2.3 fixes = formules hardened + impl patterns concrets + ACs testables. MockAudioHandler côté Combat peut implémenter AC-CMB-51 / AC-CMB-audio-01 / AC-CMB-audio-02 sans attendre AudioSystem impl pleine. Story 020 reste `Ready` (flippé 2026-05-03 post consistency-check).
- **F-04 EQUAL_POWER decision** : compromis audio-director vs game-designer adjudiqué inline GDD — pas d'adjudication CD requise. Sprint Audio gate explicite.

### Key insight (carry forward)

Le pattern "Phase C+D auto-completion en chain auto-mode → fresh re-review post-completion → fixes surgicaux multi-specialists" est efficace : 4 specialists ont identifié 8 BLOCKING distincts mais convergent sur 5 hauts (D.3 orphan, attack_us, F-04 swell, double-boot AC, F-04 midpoint AC) — la convergence rend les fixes obvious et non-controversés. **Pour futures Phase C+D auto-completions** : toujours déclencher `/design-review` fresh post-auto-completion AVANT de marquer APPROVED — l'auto-completion peut introduire des trous AC coverage et des ambiguïtés API qu'un single-session re-review révèle systématiquement. Ce pattern protège contre "auto-completion = approved by default".

### Reports

- Synthesis r2.3 : ce review log (creative-director skipped — convergence specialists forte, pas de design re-decision, fixes surgicaux purement spec/AC)
- ADR-0009 binding : `docs/architecture/adr-0009-audio-system-architecture.md` (Accepted 2026-04-27 + r2 amendements D-1/D-3 + r2.1 amendment D-6 — pas d'amendement r2.3 requis, fixes restent intra-GDD)

---

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
