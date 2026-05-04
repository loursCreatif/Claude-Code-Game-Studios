# Story 006: GSM Pause/Resume — Master Bus Mute/Unmute + State Preservation `_fade_pause_msec` Offset Wall-Clock

> **Epic**: Audio System
> **Status**: Complete 2026-05-04 (19/19 tests PASS — 7/7 ACs COVERED + lint forbidden mutation + DEFERRED idempotent)
> **Layer**: Core
> **Type**: Logic
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/audio-system.md` (r2.3 §Rule 10 + §Edge Cases pause/resume + §AC-AUD-08/09)
**Requirements** (R-AUD stable IDs jusqu'à `/architecture-review` post-Sprint 1) :
- R-AUD-10 : Pause/resume — silence total via `MASTER` bus mute (`AudioServer.set_bus_mute(0, true/false)`), aucun `stream_paused` individuel
- R-AUD-5 : `CONNECT_DEFERRED` par défaut sur tous les signals consumer

**ADR Governing**: ADR-0009 D-1 (bus hierarchy) + ADR-0007 D-4 (GSM `process_mode = ALWAYS = 3` Godot 4.6 erratum — handlers actifs même pendant pause) + ADR-0007 D-10 (state_changed contract)
**Decision Summary**: Audio handler `_on_state_changed(new_state)` connecté DEFERRED depuis GSM, sur `PAUSED` mute Master bus + marque chaque fade actif (`_swoosh_fade_active` / `_ducking_release_active` / `_crossfade_active`) avec `_fade_pause_msec = _get_time_msec()` snapshot wall-clock. Sur `PLAYING` (resume) unmute Master + applique offset `_get_time_msec() - _fade_pause_msec` aux timestamps de départ pour reprendre les fades exactement où ils étaient pré-pause. Queue audio Godot préservée (musique reste `playing == true`, pas de `stream_paused` individuel).

**Engine**: Godot 4.6 | **Risk**: LOW
**Engine Notes**: `AudioServer.set_bus_mute(0, true)` mute le Master bus instantanément (1 frame) — pas de fade naturel. Queue audio Godot survit au mute (le sample continue d'avancer en interne, simplement non audible). Sur unmute, l'audio reprend là où il était. ADR-0007 D-4 critical : Audio handler doit avoir `process_mode = ALWAYS = 3` (Godot 4.6 erratum, valeur 3 — pas 2 comme en 4.3) pour recevoir le signal `state_changed(PLAYING)` même si SceneTree est paused. Cf. mémoire `feedback_godot_4_6_physics_interpolation_enum.md` pattern enum renumérotation.

**Control Manifest Rules (Core layer)**:
- Required: connect GSM signal `state_changed` avec `CONNECT_DEFERRED`
- Required: `process_mode = ALWAYS` sur AudioSystem autoload
- Forbidden: `Engine.time_scale` ou `get_tree().paused` mutation côté Audio (autorité GSM seul, ADR-0007 D-4)
- Forbidden: `stream_paused` individuel par player (R-AUD-10 — Master mute uniquement)

---

## Acceptance Criteria

*From GDD AC-AUD-08/09:*

- [ ] **AC-AUD-08 (a) Mute DEFERRED frame N+1** : musique + 3 SFX en cours, GSM `state_changed(PAUSED)` émis → `AudioServer.is_bus_mute(0) == true` à la frame suivante (DEFERRED N+1).
- [ ] **AC-AUD-08 (b) Queue audio préservée** : `AudioStreamPlayer.playing` reste `true` pour music pendant pause (pas de `stop()` ni `stream_paused` individuel).
- [ ] **AC-AUD-08 (c) State snapshot fade actif** : si `_swoosh_fade_active == true` au moment de la pause, `_fade_pause_msec` enregistré `== _get_time_msec()` au tick reception. Idem `_ducking_release_active`, `_crossfade_active` (si présent story 005).
- [ ] **AC-AUD-09 (a) Unmute DEFERRED** : GSM `state_changed(PLAYING)` (resume) → `AudioServer.is_bus_mute(0) == false` à la frame N+1.
- [ ] **AC-AUD-09 (b) Fade offset wall-clock appliqué** : si fade pré-pause à `t=15ms` sur 30ms total, après pause de 5s wall-clock le fade reprend à `t=15ms` (PAS à `t=5015ms`). Implémentation : décaler `_fade_start_msec += (resume_msec - _fade_pause_msec)`.
- [ ] **AC-AUD-09 (c) Music audible immédiatement** : `music_player.playing == true` confirmé pré-pause + post-resume, pas de gap audible.
- [ ] **Forbidden mutation autorité GSM** : test grep `src/core/audio_system.gd` ne contient PAS `Engine.time_scale` ni `get_tree().paused` (autorité unique GSM ADR-0007 D-4). FAIL avec message si match.
- [ ] **process_mode = ALWAYS** : assertion `AudioSystem.process_mode == Node.PROCESS_MODE_ALWAYS` (valeur 3 Godot 4.6) pour recevoir signaux pendant SceneTree paused.

---

## Implementation Notes

*Derived from ADR-0009 + ADR-0007 D-4 + GDD §Edge Cases pause/resume:*

```gdscript
# AudioSystem (autoload) — pause/resume handler
var _fade_pause_msec: int = 0
var _is_paused: bool = false

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS  # Godot 4.6 erratum — handlers actifs pendant pause
    # ... pool boot story-001 ...
    _connect_gsm_signals()

func _connect_gsm_signals() -> void:
    if not GameStateManager.state_changed.is_connected(_on_state_changed):
        GameStateManager.state_changed.connect(_on_state_changed, CONNECT_DEFERRED)

func _on_state_changed(new_state: int) -> void:
    match new_state:
        GameStateManager.State.PAUSED:
            _enter_pause()
        GameStateManager.State.PLAYING:
            _exit_pause()
        # autres états (SCENE_TRANSITION, MENU) — TBD post-`/design-system game-state-manager`

func _enter_pause() -> void:
    if _is_paused:
        return  # idempotent
    _is_paused = true
    _fade_pause_msec = _get_time_msec.call()
    AudioServer.set_bus_mute(0, true)  # MASTER = bus 0

func _exit_pause() -> void:
    if not _is_paused:
        return
    _is_paused = false
    var resume_msec: int = _get_time_msec.call()
    var pause_duration_msec: int = resume_msec - _fade_pause_msec
    # Décaler timestamps de départ pour reprendre exactement où le fade était
    if _swoosh_fade_active:
        _swoosh_fade_start_msec += pause_duration_msec
    if _ducking_release_active:
        _ducking_release_start_msec += pause_duration_msec
    if _crossfade_active:  # story 005 hook si présent
        _crossfade_start_msec += pause_duration_msec
    AudioServer.set_bus_mute(0, false)
```

**Note autorité GSM** : Audio System ne mute jamais `Engine.time_scale` ni `get_tree().paused` directement. Seul GSM a cette autorité (ADR-0007 D-4). Audio est outbound-only consumer du signal `state_changed`.

**Note process_mode** : `Node.PROCESS_MODE_ALWAYS = 3` en Godot 4.6 — sans cette valeur, AudioSystem ne reçoit pas le signal `state_changed(PLAYING)` car SceneTree est paused (cf. mémoire pattern enum renumérotation Godot 4.6 vs 4.3).

---

## Out of Scope

*Handled by neighbouring stories — do not implement here:*

- Story 001 : pool boot + bus layout + sidechain compressor
- Story 003-005 : handlers Combat/Movement/Level qui produisent les fades (`_swoosh_fade_active`, `_ducking_release_active`, `_crossfade_active`)
- Story 009 : 3 lints CI (`lint-audio-pool` / `lint-audio-tween` / `lint-audio-deferred`) — vérifient également `connect()` GSM avec flag DEFERRED
- Story 011 : performance budget pause/resume (non couverte AC-AUD-13 directement, mais handler trivial)

---

## QA Test Cases

**AC-AUD-08 (a/b) Mute Master DEFERRED + queue préservée** :
- Given : AudioSystem prêt, music en cours `play_music(stream)` `playing == true`, 3 SFX joués via `play_2d`, mock GSM avec signal `state_changed`
- When : `GameStateManager.state_changed.emit(GameStateManager.State.PAUSED)` puis `await get_tree().physics_frame` (DEFERRED N+1)
- Then : `AudioServer.is_bus_mute(0) == true` ; `music_player.playing == true` (queue préservée) ; `_2d_pool[i].playing` inchangé pour SFX en cours

**AC-AUD-08 (c) State snapshot** :
- Given : `_swoosh_fade_active = true`, `_swoosh_fade_start_msec = 1000`, `_get_time_msec` mocké retourne `1015` au moment de la pause
- When : `state_changed(PAUSED)` reçu DEFERRED
- Then : `_fade_pause_msec == 1015` ; `_swoosh_fade_start_msec` inchangé pour le moment (1000 — l'offset est appliqué au resume)

**AC-AUD-09 (a/b) Unmute + offset wall-clock** :
- Given : pause active depuis `_fade_pause_msec = 1015`, `_swoosh_fade_active = true`, `_swoosh_fade_start_msec = 1000`, `_get_time_msec` mocké retourne `6015` au resume (5 s pause)
- When : `state_changed(PLAYING)` reçu DEFERRED
- Then : `AudioServer.is_bus_mute(0) == false` ; `_swoosh_fade_start_msec == 6000` (1000 + 5000 offset) ; le fade calcule `elapsed = 6015 - 6000 = 15ms` (reprend exactement à mi-fade, pas à 5015ms qui aurait fini depuis longtemps)
- Edge cases : si offset non appliqué → `elapsed = 6015 - 1000 = 5015ms` → fade considéré terminé instantanément → swoosh disparaît au resume = FAIL avec message "AC-AUD-09 (b) offset wall-clock non appliqué — fade pré-pause perdu"

**AC-AUD-09 (c) Music audible immédiatement** :
- Given : pré-pause `music_player.playing == true`, post-pause `music_player.playing == true`
- When : resume DEFERRED frame N+1
- Then : aucun appel à `music_player.play()` (pas de re-trigger, queue préservée)

**Forbidden mutation autorité GSM** :
- Given : code source `src/core/audio_system.gd`
- When : grep `Engine.time_scale|get_tree().paused`
- Then : zéro match (hors commentaires explicatifs `# autorité GSM, pas Audio`)

**process_mode ALWAYS** :
- Given : AudioSystem instancié
- When : assertion `AudioSystem.process_mode`
- Then : `== Node.PROCESS_MODE_ALWAYS` (valeur 3 Godot 4.6 — pas 2 comme en 4.3)

---

## Test Evidence

**Story Type**: Logic
**Required evidence**:
- `tests/unit/audio/pause_resume_master_mute_test.gd` (AC-AUD-08 a/b/c + AC-AUD-09 a/b/c — mock GSM `state_changed` + `_get_time_msec` mocké séquence pause-resume)
- `tests/static/audio_no_gsm_authority_lint_test.gd` (forbidden grep `Engine.time_scale|get_tree().paused` dans `src/core/audio_system.gd`) — peut être agrégé dans story 009 lint suite
- Assertion `process_mode == ALWAYS` incluse dans test pause_resume

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 001 (autoload skeleton + `_get_time_msec` Callable injection), Story 002 (API `play_music` pour test fixtures)
- Cross-system : GameStateManager (`state_changed` signal — TBD post-`/design-system game-state-manager`, Audio peut stub mock GSM en attendant)
- Unlocks: AC-AUD-08/09 BLOCKING — debloque close-out epic Audio (Definition of Done item Pause/resume verifié)

---

## Completion Notes

**Completed**: 2026-05-04
**Criteria**: 7/7 ACs COVERED (AC-AUD-08 a/b/c + AC-AUD-09 a/b/c + forbidden mutation autorité GSM + process_mode ALWAYS)
**Tests**: 19/19 PASS — `tests/unit/audio/pause_resume_master_mute_test.gd` (process_mode + mute master + queue préservée + snapshot fade-pause-msec + idempotent double pause + unmute + offset 5 fades actifs : swoosh / ducking / wallrun / crossfade / music_fade_out + no offset si fades inactifs + music pas re-trigger + idempotent guard exit sans pause + states MENU/RESPAWNING no-op + 2 lints forbidden Engine.time_scale + get_tree().paused mutation + connect DEFERRED idempotent guard)
**Code Review**: Pending (Solo mode skipped LP-CODE-REVIEW)

### Implementation Notes

1. **process_mode = ALWAYS dans `_ready()`** : Godot 4.6 enum `Node.PROCESS_MODE_ALWAYS = 3` (cf. memory feedback_godot_4_6_physics_interpolation_enum.md — toujours utiliser symbolique). Sans ce flag, AudioSystem ne reçoit pas `state_changed(PLAYING)` car SceneTree paused (ADR-0007 D-4).
2. **`_connect_gsm_signals()` no-op gracieux si GSM absent** : `get_node_or_null("/root/GameStateManager")` + `has_signal("state_changed")` guard — permet `_on_state_changed(state_int)` invoqué directement par tests sans dépendre de GSM autoload présent. Test idempotent verifie 1 seule connexion sur re-call.
3. **Autorité GSM pure** : aucune mutation `Engine.time_scale` ni `get_tree().paused` côté Audio (ADR-0007 D-4). 2 tests lint statiques regex grep sur `src/core/audio_system.gd` garantissent zéro assignation. Lecture autorisée (lookup `get_node`).
4. **Master bus mute préserve queue** : `AudioServer.set_bus_mute(0, true)` mute instantanément ; `_music_player.playing` reste true (R-AUD-10 — pas de `stream_paused` individuel). Queue Godot survit, sample continue d'avancer en interne, reprend sur unmute.
5. **State preservation 5 fades actifs** : `_swoosh_fade_active` / `_ducking_release_active` / `_wallrun_fade_active` / `_crossfade_active` / `_music_fade_out_active` — chacun a son `*_start_msec` offset par `pause_duration_msec = resume_msec - _fade_pause_msec` au resume. Math : `elapsed_post_resume = resume_now - (start + pause_dur) = elapsed_pre_pause + dt` → fade reprend exactement où il était.
6. **Idempotence pause/resume** : `_enter_pause` no-op si `_is_paused == true` (snapshot conservé, pas écrasé). `_exit_pause` no-op si `_is_paused == false` (offset jamais appliqué sans pause préalable). Test `test_state_paused_idempotent_double_pause_no_op` + `test_state_playing_without_prior_pause_no_op`.
7. **Map state → enum int hardcoded** : valeurs canoniques GSM (`MENU=0, PLAYING=1, PAUSED=2, RESPAWNING=3, BOSS_DEFEATED=4`) hardcodées dans `_on_state_changed` pour éviter dépendance compile-time `class_name GameStateManagerScript`. Cf. memory `feedback_godot_class_name_autoload_collision`. États autres que PAUSED/PLAYING : no-op (Audio outbound-only consumer).
8. **`_on_state_changed` invoqué directement par tests** : pattern hérité story-005 (Callable injection + state vars accessibles). Permet test exhaustif sans mock GSM autoload runtime.
9. **`set_paused(paused)` story-002 stub conservé** : direct mute Master sans state preservation — utilité tests/manual override hors GSM. Le path canonique GSM est `_on_state_changed(PAUSED)` qui appelle `_enter_pause` (mute + snapshot).
10. **Pattern `_get_time_msec` Callable** réutilisé (ADR-0006 D-5) : tests mockent séquence `[pause_msec, resume_msec]` via lambda Array wrapper `[idx]` (gotcha capture-by-value) pour vérifier offset exact.
