# Chrome Ascent — Visual Reference Prompt

> **Usage** : Prompt à coller dans Midjourney / SDXL / DALL-E / Sora pour
> générer une image cible représentant le look final visé du gameplay
> FPS first-person. À utiliser comme référence lors des reviews visuels
> et améliorations art direction.
>
> **Date** : 2026-05-11 (MVP playtest itération)

---

## Prompt principal (text-to-image)

```
First-person view inside a brutalist chrome spire, abandoned corporate
tower interior, polished gray concrete walls with sharp clean edges, no
ornamentation, Tadao Ando architecture meets Mirror's Edge minimalism.
Verticality emphasized: open shafts, stacked mezzanine platforms with
glowing amber-yellow edges signaling jumpable surfaces, cyan emissive
strips on wall-runnable surfaces. Dramatic vertical perspective looking
up a 10-meter shaft. Dystopian night sky visible through openings:
deep navy blue gradient fading to violet horizon with subtle cyan glow,
no stars, eerie procedural atmosphere. Crimson red humanoid enemy
silhouette mid-distance, sharp capsule shape glowing red emissive,
laser cone projection forward. Floating yellow "+1" damage popup, white
hitmarker cross at screen center, motion blur cyan streak indicating
recent dash. Color palette: 70% neutral gray concrete, 15% emissive
cyan accent (wall-run/dash/UI), 10% emissive amber-yellow (jumpable
platforms/score), 5% emissive red (enemies/danger). Flat shading
unlit-style materials, no specular highlights, hard shadows. Wide FOV
105 degrees. 4K cinematic, dramatic but minimal, no clutter, "Chrome
Zen" aesthetic. References: Ghost in the Shell 1995 corridors, Mirror's
Edge first-person parkour, Ghostrunner katana aesthetics, Neri Oxman
material clarity.
```

---

## Palette couleurs (hex codes pour reproduction matériaux)

| Rôle | Couleur | Hex | Notes |
|------|---------|-----|-------|
| Wall / concrete base | gris clair | `#8C8C95` | albedo, no specular |
| Floor base | gris sombre | `#5A5F66` | albedo, no specular |
| Platform jumpable | jaune ambre | `#F2BF33` | albedo + emission 0.4× |
| Wall-run cue | cyan vif | `#4DD9F2` | albedo + emission 0.3× |
| Enemy Grunt | rouge sombre | `#D92626` | albedo, no shadows |
| Sky top | navy profond | `#080D1A` | sky_top_color |
| Sky horizon | cyan turquoise | `#2E6B8C` | sky_horizon_color |
| Ground horizon | violet | `#4D1F59` | ground_horizon_color |
| HUD cyan | cyan UI | `#4DD9F2` | speed display + dash bar |
| HUD amber | jaune UI | `#F2BF26` | kill counter + popup +1 |
| Crosshair | blanc | `#FFFFFF` | 85% opacité |
| Killflash | blanc full | `#FFFFFF` | 50% opacité 120ms fade |

---

## Composition cible (cadrage image FPS)

- **Centre** : crosshair blanc 6×6 px + hitmarker croix jaune (flash kill)
- **Haut gauche** : "KILLS 12" (amber) + "01:23" (cyan dim) + "x3 STREAK" (orange pulse)
- **Haut droite** : (réservé futurs indicateurs santé / mini-map)
- **Bas centre** : dash cooldown bar 200×10 px (cyan plein / gris vide)
- **Bas droite** : speed display "47 km/h" (cyan grand)
- **Foreground droite** : katana mesh émissif cyan (visible quand swing)
- **Background** : Chrome Spire vertical, plateformes ambres empilées, grunts rouges au loin

---

## Mood / Atmosphère

- Solitude corporate — couloirs vides, lumière de secours
- Verticality : caméra légèrement tilted up pour montrer le shaft
- Speed : motion blur léger sur les bords (dash actif)
- Threat : grunt rouge visible mais distant — anticipation
- Promesse : sortie EtageExitTrigger visible dans la lointaine = "atteindre la fin"

---

## Anti-patterns visuels (à éviter)

- ❌ Textures réalistes / brick / wood
- ❌ Decals graffiti / posters / clutter
- ❌ Ennemis colorés multiples (1 type = rouge unique MVP)
- ❌ Particles abusives en idle
- ❌ Soleil dur avec ombres dramatiques (cause "zones noires" feedback Martin)
- ❌ Specular sur surfaces (Chrome Zen K.8 = flat unlit)
- ❌ UI ornementée (HUD = labels purs sans frame)

---

## Inspirations directes

1. **Mirror's Edge (DICE 2008)** — first-person parkour, color block UI
2. **Ghostrunner (One More Level 2020)** — katana neon, one-hit kill, slow-mo
3. **Tadao Ando (1970–présent)** — béton brutalist, clean concrete walls
4. **Ghost in the Shell (Oshii 1995)** — corridors corporate dystopia
5. **Neri Oxman (2007–2019)** — material clarity, biomorphic minimalism

---

## Itération

Re-générer ce prompt après chaque update significatif du look-feel jeu.
Comparer screenshot vs image cible générée. Diff → next improvements.
