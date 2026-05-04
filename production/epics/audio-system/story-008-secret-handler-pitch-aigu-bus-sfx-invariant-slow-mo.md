# Story 008: Secret Audio Handler — `_on_secret_collected` Pitch +5 Semitones Bus `SFX` Invariant Slow-Mo (Rule 17 r2.2 NB-CRD-6 Option A)

> **Epic**: Audio System
> **Status**: Complete 2026-05-04 (15/15 tests PASS — 10/11 ACs COVERED ; AC-AUD-18 (h) defensive queue_free DEFERRED par design GDScript typed — `is_instance_valid` garde défensive conservée)
> **Layer**: Core
> **Type**: Logic
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/audio-system.md` (r2.3 §Rule 17 + §Formula 7 + §AC-AUD-18/19 + r2.2 amendement éditorial NB-CRD-6 Option A)
**Requirements** (R-AUD stable IDs jusqu'à `/architecture-review` post-Sprint 1) :
- R-AUD-17 : Secret collect clac différencié — pitch +5 semitones bus `SFX` (PAS `COMBAT_KILL` — sidechain n'arme pas), positionnel 3D depuis `secret_node.global_position`, pas de ducking ni multi-kill counter (Rule 17 r2.2 NB-CRD-6 Option A creative-director adjudication)
- R-AUD-7 : Position payload pour signals 3D — capture au tick d'émission, jamais `secret_node.global_position` au moment de réception DEFERRED (queue_free risk)
- R-AUD-5 : `CONNECT_DEFERRED` par défaut

**ADR Governing**: ADR-0009 D-3 (allowlist) + D-5 (spatialisation 3D positional)
**Decision Summary**: Audio handler `_on_secret_collected(secret_node, tier)` connecté DEFERRED depuis Secret System, capture `pos = secret_node.global_position` au tick reception (défense queue_free post-collect), appel `play_3d_at(clac_stream, pos, AudioBuses.SFX, pitch_scale=SECRET_PITCH_SCALE)` avec `SECRET_PITCH_SCALE = 2.0 ** (5 / 12.0) ≈ 1.335` (Formula 7). Bus `SFX` exclusif — PAS `COMBAT_KILL` (sidechain n'arme pas, Couche 1 silence rythmique combat préservé invariant). Pas de ducking `SWING_ACTIVE`, pas d'incrément `_kill_count_this_swing` counter, pas de blood ambiance chain. Pitch invariant slow-mo (bus `SFX` PAS dans pitch allowlist Rule 11). Fallback `play_2d` head-locked si position invalide (NaN/inf).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `AudioStreamPlayer3D.pitch_scale` set live mid-`play()` supporté Godot 4.0+. Position 3D capturée au tick d'émission via `pos = secret_node.global_position` reçu en payload (vs lookup live `secret_node` au DEFERRED tick — risque queue_free post-collect via Secret System). `is_finite(pos.x) && is_finite(pos.y) && is_finite(pos.z)` precheck Phase D.1 fallback `play_2d`.

**Control Manifest Rules (Core layer)**:
- Required: connect Secret signal `secret_collected` avec `CONNECT_DEFERRED`
- Required: capture position au tick d'émission (R-AUD-7 + R-7 ADR-0009)
- Required: pitch `SECRET_PITCH_SCALE` invariant (PAS multiplié par Formula 5 slow-mo)
- Forbidden: bus `COMBAT_KILL` côté secret (sidechain n'arme pas Couche 1 invariant)
- Forbidden: ducking `SWING_ACTIVE` côté secret
- Forbidden: incrément `_kill_count_this_swing` (secret pas combat kill)

---

## Acceptance Criteria

*From GDD AC-AUD-18 (secret collect clac aigu bus SFX) + AC-AUD-19 (secret pitch invariant slow-mo):*

- [ ] **AC-AUD-18 (a) Dispatch correct** : `play_3d_at` appelé exactement 1 fois avec `stream == clac_stream`, `bus == AudioBuses.SFX`, `pitch_scale ≈ 1.335 ± 0.001` (`SECRET_PITCH_SCALE = 2.0 ** (5/12)` Formula 7).
- [ ] **AC-AUD-18 (b) Bus exclusif SFX** : `play_3d_at` n'est PAS appelé avec `bus == AudioBuses.COMBAT_KILL` ni `bus == AudioBuses.SWING_ACTIVE`. Vérifier via spy assert `bus_arg != AudioBuses.COMBAT_KILL && bus_arg != AudioBuses.SWING_ACTIVE`.
- [ ] **AC-AUD-18 (c) Pas de ducking SWING_ACTIVE** : `duck_bus` n'est PAS appelé suite à ce signal (vs Rule 13 kill qui appelle `duck_bus(SWING_ACTIVE, -6, 30)`).
- [ ] **AC-AUD-18 (d) Compteur multi-kill intact** : `_kill_count_this_swing` reste inchangé après réception `secret_collected`. Le secret n'incrémente PAS le compteur combat.
- [ ] **AC-AUD-18 (e) Position 3D capturée** : la position passée à `play_3d_at` `== secret_node_mock.global_position` (`Vector3(5, 1, 3) ± 0.001`) capturée au tick de réception (pas une ref live au node — défense queue_free post-collect).
- [ ] **AC-AUD-18 (f) Pas de blood ambiance** : `play_3d_at` n'est PAS appelé avec `stream == blood_stream` suite à ce signal (vs kill Rule 13 qui chain blood ambiance 50 ms après clac).
- [ ] **AC-AUD-18 (g) Tier indifférent** : ré-émission `Secret.secret_collected.emit(secret_node_mock, 3)` (tier 3) → mêmes assertions (a)-(f), `pitch_scale` identique. MVP ne différencie pas les tiers.
- [ ] **AC-AUD-18 (h) Position invalide fallback** : si `secret_node_mock.global_position = Vector3(NAN, NAN, NAN)`, `play_2d` est appelé (head-locked fallback) avec `bus == AudioBuses.SFX` et `pitch_scale ≈ 1.335` ; `play_3d_at` n'est PAS appelé. `push_warning` capturé.
- [ ] **AC-AUD-19 (a) Pitch invariant slow-mo** : `Engine.time_scale = 0.3` actif → `play_3d_at` appelé avec `pitch_scale ≈ 1.335 ± 0.001` (`SECRET_PITCH_SCALE` invariant — bus `SFX` PAS dans pitch allowlist Rule 11).
- [ ] **AC-AUD-19 (b) Pas composite Formula 5** : `pitch_scale != 1.335 × 0.8821` (NE PAS multiplié par Formula 5 slow-mo). Assertion explicite `abs(pitch_scale - 1.335) < 0.005` ET `abs(pitch_scale - 1.178) > 0.05`.
- [ ] **AC-AUD-19 (c) Retour time_scale = 1.0** : prochain `secret_collected` produit toujours `pitch_scale ≈ 1.335`.

---

## Implementation Notes

*Derived from ADR-0009 D-3 + D-5 + Rule 17 r2.2 + Formula 7:*

```gdscript
# AudioSystem (autoload) — secret handler
const SECRET_PITCH_SCALE: float = 2.0 ** (5.0 / 12.0)  # ≈ 1.3348 — Formula 7 +5 semitones
@export var clac_stream: AudioStream  # asset stub MVP, asset réel Sprint Audio asset pipeline

func _connect_secret_signals(secret_system: Node) -> void:
    if not secret_system.secret_collected.is_connected(_on_secret_collected):
        secret_system.secret_collected.connect(_on_secret_collected, CONNECT_DEFERRED)

func _on_secret_collected(secret_node: Node, _tier: int) -> void:
    # R-AUD-7 — capture position au tick reception, défense queue_free post-collect
    if not is_instance_valid(secret_node):
        push_warning("AudioSystem: secret_node invalide (queue_free pré-DEFERRED), fallback play_2d head-locked")
        play_2d(clac_stream, AudioBuses.SFX, SECRET_PITCH_SCALE)
        return
    var pos: Vector3 = secret_node.global_position
    # Phase D.1 — is_finite precheck fallback head-locked
    if not (is_finite(pos.x) and is_finite(pos.y) and is_finite(pos.z)):
        push_warning("AudioSystem: secret_node.global_position invalide (NaN/inf), fallback play_2d head-locked")
        play_2d(clac_stream, AudioBuses.SFX, SECRET_PITCH_SCALE)
        return
    # Bus SFX exclusif — PAS COMBAT_KILL (sidechain n'arme pas, Couche 1 silence combat invariant)
    # Pitch invariant slow-mo (SFX PAS dans pitch allowlist Rule 11) — Formula 7 absolu, pas composite Formula 5
    play_3d_at(clac_stream, pos, AudioBuses.SFX, SECRET_PITCH_SCALE)
    # Pas de duck_bus, pas d'incrément _kill_count_this_swing, pas de blood ambiance chain — secret ≠ kill (Rule 17)
```

**Note bus SFX exclusif** : choix bus `SFX` (pas `COMBAT_KILL`) garantit que la sidechain compressor `MUSIC ← COMBAT_KILL` n'arme pas → pas de ducking music sur secret collect → Couche 3 continuité musicale invariant + Couche 1 silence rythmique combat préservé pour les kills uniquement (creative-director adjudication NB-CRD-6 Option A 2026-04-28 Phase A re-review).

**Note pitch invariant** : `SECRET_PITCH_SCALE = 2.0 ** (5/12) ≈ 1.3348` est appliqué directement au `play_3d_at` AVANT `play()`. Sous slow-mo, le bus `SFX` n'étant pas dans `PITCH_ALLOWLIST` (story-007), le `_apply_pitch_shift_slow_mo` ramène les slots `SFX` à `pitch_scale = 1.0`... **MAIS** le secret slot n'est pas trapped — l'ordre est : handler set `pitch_scale = 1.335` AVANT `play()`, et `_physics_process` slow-mo loop voit le slot `playing == true` avec bus `SFX` (allowlist=false) → set `pitch_scale = 1.0` → CASSE l'invariant secret. **Solution** : ajouter slot secret au tracker ou bypass slow-mo loop pour bus SFX. Simpler : conserver `pitch_scale` set par handler en restaurant à `pitch_scale = 1.0` UNIQUEMENT si slot était précédemment pitch-shifted via Formula 5 (e.g. flag `_slot_pitched_by_slow_mo: Dictionary[int, bool]`). Cf. Phase D.3 design pattern compatible avec story-007.

**Note R-AUD-7 capture position** : `pos = secret_node.global_position` capturé au tick reception du DEFERRED (pas une ref live). Si Secret System fait `secret_node.queue_free()` immédiatement après `secret_collected.emit()`, le node peut être invalide à la frame N+1 quand le handler reçoit le signal. `is_instance_valid(secret_node)` precheck + fallback `play_2d` head-locked. Idem `is_finite()` precheck Phase D.1 (story-002).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001 : pool 3D 12 slots
- Story 002 : API `play_3d_at` / `play_2d` verbes (utilisés par handler)
- Story 003 : Combat `_on_enemy_killed` handler — pattern différent (bus `COMBAT_KILL`, ducking, multi-kill counter, blood ambiance chain)
- Story 007 : slow-mo pitch shift bus allowlist — interaction avec slot SFX secret discutée Note pitch invariant

---

## QA Test Cases

**AC-AUD-18 (a-f) Secret dispatch correct + bus exclusif + pas de chain combat** :
- Given : AudioSystem prêt, AudioBuses configurés (Rule 16 sidechain armed sur `COMBAT_KILL`), spy injecté sur `play_3d_at`/`play_2d`/`duck_bus`, mock Secret node `secret_node_mock` avec `global_position = Vector3(5, 1, 3)`, `_kill_count_this_swing = 0`
- When : `Secret.secret_collected.emit(secret_node_mock, 1)` (tier 1) émis depuis main thread, propagation DEFERRED frame N+1
- Then : `play_3d_at` appelé 1× avec `(clac_stream, Vector3(5,1,3), AudioBuses.SFX, 1.335 ± 0.001)` ; `bus_arg != COMBAT_KILL && bus_arg != SWING_ACTIVE` ; `duck_bus` PAS appelé ; `_kill_count_this_swing == 0` (inchangé) ; `play_3d_at` PAS appelé avec `stream == blood_stream`

**AC-AUD-18 (g) Tier indifférent** :
- Given : même setup, ré-émission `secret_collected.emit(secret_node_mock, 3)` (tier 3)
- When : DEFERRED N+1
- Then : `pitch_scale ≈ 1.335 ± 0.001` (identique tier 1)

**AC-AUD-18 (h) Position invalide fallback** :
- Given : `secret_node_mock.global_position = Vector3(NAN, NAN, NAN)`
- When : `secret_collected.emit(secret_node_mock, 1)` DEFERRED
- Then : `play_2d` appelé (head-locked fallback) avec `(clac_stream, AudioBuses.SFX, 1.335 ± 0.001)` ; `play_3d_at` PAS appelé ; `push_warning` capturé via mock logger ou debug-guarded `_warning_handler`

**AC-AUD-19 (a-c) Pitch invariant slow-mo** :
- Given : `Engine.time_scale = 0.3` actif
- When : `secret_collected.emit(secret_node_mock, 1)` DEFERRED
- Then : `play_3d_at` appelé avec `pitch_scale ≈ 1.335 ± 0.001` (PAS `1.335 × 0.8821 ≈ 1.178`) ; assertion explicite `abs(pitch_scale - 1.335) < 0.005` ET `abs(pitch_scale - 1.178) > 0.05`. Retour `Engine.time_scale = 1.0` → prochain `secret_collected` produit toujours `pitch_scale ≈ 1.335`.

**Defensive queue_free** :
- Given : `secret_node_mock.queue_free()` puis `secret_collected.emit(secret_node_mock, 1)` (handler reçoit DEFERRED N+1, node potentiellement invalide)
- When : DEFERRED frame N+1, `is_instance_valid(secret_node) == false`
- Then : fallback `play_2d` head-locked + `push_warning` capturé

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- `tests/integration/audio/secret_collect_pitch_shift_test.gd` (AC-AUD-18 a-h + AC-AUD-19 a-c — couvre dispatch, bus exclusif, pas chain combat, fallback NaN, defensive queue_free, invariant slow-mo)

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (pool 3D), Story 002 (`play_3d_at` / `play_2d` API)
- Cross-system : Secret System (`secret_collected(secret_node: Node, tier: int)` signal — TBD post-`/design-system secret-system`, Audio peut stub mock Secret en attendant)
- Unlocks: AC-AUD-18/19 BLOCKING — débloque close-out epic Audio Pillar 4 viscéralité MVP minimum

---

## Completion Notes

**Completed**: 2026-05-04 — 15/15 tests PASS (1.15 s overall audio suite 154/154 zéro régression)

1. **`SECRET_PITCH_SCALE` precomputed const** : `2.0 ** (5/12) ≈ 1.3348398541700344` stocké en const float (pas formula run-time → zero recompute hot path). Formula 7 absolu, jamais composite avec Formula 5 slow-mo.

2. **`play_2d(stream, bus, pitch_scale: float = 1.0)` extension** : 3e arg optionnel ajouté pour secret head-locked fallback (NaN/inf). Default 1.0 préserve l'historique callers (dash, walljump, death, swoosh, fallback play_3d_at standard sans pitch). Aucune régression sur 5 callers existants (dash/walljump/death/swoosh/play_3d_at fallback) car ils passent toujours 2 args.

3. **Tracker `_slot_fixed_pitch: Dictionary[int, float]`** : key=slot_idx → value=pitch_scale demandé. Permet à `_tick_slow_mo_pitch_shift` de protéger les slots avec pitch fixé caller (secret SFX), même hors `PITCH_ALLOWLIST`. Sans ce tracker, le tick reseterait SFX à 1.0 → casse invariant AC-AUD-19.

4. **Check tracker AVANT check allowlist** dans `_tick_slow_mo_pitch_shift` : `if _slot_fixed_pitch.has(i): continue` placé en premier dans la boucle 3D, avant `PITCH_ALLOWLIST.get`. Critique : sinon SFX (allowlist=false) reseté à 1.0 immédiatement.

5. **Cleanup parallèle aux 2 chemins recycle/force-stop** : `_cleanup_fixed_pitch_slot(slot_idx)` appelé dans `play_3d_at` (round-robin recycle) et `_round_robin_3d_stop_if_saturated` (force-stop saturation). Idempotent via `dict.has()` guard. Pattern symétrique au `_cleanup_clac_slot_tracker` story-007.

6. **Bus SFX exclusif** : choix `&"SFX"` (pas `&"combat_kill"`) garantit sidechain `MUSIC ← COMBAT_KILL` n'arme PAS sur secret collect → Couche 3 musicale continue + Couche 1 silence rythmique combat préservé invariant. Conforme NB-CRD-6 Option A creative-director adjudication 2026-04-28.

7. **Pas de duck_bus, pas d'incrément `_kill_count_this_swing`, pas de blood ambiance** : R-AUD-17 Rule 17 — secret ≠ kill. Tests vérifient explicitement (snapshot bus volume swing_active avant/après, snapshot _kill_count_this_swing, snapshot _blood_pending_count).

8. **Position 3D capturée au tick reception** (R-AUD-7) : `pos = secret_node.global_position` capturé dans handler (pas une ref live au node). Defense queue_free post-emit. Phase D.1 `is_finite()` precheck via `pos.is_finite()` Vector3 method (Godot 4.x natif).

9. **AC-AUD-18 (h) defensive queue_free non-testable en isolation** : GDScript typed strict (`secret_node: Node`) reject les freed nodes AVANT l'entrée de la fonction → impossible de tester `is_instance_valid` precheck via call synchrone. En runtime, Godot auto-disconnect signals vers freed senders (DEFERRED reçu sur freed sender quasi-impossible). La garde `is_instance_valid` reste défensive (cost = 1 if-check) mais ne peut pas être testée isolément sans relâcher le typing handler. Documenté inline dans test file. NaN/inf fallback (8a/8b) testé proprement.

10. **`connect_secret_signals(secret_system: Node)` public** : pattern symétrique à `connect_movement_signals` / `connect_combat_signals` / `connect_level_signals`. No-op gracieux si `null` OU signal `secret_collected` absent — permet boot ordering Secret System pas encore prêt + tests sans dépendance autoload runtime.

**Test file**: `tests/integration/audio/secret_collect_pitch_shift_test.gd` (15 tests : dispatch correct + bus exclusif + pas ducking + counter intact + position capturée + pas blood + tier indifférent + NaN fallback + inf fallback + slow-mo invariant + tracker registered + time_scale restore + cleanup recycle + cleanup force-stop + connect null/missing-signal guards).

**Patterns réutilisables nouveaux** :
- `Dictionary[int, float]` typed tracker key=slot_idx → value=fixed_user_value : pattern réutilisable pour autres préservations per-slot (e.g. fixed volume, fixed reverb send) sous transformations globales (slow-mo, dynamics)
- Cleanup parallèle aux 2 chemins de fin-de-vie slot (recycle round-robin + force-stop saturation) : pattern obligatoire pour tout tracker per-slot afin d'éviter orphans Phase D.3 r2.3
- `default arg = 1.0` extension API rétro-compatible : permet d'ajouter pitch_scale à un verbe play_* sans casser callers existants

**Sprint Audio progression** : **8/12 Complete** (Foundation + API + Combat + Movement + Level + GSM Pause + Slow-mo + Secret). 4/12 stories restantes (009 lint anti-patterns / 010 AudioListener3D / 011 perf budget / 012 sidechain peak meter).
