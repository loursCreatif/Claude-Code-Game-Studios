# Story 011: SaveLoad Failure Buffer Retry (EC-SHP-9 Option C)

> **Epic**: Shop System
> **Status**: Deprecated — Tier 2+ revisit
> **Layer**: Feature
> **Type**: Logic
> **Manifest Version**: 2026-04-23

> ⚠️ **DEPRECATED 2026-04-28** : design contradiction avec ADR-0010 promu Accepted (D-2 `save_string_array(...) -> void` + D-5 outbound-zero) — caller ne peut pas détecter l'échec sans amendement r2 cascadant sur tout l'epic save_load. Risque résiduel ~0.5% (force-quit + disk full simultanés) accepté MVP via EC-SHP-24. Re-évaluer Tier 2+ si telemetry montre fréquence > 0.5%. Voir Completion Notes.

> ✅ **ADR-0010 Accepted** (promu 2026-04-27) : pattern Option C consomme `save_string_array` SYNC void-return + `push_error` côté SaveLoad (ADR-0010 D-2 + D-5).

## Context

**GDD**: `design/gdd/shop-system.md`
**Requirement**: `EC-SHP-9` (Option C buffer retry non-bloquant), `EC-SHP-24` (force-quit risque résiduel admis)
*Quand `save_string_array` échoue post-débit (disque plein, permissions, file lock), Shop applique le pattern Option C : push_error log + queue interne `_pending_save_retries: Array[Array[StringName]]` + retry max 3 tentatives sur 5 s wall-clock (intervalle exponentiel 0.5s, 1.5s, 3s) dans `_process` idle frame. Si 3 échecs → fallback save quit-to-menu via hook `_on_pre_quit` connecté à GSM `state_changed(MENU)`. Risque résiduel ~0.5% (force-quit + retry exhausted) admis EC-SHP-24.*

**ADR Governing Implementation**: ADR-0010 D-2 (save_* return void, push_error on failure).
**ADR Decision Summary**: SaveLoad ne retourne pas de bool ; le caller doit assumer write-through SYNC (push_error log = signal de failure). Retry pattern owned par caller (Shop) — cohérent ADR-0010 D-5 outbound-zero (Save/Load ne pilote pas de retry).

**Engine**: Godot 4.6 | **Risk**: MEDIUM (retry pattern non standard — ADR-0010 promu Accepted 2026-04-27).
**Engine Notes**: `_process(delta)` standard Godot lifecycle. `Time.get_ticks_msec()` pour intervalles wall-clock.

**Control Manifest Rules**:
- Required: retry sur idle frame `_process` (pas `_physics_process` — Shop est UI, pas gameplay)
- Forbidden: blocking retry loop dans `_on_buy_pressed` (cycle reste atomique synchrone EC-SHP-23)

---

## Acceptance Criteria

- [ ] **EC-SHP-9** : `save_string_array` échoue post-débit → `push_error` log + `_pending_save_retries.append(_owned_upgrades.duplicate())` + cycle continue (apply_upgrade appelé).
- [ ] Retry intervalles : 0.5s, 1.5s, 3s wall-clock (exponentiel) max 3 tentatives.
- [ ] Retry succès → `_pending_save_retries.clear()` + `push_warning("save retry succeeded after N attempts")`.
- [ ] Retry exhausted → `push_error("save retry exhausted — owned_upgrades will be re-attempted at quit-to-menu")` ; upgrade reste active RAM.
- [ ] Hook `_on_pre_quit` connecté à `GameStateManager.state_changed(MENU)` → re-tente save_string_array.
- [ ] Aucune notification UX joueur MVP (silence cohérent Pillar 1).
- [ ] **EC-SHP-24** : force-quit avant écriture quit-to-menu → upgrade perdue, débit crédit persisté indépendamment (Credit R-CRD-12 idempotent) — risque résiduel admis.

---

## Implementation Notes

```gdscript
var _pending_save_retries: Array[Array] = []  # FIFO queue d'arrays owned_upgrades à re-tenter
var _retry_attempts: int = 0
var _next_retry_at_ms: int = 0
const _RETRY_DELAYS_MS: Array[int] = [500, 1500, 3000]
const _MAX_RETRIES: int = 3

func _ready() -> void:
    # ... (story-002 à 010) ...
    # Hook fallback save quit-to-menu
    GameStateManager.state_changed.connect(_on_state_changed, CONNECT_DEFERRED)

func _safe_save_owned_upgrades() -> void:
    # Wrapper appelé depuis cycle (story-005 étape 5b), remplace appel direct
    SaveLoad.save_string_array(&"owned_upgrades", _owned_upgrades)
    # SaveLoad émet push_error interne si fail. Pour détecter ici, alternative :
    # interroger un getter SaveLoad.get_last_error() (à confirmer ADR-0010 D-2).
    # Si pas dispo → fallback : capturer push_error via _push_error_handler en debug.

func _process(_delta: float) -> void:
    if _pending_save_retries.is_empty():
        return
    var now_ms: int = Time.get_ticks_msec()
    if now_ms < _next_retry_at_ms:
        return
    _retry_attempts += 1
    if _retry_attempts > _MAX_RETRIES:
        push_error("ShopSystem: save retry exhausted — owned_upgrades will be re-attempted at quit-to-menu")
        _pending_save_retries.clear()
        _retry_attempts = 0
        return
    var snapshot: Array = _pending_save_retries[0]
    SaveLoad.save_string_array(&"owned_upgrades", snapshot)
    # Si succès (no push_error ce frame) : clear retry queue
    # Mécanisme exact de détection success/fail à confirmer Sprint 1 (interroger SaveLoad)
    _next_retry_at_ms = now_ms + _RETRY_DELAYS_MS[_retry_attempts - 1]

func _on_state_changed(new_state: int) -> void:
    if new_state == GameStateManager.State.MENU and not _pending_save_retries.is_empty():
        # Fallback ultime : re-tente save avant que scène shop ne soit déchargée
        SaveLoad.save_string_array(&"owned_upgrades", _owned_upgrades)
        _pending_save_retries.clear()
```

**Note d'implémentation pragmatique** : le mécanisme de détection succès/échec dépend de l'API exacte de SaveLoad Sprint 1. Trois options à choisir lors de `/dev-story` :
1. SaveLoad expose `get_last_save_error() -> int` (à demander en amendement ADR-0010).
2. Shop hook un global `push_error` capture en debug (fragile).
3. SaveLoad expose un signal `save_failed(key: String, err: int)` (rompt outbound-zero R-SAV-10 — déconseillé).

Recommandation : option 1 si scope amendement minimal. Sinon option 2 + warning Sprint 2 cleanup.

**Snapshot via `duplicate()`** : `_owned_upgrades.duplicate()` pour éviter mutation pendant retry.

---

## Out of Scope

- Story 010 : write SYNC nominal + corruption load.
- Story 015 : test bidirectional avec SaveLoad réel (cas nominal).
- Sprint 2+ : alerte UX discrète si retry exhausted (Tier 2+, hors MVP).

---

## QA Test Cases

- **EC-SHP-9 buffer retry** : Logic
  - Given: mock SaveLoad.save_string_array émet push_error premier appel + succès au 3e
  - When: cycle achat exécuté + 2× `_process` ticks avec wall-clock avancé
  - Then: 3 appels save total (1 initial + 2 retry), push_warning "succeeded after 2 attempts"
- **Retry exhausted** : Logic
  - Given: mock SaveLoad émet push_error sur 4 appels consécutifs
  - When: cycle + ticks avancés couvrant 5s
  - Then: 4 appels (1 + 3 retry), push_error "exhausted", `_pending_save_retries.is_empty()`
- **Hook quit-to-menu fallback** : Integration
  - Given: retry exhausted, GSM state == PLAYING
  - When: emit `state_changed(MENU)`
  - Then: 1 appel `save_string_array` supplémentaire (re-tente avec snapshot RAM courant)
- **Idle process retry timing** : Logic
  - Given: 1 entry dans `_pending_save_retries`
  - When: `_process` invoqué avec `Time.get_ticks_msec` < `_next_retry_at_ms`
  - Then: aucun appel save (early return delay non écoulé)
- **EC-SHP-24 force-quit** : Manual + Doc
  - Given: retry exhausted + before quit-to-menu
  - When: force-quit (kill -9 simulé)
  - Then: upgrade perdue au reboot, débit crédit persisté (Credit indépendant)
  - Pass: documenter dans `production/qa/evidence/shop/story-011-force-quit-edge.md` comme risque assumé

---

## Test Evidence

**Story Type**: Logic
**Required evidence**: `tests/unit/shop/saveload_buffer_retry_test.gd` — must exist and pass
**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Story 010 (write SYNC nominal), Story 008 (GSM connection établie)
- Unlocks: Story 015 (bidirectional avec failure scenarios) — close partial avec marker `[PROVISIONAL — no buffer retry coverage]`

---

## Completion Notes
**Status**: Deprecated — Tier 2+ revisit
**Decision Date**: 2026-04-28
**Rationale** :
- **Blocker design** : pattern Option C exige détecter l'échec côté Shop pour enqueue `_pending_save_retries`, mais `SaveLoadSystem.save_string_array(key, value) -> void` (ADR-0010 D-2 lock-in) expose seulement `push_error` log côté SaveLoad sans canal observable côté caller. ADR-0010 D-5 outbound-zero interdit hooks internes SaveLoad.
- **Options évaluées** :
  1. Amender ADR-0010 → ajouter `signal save_failed(key, err_code)` (rompt outbound-zero, r2 review obligatoire, cascade save_load epic)
  2. Changer signature `-> int` retournant `Error` (rompt D-2 API lock-in, refactor toute la chaîne save_load)
  3. **Retenue** : Déprécier story-011 et accepter risque résiduel EC-SHP-24
- **Coût/bénéfice MVP** : ~80 lignes code (`_process` timer + GSM hook + quit-to-menu fallback) pour scénario combiné force-quit + disk full simultanés (~0.5%). ROI faible MVP.
- **Pillar 1 cohérence** : silence cohérent anti-friction (pas de notification UX joueur prévue de toute façon — EC-SHP-9 ligne 36).
- **Réversibilité** : si telemetry Tier 2+ montre fréquence > 0.5% ou plaintes joueurs, ré-ouvrir avec budget ADR amendment.
- **Impact downstream** : story-015 (bidirectional integration) ferme partial avec marker `[PROVISIONAL — no buffer retry coverage]` ; pas de blocker autres stories (012-014, 016 indépendantes).

**Code Review** : N/A (Deprecated avant impl).
**Test Evidence** : N/A (Deprecated — risque accepté EC-SHP-24).
