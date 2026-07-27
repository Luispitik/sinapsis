---
name: dashboard-sinapsis
description: Dashboard visual del sistema Sinapsis con datos reales (instincts, skills, passive rules, proposals, activaciones, evolución y timings). Regenera _dashboard.html autocontenido.
command: /dashboard-sinapsis
---

# /dashboard-sinapsis

## Trigger

Run with `/dashboard-sinapsis`, "dashboard sinapsis", "ver dashboard", "muestra el dashboard".

## What it does

Regenera `~/.claude/skills/_dashboard.html` — dashboard visual editorial con datos reales parseados de los ficheros del pipeline de Sinapsis. Determinista, sin LLM, milisegundos.

Incluye 8 KPIs, velocity, timings por hora del día, maduración de instincts, heatmap 21 días, funnel de maduración, radar de dominios, leaderboards de instincts y passive rules, doughnut de skills, tabla de dormidos, barras de proyectos y timeline de decisiones.

## Implementation

### Step 1: Execute the generator

Run the Python script directly (not via LLM reasoning — es determinista):

```bash
python ~/.claude/skills/_generate-dashboard.py
```

El script lee en paralelo:
- `_instincts-index.json`
- `_passive-rules.json` + `_passive.log`
- `_instinct-proposals.json`
- `_instinct.log` (distribución por hora + heatmap 21d)
- `_catalog.json` (skills)
- `_sinapsis-projects.json` + `homunculus/projects/*/observations.jsonl`
- `_operator-state.json` (decisiones estratégicas)

Y escribe `~/.claude/skills/_dashboard.html` autocontenido (Chart.js + Google Fonts via CDN).

### Step 2: Report URL and offer to open

Tras ejecutar el script, muestra al usuario:

```
Dashboard regenerado: ~/.claude/skills/_dashboard.html

Acceso:
  · Preview server (si está arrancado): http://localhost:8080/_dashboard.html
  · Directamente:                       file://<HOME>/.claude/skills/_dashboard.html

Próxima regeneración automática: diaria por sinapsis-linting
```

Sustituye `<HOME>` por la ruta absoluta del home real del usuario — `file://` no expande `~`.

Si el preview server de `.claude/launch.json` (name=`dashboard-static`) está activo, basta con navegar a la URL.
Si no está activo, ofrece arrancarlo con `preview_start` del MCP Claude_Preview (solo si el usuario lo pide).

### Step 3: Handle errors

- Si falla el Python con "template not found": el instalador deja el template en `~/.claude/skills/_dashboard-template.html` (origen: `core/_dashboard-template.html`) — verificar que existe.
- Si falla por fichero JSON corrupto: el script ya gestiona `default` en `load_json`, seguirá con ceros.
- Si no hay `_instinct.log`: el heatmap y hour-distribution estarán a cero, el resto del dashboard funciona.

## Why this is not a skill but a command

Es una operación determinista pura (parseo + agregación + template fill). No requiere reasoning de Claude. Ejecutarla como script Python directo ahorra tokens y es consistente entre ejecuciones. El comando sólo orquesta el run + reporte.

## Related

- `/instinct-status` — vista terminal rápida de instincts
- `/passive-status` — dashboard terminal de passive rules
- `/system-status` — estado textual del sistema completo
- `/dream` — limpieza de instincts dormidos (detectados aquí)
- `/evolve` — cluster de instincts a skills/rules
- `sinapsis-linting` scheduled task — regenera este dashboard + `_knowledge-index.md` diariamente
