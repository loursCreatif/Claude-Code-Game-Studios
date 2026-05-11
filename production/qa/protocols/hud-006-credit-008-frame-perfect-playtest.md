# Protocole Playtest — HUD Frame-Perfect + Différenciation Source (AC-HUD-23 / AC-HUD-30 / AC-CRD-46)

> **Stories** : hud-system/story-006 + credit-economy-system/story-008 (convergence)
> **Type** : Visual/Feel ADVISORY — gate ADVISORY (non-bloquant merge CI)
> **Owner** : qa-lead → sign-off creative-director ou game-designer
> **Préalable** : HUD stories 001-005 Complete + build MVP Sprint Multi-Epic playable

## Objectif

Valider **perceptuellement** que le compteur HUD monte dans le même frame que le kill/secret
(Pillar 1 FLOW frame-perfect) et que les deux sources KILL vs SECRET sont **visuellement
distinguables** sans tutoriel (Pillar 2 LA PROGRESSION SE VOIT).

Evidence requise pour fermer AC-HUD-23 / AC-HUD-30 / AC-CRD-46 et clore credit-008
par **subsume** (Option A) ou **shared evidence** (Option B).

## Setup

| Élément | Valeur |
|---------|--------|
| Build | Release MVP Godot 4.6 (pas debug, pas console overlay) |
| Hardware | Laptop entry-level 60 fps vsync locked |
| Input | Clavier + souris |
| Scène | Étage 1 — ≥ 1 grunt + ≥ 1 secret tier-1 accessible |
| Capture | OBS 60 fps **OU** Godot `MovieWriter --fixed-fps 60` **OU** QuickTime macOS |
| Testeur | Martin (solo) — sign-off qa-lead + lead-designer |

### Commande capture Godot MovieWriter (optionnelle)

```bash
godot --headless --write-movie production/qa/evidence/hud-frame-perfect-capture.mp4 \
  --fixed-fps 60 res://scenes/levels/etage_01.tscn
```

### Extraction frames (analyse post-capture)

```bash
ffmpeg -i production/qa/evidence/hud-frame-perfect-capture.mp4 \
  -vf "fps=60" -frame_pts true \
  production/qa/evidence/hud-frame-perfect-frames/%04d.png
```

## Protocole — 5 scénarios

> **Ordre obligatoire.** Capturer A→E en continu si possible.
> Marquer le timecode de départ de chaque scénario dans les notes.

### Scénario A — KILL single (AC-CRD-46 + AC-HUD-23)

1. Lancer capture 60 fps.
2. Tuer 1 grunt avec katana (single swing sans mouvement).
3. Stopper capture après ~2 secondes.
4. Identifier en post : F0 = frame mort grunt visible (corps/ennemi disparu), F1 = frame où le
   chiffre HUD passe N → N+1.
5. **Pass** : `F1 - F0 ∈ [0, 1]`. **Fail** : `F1 - F0 > 1`.

### Scénario B — SECRET collect (AC-CRD-46 + AC-HUD-23)

1. Capturer la collecte d'un secret tier-1 (delta = +5 crédits).
2. F0 = frame icône secret consumed visible, F1 = frame HUD passe N → N+5.
3. **Pass** : `F1 - F0 ∈ [0, 1]`.

### Scénario C — Multi-kill 3 ennemis même swing (AC-HUD-23)

1. Capturer un swing touchant 3 grunts simultanément.
2. F0 = frame impact swing, F1 = frame HUD après dernier incrément.
3. **Pass** : tous incréments dans F0 ou F0+1 (label saute N → N+3 sans frames intermédiaires visibles).

### Scénario D — KILL puis SECRET 500 ms+ après (AC-HUD-23 — différenciation source)

1. Tuer 1 grunt, noter durée pulse (~6 frames = 100 ms attendu).
2. Collecter 1 secret 500 ms après, noter durée pulse (~9 frames = 150 ms attendu).
3. **Pass** : observateur humain distingue les deux pulses comme "différents" (durée visible).
   Différence ≥ 3 frames à l'œil sur la vidéo.

### Scénario E — Resize toggle (AC-HUD-30)

1. Pendant gameplay actif (HUD visible), appuyer sur F11 (plein écran → fenêtré).
2. Revenir en plein écran. Répéter 2-3 fois.
3. **Pass** : counter reste anchored top-right, in-bounds, lisible sans dérive visible.

## Questions structurées (debrief solo)

Répondre par écrit dans l'evidence file après analyse vidéo :

1. [BINAIRE] Scénario A : delta frame = `___`. Pass / Fail ?
2. [BINAIRE] Scénario B : delta frame = `___`. Pass / Fail ?
3. [BINAIRE] Scénario C : label saute N → N+3 en ≤ 1 frame ? Oui / Non ?
4. [1-5] Scénario D : la différence de durée pulse KILL vs SECRET est perceptible sans
   freeze-frame ? 1 = invisible, 5 = clairement distincte.
5. [BINAIRE] Scénario E : counter stable après resize ? Oui / Non ?

## Critères Pass / Fail

| AC | Seuil | Source |
|----|-------|--------|
| AC-CRD-46 / AC-HUD-23 frame-perfect | `delta ∈ [0, 1]` frame sur scénarios A + B + C | hud-006 §AC + credit-008 §AC |
| AC-HUD-23 différenciation source | Q4 ≥ 3/5 (perceptible) | hud-006 §AC |
| AC-HUD-30 resize stable | Scénario E pass binaire | hud-006 §AC |

**Fail** sur A OU B OU C (`delta > 1`) → vérifier chaîne SYNC `enemy_killed → credits_changed
→ _on_credits_changed` ; chercher `CONNECT_DEFERRED` parasite dans la chaîne.

## Evidence à produire

Fichier : `production/qa/evidence/hud-frame-perfect-evidence-[YYYY-MM-DD].md`

Template :

```markdown
# Evidence — HUD frame-perfect (AC-HUD-23 + AC-HUD-30 + AC-CRD-46)
**Date** : YYYY-MM-DD | **Build** : <git sha> | **Capture** : <path>.mp4

## Résultats scénarios
| Scénario | F0 | F1 | Delta | Verdict |
|----------|----|----|-------|---------|
| A KILL | | | | |
| B SECRET | | | | |
| C Multi-kill | | | | |
| D Différenciation (Q4 score) | — | — | score /5 | |
| E Resize toggle | — | — | — | |

## Verdict global : PASS / FAIL

## Sign-off
- qa-lead : ___ — YYYY-MM-DD
- lead-designer : ___ — YYYY-MM-DD

## Convergence credit-008
- Option A (subsume) : credit-008 fermée par cette evidence. OU
- Option B (shared) : credit-008 référence ce fichier + close indépendamment.
```

## Mots-clés observés (think-aloud optionnel)

**Positifs** : "instantané", "direct", "immédiat", "net", "frame-perfect"

**Négatifs** (red flags) : "lag", "décalé", "lent", "retard", "j'attends", "delay"

## Source

- `production/epics/hud-system/story-006-visual-feel-frame-perfect-playtest.md` §AC-HUD-23/30 + §AC-CRD-46
- `production/epics/credit-economy-system/story-008-visual-feel-hud-frame-perfect.md` §AC-CRD-46
- Template : `production/qa/protocols/combat-feel-interview.md`
