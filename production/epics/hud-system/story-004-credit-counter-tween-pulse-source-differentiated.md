# Story 004: Credit Counter Tween Pulse Source-Differentiated (r1.1 amendement)

> **Epic**: HUD System
> **Status**: Complete 2026-05-05 (6/6 GdUnit4 PASS — AC-HUD-36 (a)(b)(c)(d)(e) + Wall-clock OQ-HUD-5 ; cumulé HUD 30/30 PASS — story-001 6 + story-002 12 + story-003 6 + story-004 6)
> **Layer**: Presentation
> **Type**: Logic
> **Manifest Version**: 2026-05-04
> **Estimate**: S (2-3 h, durée tween différenciée + invariant balance + wall-clock)

## Context

**GDD**: `design/gdd/hud-system.md` (In Design r1.1 — amendement r2.2 cascade NB-CRD-6 Option A 2026-04-28)
**Requirement**: R-HUD-5 (pulse différencié source KILL/SECRET — corps complet ici), F-HUD-1 (formula durée différenciée + magnitude + easing + wall-clock invariance OQ-HUD-5).
*(TR-hud-* IDs non encore présents dans `tr-registry.yaml` — référence directe R-HUD/F-HUD/AC-HUD GDD r1.1.)*

**ADR Governing Implementation**:
- **ADR-0001** (Physics rate 60 Hz) — pulse Tween wall-clock `set_ignore_time_scale(true)` — quand Combat slow-mo `Engine.time_scale = 0.3` au même tick que kill, le pulse HUD reste 100/150 ms wall-clock (pas time_scaled 333/500 ms perçus).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `Tween.set_ignore_time_scale(true)` API stable Godot 4.0+ (renommée depuis `Tween.tween_method(time_scale=...)` 3.x). Easing `EASE_IN_OUT` + `TRANS_SINE` enum stables.

**Control Manifest Rules (Presentation layer)**:
- Required : durée `CREDIT_COUNTER_TWEEN_KILL_MS = 100` ms / `CREDIT_COUNTER_TWEEN_SECRET_MS = 150` ms ; magnitude `PULSE_SCALE_MAGNITUDE = 1.05` identique KILL/SECRET MVP ; easing `Tween.EASE_IN_OUT` + `Tween.TRANS_SINE` ; `set_ignore_time_scale(true)` wall-clock invariance.
- Forbidden : durée hardcodée hors constantes nommées (anti-magic-number) ; easing `BOUNCE` / `ELASTIC` / `SPRING` (anti-Chrome Zen K.5) ; magnitude > `1.10` ou < `1.02` (anti-Pillar 1/2 hors safe range).
- Guardrail : invariant balance `tween_secret.duration > tween_kill.duration` strictement (différenciation perceptive Pillar 4 viscéralité — assert au runtime debug-only).

---

## Acceptance Criteria

*From GDD §Acceptance Criteria r1.1, scoped à cette story (Logic) :*

- [x] **AC-HUD-36** [BLOCKING][AUTO] (r1.1 — pulse durée différenciée par source) **GIVEN** HUD initialisé en `State.PLAYING`, spy injecté sur `Tween.tween_property(Label, "scale", ...)`. **WHEN** deux signals `credits_changed` séquentiels émis : (1) `credits_changed(N+1, +1, SourceKind.KILL)` puis (2) `credits_changed(N+6, +5, SourceKind.SECRET)` 500 ms plus tard (pas de chevauchement). **THEN** :
    - **(a)** Le tween du 1er signal (KILL) a `duration ≈ 0.100 s ± 0.005 s` (`CREDIT_COUNTER_TWEEN_KILL_MS / 1000`).
    - **(b)** Le tween du 2e signal (SECRET) a `duration ≈ 0.150 s ± 0.005 s` (`CREDIT_COUNTER_TWEEN_SECRET_MS / 1000`).
    - **(c)** **Invariant balance** : `tween_secret.duration > tween_kill.duration` strictement. Pas d'égalité, pas d'inversion. Si invariant violé : FAIL avec message "Pillar 4 différenciation perceptive cassée — secret pulse durée doit dépasser kill pulse durée".
    - **(d)** Magnitude pic de scale `(1.05, 1.05)` identique pour les deux tweens (différenciation magnitude réservée Tier 2+).
    - **(e)** **Edge case `tween.kill()` collision** : si un 3e signal `credits_changed(... KILL)` arrive pendant que le tween (b) SECRET est encore en cours, le tween SECRET est `kill()` et un nouveau tween KILL démarre avec `duration ≈ 0.100 s`. La durée du tween courant reflète toujours le `source` du dernier signal reçu.
- [x] **Wall-clock invariance OQ-HUD-5** : durée 100ms (KILL) ou 150ms (SECRET) reste wall-clock indépendant de `Engine.time_scale` — vérifié via test simulant `Engine.time_scale = 0.3` au même tick que kill ; pulse atteint pic à `~50ms` (KILL) ou `~75ms` (SECRET) wall-clock measured via `Time.get_ticks_msec()`.

---

## Implementation Notes

1. **Constantes nommées** dans `src/gameplay/hud/hud_system.gd` :
   ```gdscript
   const CREDIT_COUNTER_TWEEN_KILL_MS: int = 100
   const CREDIT_COUNTER_TWEEN_SECRET_MS: int = 150
   const PULSE_SCALE_MAGNITUDE: float = 1.05

   # Référence enum SourceKind (à confirmer via Credit Economy registry au moment d'impl)
   # const SourceKind = preload("res://src/gameplay/credit/credit_economy.gd").SourceKind
   # SourceKind.KILL == 0, SECRET == 1, SPEND_SHOP == 2, BOOT_HYDRATE == 3
   ```

2. **Helper `_start_pulse_tween(source: int)` upgrade depuis story-002 stub** :
   ```gdscript
   func _start_pulse_tween(source: int) -> void:
       # Multi-kill collision (AC-HUD-07/19/20 + AC-HUD-36 (e)) — kill tween précédent
       if _active_pulse_tween != null and _active_pulse_tween.is_valid():
           _active_pulse_tween.kill()

       # R-HUD-5 r1.1 — durée différenciée par source
       var duration_ms: int = CREDIT_COUNTER_TWEEN_KILL_MS  # default KILL (et SPEND_SHOP traité ailleurs)
       if source == 1:  # SourceKind.SECRET
           duration_ms = CREDIT_COUNTER_TWEEN_SECRET_MS

       # Invariant balance debug-only assert (AC-HUD-36 (c))
       assert(CREDIT_COUNTER_TWEEN_SECRET_MS > CREDIT_COUNTER_TWEEN_KILL_MS, \
           "Pillar 4 différenciation perceptive cassée — secret pulse durée doit dépasser kill pulse durée")

       var half_duration: float = (duration_ms / 1000.0) / 2.0

       _active_pulse_tween = create_tween()
       _active_pulse_tween.set_ignore_time_scale(true)  # OQ-HUD-5 wall-clock R-HUD-5 invariance
       _active_pulse_tween.tween_property(_credit_counter_label, "scale", \
           Vector2(PULSE_SCALE_MAGNITUDE, PULSE_SCALE_MAGNITUDE), half_duration) \
           .set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
       _active_pulse_tween.tween_property(_credit_counter_label, "scale", Vector2.ONE, half_duration) \
           .set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
   ```

3. **Wall-clock invariance OQ-HUD-5 RESOLU MVP** — recommandation `set_ignore_time_scale(true)`. Test edge case slow-mo : simuler `Engine.time_scale = 0.3` au tick d'émission `credits_changed(N+1, +1, KILL)` ; mesurer `Time.get_ticks_msec()` avant et à `Tween.finished` ; verify `delta ∈ [95, 110]` ms wall-clock (pas 333 ms time_scaled).

4. **EC-HUD-05 multi-kill 3 emits différenciés** : si 3 emits séquentiels arrivent dans le même tick avec sources mixtes (e.g. 2 KILL + 1 SECRET), le tween courant à chaque emit reflète le `source` du dernier signal. Test : `credits_changed.emit(11, 1, KILL); credits_changed.emit(12, 1, KILL); credits_changed.emit(17, 5, SECRET)` → tween final durée 150ms.

5. **AC-HUD-36 (a)(b) tolerance ±0.005 s** : durée Tween Godot mesurée via `Tween.get_total_elapsed_time()` ou `Tween.finished` signal timestamp. Tolerance 5ms absorbe la précision physics tick 16.6 ms / 2.

6. **Verbose log** : `print("[HUD] pulse source=%d duration_ms=%d" % [source, duration_ms])` (debug-only).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here :*

- Listener `_on_credits_changed` body (hard set Label.text + branch SPEND_SHOP/BOOT_HYDRATE) — story-002.
- Visibility state machine + tween kill PAUSED — story-003.
- Lints statiques (R-HUD-12/13 alloc hot path) — story-005.
- Visual/Feel frame-perfect playtest evidence — story-006 (audio-009 cross-reference Audio Rule 17 +5 semitones SECRET).

---

## QA Test Cases

*Logic — automated GdUnit4 tests requis :*

**AC-HUD-36 (a)** : KILL tween duration ≈ 0.100 s
- Setup : `_ready()` terminé. State.PLAYING. Counter `N=10`. Spy `Tween.tween_property` capture.
- Action : `credits_changed.emit(11, 1, SourceKind.KILL)`. Mesurer `Time.get_ticks_msec()` au démarrage tween puis à `tween.finished` signal.
- Verify : `delta_ms ∈ [95, 105]` (tolerance ±5 ms).

**AC-HUD-36 (b)** : SECRET tween duration ≈ 0.150 s
- Setup : Counter `N=10`. State.PLAYING.
- Action : `credits_changed.emit(15, 5, SourceKind.SECRET)`. Mesurer durée tween.
- Verify : `delta_ms ∈ [145, 155]`.

**AC-HUD-36 (c)** : Invariant balance secret > kill
- Setup : tests (a) et (b) ci-dessus exécutés.
- Verify : `kill_duration < secret_duration` strictement (pas d'égalité, pas d'inversion).
- Pass message si fail : "Pillar 4 différenciation perceptive cassée — secret pulse durée doit dépasser kill pulse durée".

**AC-HUD-36 (d)** : Magnitude identique 1.05
- Setup : tests (a) et (b) ci-dessus.
- Verify : capturé via spy `Tween.tween_property` arg `final_val == Vector2(1.05, 1.05)` pour les deux tweens.

**AC-HUD-36 (e)** : Collision tween.kill() durée du dernier source
- Setup : `credits_changed.emit(11, 1, KILL)` (tween KILL démarre 100ms). 50ms plus tard, `credits_changed.emit(16, 5, SECRET)` (tween SECRET démarre 150ms — tween KILL killed).
- Verify : durée du tween courant `== 0.150 s` (SECRET — dernier source). KILL tween `is_valid() == false`.
- Edge : 80ms après SECRET start, `credits_changed.emit(17, 1, KILL)` → tween courant `== 0.100 s` KILL.

**Wall-clock invariance OQ-HUD-5** : slow-mo time_scale=0.3
- Setup : `Engine.time_scale = 0.3`. State.PLAYING. Counter `N=10`.
- Action : `credits_changed.emit(11, 1, KILL)`. Mesurer wall-clock `Time.get_ticks_msec()`.
- Verify : `delta_ms ∈ [95, 110]` (wall-clock, pas time_scaled 333 ms). `Tween.set_ignore_time_scale(true)` confirmé via `_active_pulse_tween.is_ignoring_time_scale() == true` (Godot 4.6 API si exposed).
- Cleanup : `Engine.time_scale = 1.0` après test.

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- `tests/integration/hud/credit_counter_pulse_source_diff_test.gd` (NEW, ~200 lignes) — chemin référencé GDD AC-HUD-36 ligne 581. Couvre AC-HUD-36 (a)(b)(c)(d)(e) + wall-clock invariance.
- Smoke check : test suite green run via GdUnit4 headless.

**Status**: [x] Created — `tests/integration/hud/credit_counter_pulse_source_diff_test.gd` (332 lignes, 6 functions, 6/6 PASS exit 0 — `reports/report_422/results.xml` 2026-05-05).

---

## Dependencies

- **Hard upstream** : story-001 Complete (autoload skeleton) ; story-002 Complete (handler `_on_credits_changed` body + helper `_start_pulse_tween` stub durée fixe — cette story upgrade le helper avec durée différenciée).
- **Soft upstream** : Credit Economy Rule 13 enum SourceKind défini.
- **Cross-reference Audio** : cohérent Audio Rule 17 r2.2 (clac aigu pitch +5 semitones bus `SFX` pour `secret_collected`) — la **durée plus longue** du pulse HUD est l'extension visuelle du **timbre plus long perçu** côté audio. Cascade NB-CRD-6 Option A creative-director adjudication 2026-04-28.
- **Unlocks** : story-005 (lints peuvent vérifier constantes nommées present + magnitude ≤ 1.05) ; story-006 (playtest evidence frame-perfect cumule kill + secret).

---

## Completion Notes
**Completed**: 2026-05-05
**Criteria**: 6/6 passing (AC-HUD-36 (a)(b)(c)(d)(e) + Wall-clock invariance OQ-HUD-5 — auto-verified via `Time.get_ticks_msec()` mesures + `Tween.finished` await + `override_failure_message` AC-ID traceability)
**Deviations**: None.
**Test Evidence**: `tests/integration/hud/credit_counter_pulse_source_diff_test.gd` (332 lignes, 6 functions). Cumulé HUD : 30/30 PASS exit 0 / 2.93s (6 boot + 12 listener + 6 visibility + 6 pulse).
**Code Review**: Complete — APPROVED. Suggestion non-bloquante : `if source == 1` → const `_SOURCE_KIND_SECRET = 1` (cosmétique, parité `_STATE_PAUSED`).
**Implementation note**: 3 constantes module-level ajoutées (`CREDIT_COUNTER_TWEEN_KILL_MS=100`, `CREDIT_COUNTER_TWEEN_SECRET_MS=150`, `PULSE_SCALE_MAGNITUDE=1.05`). Param `_source` → `source` (utilisé). `assert(SECRET_MS > KILL_MS)` debug-only invariant Pillar 4 anti-régression numérique. Test `Engine.time_scale=0.3` slow-mo confirme wall-clock invariance OQ-HUD-5.
