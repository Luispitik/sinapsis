---
name: projects
description: Lista proyectos conocidos con conteo de instincts y observaciones
command: true
---

# /projects

## Que hace

Lista todos los proyectos registrados en el sistema Sinapsis con estadisticas.

## Implementacion

1. Leer `~/.claude/homunculus/projects.json`
2. Para cada proyecto, contar:
   - Instincts en `projects/<hash>/instincts/personal/`
   - Lineas en `projects/<hash>/observations.jsonl`
   - Ficheros en `projects/<hash>/evolved/`
3. Mostrar tabla ordenada por ultima actividad

## Formato de salida

```
══════════════════════════════════════════════════
  PROYECTOS REGISTRADOS — Sinapsis
══════════════════════════════════════════════════

  Hash         Nombre              Instincts  Obs.   Evolved  Ultima act.
  ──────────── ─────────────────── ────────── ────── ──────── ───────────
  a1b2c3d4e5f6 mi-proyecto-web     4          287    0        2026-03-14
  b2c3d4e5f6a1 api-backend         6          412    1 skill  2026-03-12
  c3d4e5f6a1b2 landing-page        3          156    0        2026-03-10
  d4e5f6a1b2c3 mobile-app          5          203    0        2026-03-08

  Global                           12         45     0

  Total: 4 proyectos | 30 instincts | 1.103 observaciones
══════════════════════════════════════════════════
```
