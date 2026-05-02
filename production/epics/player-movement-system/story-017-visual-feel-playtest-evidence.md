# Story 017: Visual/Feel playtest evidence

> **Epic**: player-movement-system
> **Status**: Complete
> **Layer**: Core
> **Type**: Visual/Feel
> **Manifest Version**: 2026-04-23

## Context

**GDD**: `design/gdd/player-movement-system.md`
**Requirements**: `TR-mov-001`, `TR-mov-003`
*(Requirement text lives in `docs/architecture/tr-registry.yaml` — read fresh at review time.)*

**ADR Governing**: ADR-0001 (Pillar 1 FLOW AVANT TOUT — la latence intra-engine atteinte est nécessaire mais pas suffisante ; le feel doit être validé empiriquement)
**Decision Summary**: Validation qualitative playtest (≥ 3 sessions) du feel Ghostrunner-like — prérequis gate Pre-Production → Production. Garde-fou attribution causale 50 ms RESPAWN_DELAY (AC Feel GDD). Captures FOV pulse dash et fade rouge respawn (AC-MV-100/101).

**Engine**: Godot 4.6 | **Risk**: MEDIUM (risque #1 projet : feel = seul différenciateur Pillar 1. Si playtest fail → revisite fondamentale moveset, pas juste tuning.)

**Control Manifest Rules**:
- Required: playtest prototype `prototypes/movement-katana/` ≥ 3 sessions AVANT gate Production ; evidence screenshots + signatures dans `production/qa/evidence/` ; protocole playtest structuré (grille observation).
- Forbidden: claim "feel ok" sans playtest tiers (Martin + agents = biais auteur, ADR-0001 EC non-triggers l.290).
- Guardrail: ≥ 4 playtesters sur 5 identifient correctement cause mort sur ≥ 8 morts / 10 (garde-fou Martin r3 50 ms).

---

## Acceptance Criteria

*From GDD Feel Acceptance Criteria + AC-MV-100 + AC-MV-101 + Feel AC Attribution causale :*

- [ ] **Feel playtest (ADVISORY)** : ≥ 5 playtesters jouent 10 min libre, < 20 % prononcent mots-clés négatifs ("floaty", "slippery", "unresponsive", "raté", "stuck"). Evidence : grille structurée + signature QA Lead dans `production/qa/evidence/feel-playtest-[date].md`.
- [ ] **AC-MV-100 — Dash FOV pulse evidence** : GIVEN dash déclenché, WHEN `dash_started` émis, THEN screenshot à `t = DASH_DURATION/2` montre trail linéaire visible + `camera3d.fov ≈ 100° ±1°` (= BASE_FOV 90 + DASH_FOV_KICK 10, owned Camera). Si `reduce_motion=true` → `fov ≤ 94°` (kick ≤ 4°). Evidence : `production/qa/evidence/dash-vfx-[date].png` + signature QA Lead.
- [ ] **AC-MV-101 — Death fade rouge evidence** : GIVEN `die()` appelé, WHEN `died` émis, THEN screenshot à `t = RESPAWN_DELAY/2 ≈ 25 ms` montre fondu rouge plein écran ≤ 40 ms. Si `reduce_flash=true` → assombrissement gris neutre 80-120 ms. Evidence : `production/qa/evidence/death-fade-[date].png` + signature QA Lead.
- [ ] **Feel AC Respawn total (Integration — BLOCKING)** : GIVEN état vivant, WHEN `die()`, THEN timestamp entre `die()` et 1er `_physics_process` où `_state == State.GROUNDED AND inputs_accepted == true` < 100 ms. *(Cette assertion peut être automatisée GUT comme complément — mais evidence doc reste bénéfique pour QA Lead.)*
- [ ] **Feel AC Attribution causale 50 ms (garde-fou)** : 5 joueurs débutants (jamais joué CHROME://ASCENT), 10 morts chacun, facilitateur demande "qu'est-ce qui t'a tué ?" après chaque mort. ≥ 4 joueurs/5 identifient correctement sur ≥ 8 morts / 10. Si fail → flagger RESPAWN_DELAY suspect, revisiter en playtest MVP (potentiel 80-120 ms). Evidence : grille + signature.
- [ ] **Prototype continuity** : `prototypes/movement-katana/` playtest ≥ 3 sessions valide feel Pillar 1 AVANT gate Pre-Production → Production (DoD epic). Migration progressive prototype → `src/` doit préserver feel mesuré.
- [ ] **Anti-références respectées (observation qualitative)** : aucune session ne génère verbatim tag "j'anticipe mes inputs", "ça répond pas tout de suite", "c'est mou", "c'est flottant" (ADR-0001 EC-2). Si ≥ 1 tag verbatim → trigger EC-3 protocole (spike 120 Hz A/B blind, voir ADR-0001).

---

## Implementation Notes

*Derived from GDD Feel Acceptance Criteria + Player Fantasy :*

- Protocole playtest structuré : créer `production/qa/playtest-protocols/feel-movement-session.md` avec grille d'observation (5 mots-clés positifs attendus, 5 mots-clés négatifs à traquer, 3 questions attribution causale mort).
- Session setup : build release MVP (pas debug), hardware entry-level laptop cible (si dispo), clavier/souris. 10 min session libre + 10 morts scriptées pour attribution causale.
- Evidence naming : `production/qa/evidence/feel-playtest-session-[N]-[YYYY-MM-DD].md` ; screenshots named `dash-vfx-[YYYY-MM-DD].png`, `death-fade-[YYYY-MM-DD].png`.
- Signatures : QA Lead + éventuellement creative-director (si trigger ADR-0001 EC).
- Captures FOV/fade : utiliser `tests/scenes/combo_chain_test.tscn` + screenshot automatisé GUT `take_screenshot_at_tick(N)` helper ; FOV lu via `camera3d.fov`.
- Migration prototype : scripts `prototypes/movement-katana/player.gd` comparés à `src/core/movement_controller.gd` (post stories 001-013) — tuning values identiques (MOVE_SPEED=10, DASH_SPEED=30, etc.), feel doit être préservé.

---

## Out of Scope

- VFX assets finaux (trails, particles) → VFX epic + art-bible
- Audio assets finaux (dash_whoosh.wav, etc.) → Audio epic post-ADR-0006
- Accessibility toggles runtime implementation → Story 018 (BLOCKED ADR-0015)
- Camera FOV/tilt code implementation → Camera epic stories

---

## QA Test Cases

**Manual check Feel playtest** :
- Setup : build release MVP, 5 playtesters tiers (non-agents, non-Martin pour cohérence ADR-0001), 10 min session libre chacun.
- Verify : grille d'observation : quels mots-clés prononcés spontanément (5 positifs + 5 négatifs) ; moyenne score sur questionnaire latence (ADR-0001 EC-1 : "sur 1-5, réponse instantanée ?").
- Pass condition : < 20% mots-clés négatifs par session ; moyenne score > 3/5.

**Manual check AC-MV-100 Dash FOV** :
- Setup : debug build avec `can_dash=true`, screenshot helper
- Verify : screenshot à tick 3 (DASH_DURATION/2 = 50ms = 3 ticks) → trail visible + `camera3d.fov ∈ [99, 101]`. Avec `reduce_motion=true` → `fov ∈ [90, 94]`.
- Pass condition : 2 screenshots PNG dans `production/qa/evidence/`, signature QA Lead sur fichier Markdown associé.

**Manual check AC-MV-101 Death fade** :
- Setup : `player.die()` appelé manuellement
- Verify : screenshot à tick 2 (RESPAWN_DELAY/2 = 25ms = ~1.5 ticks, round up) → fondu rouge plein écran ≤ 40 ms ; avec `reduce_flash=true` → gris neutre 80-120 ms.
- Pass condition : screenshot + signature.

**Manual check Respawn total < 100 ms** :
- Setup : GUT test automation (complément, pas exclusivement playtest)
- Verify : timestamp `die()` → premier tick `_state==GROUNDED AND inputs_accepted`
- Pass condition : < 100 ms sur 50 iterations.

**Manual check Attribution causale 50 ms** :
- Setup : session contrôlée 5 joueurs débutants, 10 morts scriptées (lasers variés, pics, chutes)
- Verify : après chaque mort, facilitateur demande "qu'est-ce qui t'a tué ?" ; 4 options (laser rouge / pic / ennemi X / chute)
- Pass condition : ≥ 4 joueurs sur 5 identifient correctement sur ≥ 8/10 morts ; grille signée QA Lead.

**Manual check Prototype continuity** :
- Setup : comparer `prototypes/movement-katana/` (feel validé au moins 3 sessions selon `REPORT.md`) vs `src/core/movement_controller.gd` post-stories
- Verify : même feel subjectif sur dash + wall-run (au moins Martin + 2 tiers en session courte)
- Pass condition : document sign-off `production/qa/evidence/prototype-to-src-continuity-[date].md`.

---

## Test Evidence

**Story Type**: Visual/Feel (ADVISORY gate-level, mais prérequis gate Pre-Production → Production per EPIC DoD)
**Required evidence**:
- `production/qa/evidence/feel-playtest-session-1-[date].md` ; session-2 ; session-3 (≥ 3 sessions)
- `production/qa/evidence/dash-vfx-[date].png` + `death-fade-[date].png`
- `production/qa/evidence/attribution-causale-session-[date].md`
- `production/qa/evidence/prototype-to-src-continuity-[date].md`
- Signatures QA Lead sur tous les .md

**Status**: [ ] Not yet created

---

## Dependencies

- Depends on: Stories 001-016 (full implementation + tests automatisés)
- Unlocks: Gate Pre-Production → Production (DoD EPIC — playtest ≥ 3 sessions valide feel Pillar 1 prérequis)
