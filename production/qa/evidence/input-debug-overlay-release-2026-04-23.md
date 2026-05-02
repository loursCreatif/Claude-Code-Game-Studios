# QA Evidence — Input Debug Overlay (Release Build Smoke)

**Story**: story-009 — Debug overlay F3 (latency, action, mouse mode)
**AC**: AC-DBG-2
**Date**: 2026-04-23
**Tester**:

## Environnement

| Champ | Valeur |
|---|---|
| OS | <!-- ex. Windows 11 22H2 / macOS 15.4 / Ubuntu 24.04 --> |
| GPU + driver | <!-- ex. RTX 3060 driver 537.xx --> |
| Godot version | 4.6.x (stable) |
| Build commit | <!-- git rev-parse --short HEAD --> |
| Build type | Release (exported) |
| Export preset utilisé | <!-- nom du preset dans export_presets.cfg --> |

## Prérequis (known gaps)

- **`export_presets.cfg` absent** à la date de cette story : le preset d'export release doit être configuré dans l'éditeur Godot (`Project → Export → Add...`) AVANT d'exécuter ce test. Follow-up story à créer si pas encore fait.
- **Alternative sans export** : si l'export n'est pas disponible, une validation partielle est possible en :
  1. Ajoutant temporairement `custom_features="non_debug"` dans une config de run Godot
  2. OU en forçant `OS.has_feature("debug") == false` via un override headless test
  Marquer l'evidence comme **PARTIAL** dans ce cas.

---

## Setup

- [ ] Export release produit via l'éditeur Godot (preset Windows/macOS/Linux) OU `godot --export-release "<preset_name>" <output_path>`
- [ ] Exécutable lancé sur machine cible (pas depuis l'éditeur Godot)
- [ ] Scène jouable active dans le build

---

## Steps

### Binary gate release — AC-DBG-2

- [ ] Presser F3 ≥ 10 fois réparties sur ≥ 30 s de gameplay
- [ ] Aucun overlay (aucun CanvasLayer, aucun Label) n'apparaît à aucun moment
- [ ] Aucune pause, freeze ou micro-stutter corrélé aux pressions F3
- [ ] Logs stdout/stderr propres : aucun message d'erreur, aucun warning mentionnant `InputDebugOverlay` ou `debug_toggle`
- [ ] Vérifier dans le binaire : le Label "latency_p99: 0.00 ms" n'est pas rendu à l'écran à aucun moment

### Vérification gate source (complémentaire)

- [ ] `grep "OS.has_feature(\"debug\")" src/core/input_manager.gd` renvoie bien le guard l. 198 ss
- [ ] `grep "queue_free" src/core/input_debug_overlay.gd` renvoie bien le binary gate l. 54-55

---

## Result

<!-- Coller capture vidéo (≥ 30 s) montrant gameplay normal + pressions F3 sans overlay ; logs stdout en texte -->

Video : `<path ou lien>`
Logs release run : `<path>`

---

## Sign-off

| Champ | Valeur |
|---|---|
| Lead sign-off | _______________ |
| Date | _______________ |
| Verdict | [ ] PASS   [ ] PARTIAL (alt path)   [ ] FAIL |
| Notes | <!-- si PARTIAL, décrire l'alternative utilisée --> |
