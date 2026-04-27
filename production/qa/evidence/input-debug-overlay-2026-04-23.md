# QA Evidence — Input Debug Overlay (Debug Build)

**Story**: story-009 — Debug overlay F3 (latency, action, mouse mode)
**AC**: AC-DBG-3
**Date**: 2026-04-23
**Tester**:

## Environnement

| Champ | Valeur |
|---|---|
| OS | <!-- ex. Windows 11 22H2 / macOS 15.4 / Ubuntu 24.04 Wayland --> |
| GPU + driver | <!-- ex. RTX 3060 driver 537.xx / Apple M4 intégré --> |
| Godot version | 4.6.x (stable) |
| Build commit | <!-- git rev-parse --short HEAD --> |
| Build type | Debug (interpreter) |

## Prérequis (known gaps)

- **Scène de run** : `project.godot` n'a pas `config/run/main_scene` configuré ; lancer une scène test jouable (ex. `tests/manual/debug_overlay_scene.tscn` quand elle existera) ou via la scène de gameplay active du sprint. Noter ici la scène utilisée : `_______________`
- **Warmup latency** : `latency_p99` affiche `0.00 ms` pendant ~1 s après l'activation de l'overlay (fenêtre rolling 1 s vide tant que pas assez de samples). **Ce comportement est attendu** — ne pas cocher FAIL avant T+2 s d'overlay visible.
- **mouse_mode CAPTURED** : observable uniquement si une scène avec PlayerController (ou équivalent `Input.set_mouse_mode(MOUSE_MODE_CAPTURED)`) est active. Si scène MVP sans capture, le Label restera `VISIBLE` en permanence — **n'est pas un échec**, la pass condition accepte `CAPTURED | VISIBLE`.

---

## Setup

- [ ] Build debug lancé (`godot --debug` ou depuis l'éditeur)
- [ ] Scène jouable active (cf prérequis)
- [ ] Machine non-alt-tab (focus fenêtre stable pendant le test)

---

## Steps

### Toggle F3 — AC-DBG-3

- [ ] Presser F3 → overlay apparaît avec 3 labels visibles
- [ ] Presser F3 → overlay disparaît
- [ ] Répéter ≥ 3 fois — toggle stable à chaque presse

### Labels dynamiques — AC-DBG-3 bis

**ActionLabel** (4 actions × timer reset binaire 500 ms ±200 ms — mesurable vidéo frame-by-frame) :

- [ ] Presser `jump` → `action: jump` s'affiche dans le frame suivant ; retour à `action: —` entre T+300 ms et T+700 ms
- [ ] Presser `dash` → idem (`action: dash`)
- [ ] Presser `attack` → idem (`action: attack`)
- [ ] Presser `restart` → idem (`action: restart`)

**LatencyLabel** (refresh 1 Hz mesurable par valeur qui change) :

- [ ] Après T+2 s d'overlay visible : LatencyLabel affiche une valeur non-nulle
- [ ] Entre T+2 s et T+5 s : la valeur affichée change au moins 1 fois (1 Hz accumulator)
- [ ] Valeur cohérente : 0 ms < p99 < 50 ms en conditions debug normales

**MouseModeLabel** (valeur courante — scène-dépendant) :

- [ ] Value affichée : `CAPTURED` ou `VISIBLE` (pas de valeur vide ou autre)
- [ ] Si scène avec capture souris : Label affiche `CAPTURED`
- [ ] Si scène sans capture (ex. menu) : Label affiche `VISIBLE`

### Flag rouge latence (anomalie)

- [ ] Condition normale (p99 ≤ 0.5 ms) : LatencyLabel reste blanc
- [ ] Si spike observable (p99 > 0.5 ms) : LatencyLabel passe rouge à la mise à jour suivante

---

## Result

<!-- Coller screenshots (min 1× overlay ON, 1× overlay OFF, 1× ActionLabel pendant timer) + lien vidéo ≥ 10 s montrant les 3 labels dynamiques + au moins 3 toggles F3 -->

Screenshots :
- Overlay ON, 3 labels visibles : `<path>`
- Overlay OFF après toggle : `<path>`
- ActionLabel pendant timer : `<path>`

Video : `<path ou lien>`

---

## Sign-off

| Champ | Valeur |
|---|---|
| Lead sign-off | _______________ |
| Date | _______________ |
| Verdict | [ ] PASS   [ ] FAIL   [ ] PASS WITH NOTES |
| Notes | <!-- anomalies mineures acceptables, ou raison d'échec --> |
