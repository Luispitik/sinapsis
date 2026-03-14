---
name: auto-schedule
description: Detecta acciones manuales repetidas y sugiere automatizarlas como tareas programadas
trigger: /auto-schedule
---

# /auto-schedule — Automatizacion Inteligente de Tareas Repetidas

Analiza tus patrones de uso y detecta acciones que haces manualmente de forma recurrente para sugerirte convertirlas en tareas programadas.

## Como funciona

### Paso 1: Analizar observations.jsonl

Leer observaciones de los ultimos 30 dias buscando patrones repetitivos:

**A. Comandos Bash recurrentes:**
- Misma secuencia de comandos ejecutada en 3+ sesiones diferentes
- Ejemplos: `npm run build && npm run deploy`, `git pull && npm install`, `docker compose up`

**B. Workflows de Sinapsis recurrentes:**
- `/audit` ejecutado semanalmente → sugerir auto-audit semanal
- `/instinct-status` + `/evolve` ejecutados juntos → sugerir revision periodica
- `/watchdog` ejecutado tras cada deploy → sugerir health check post-deploy

**C. Patrones temporales:**
- Acciones que ocurren siempre a la misma hora (±1h)
- Acciones que ocurren siempre el mismo dia de la semana
- Acciones que ocurren al inicio/final de sesion

**D. Secuencias pre/post deploy:**
- `test → build → deploy → health check` → sugerir pipeline automatizado

### Paso 2: Clasificar candidatos

Para cada patron detectado, evaluar:

| Criterio | Peso |
|----------|------|
| Frecuencia (veces repetido) | 40% |
| Regularidad temporal (misma hora/dia) | 30% |
| Complejidad de la tarea (pasos involucrados) | 20% |
| Ultimo uso (recencia) | 10% |

**Score minimo para sugerir: 0.6** (de 0.0 a 1.0)

### Paso 3: Presentar sugerencias

```
╔══════════════════════════════════════════════════════════╗
║  AUTO-SCHEDULE — Sinapsis                               ║
╠══════════════════════════════════════════════════════════╣
║                                                         ║
║  Analizadas 847 observaciones de 23 sesiones (30 dias)  ║
║                                                         ║
║  📋 CANDIDATOS A AUTOMATIZAR: 3                         ║
║  ───────────────────────────────                        ║
║                                                         ║
║  1. 🔄 Audit semanal                      Score: 0.92  ║
║     Patron: /audit ejecutado 4 veces,                   ║
║     siempre en lunes entre 9:00-10:00                   ║
║     Sugerencia: Cron "0 9 * * 1"                        ║
║     [Crear tarea] [Ignorar]                             ║
║                                                         ║
║  2. 🔄 Health check post-deploy            Score: 0.78  ║
║     Patron: /watchdog ejecutado tras                    ║
║     cada "vercel deploy" (6 veces)                      ║
║     Sugerencia: Hook post-deploy                        ║
║     [Crear tarea] [Ignorar]                             ║
║                                                         ║
║  3. 🔄 Dependency update check              Score: 0.65 ║
║     Patron: "npm outdated" ejecutado                    ║
║     3 veces, cada ~2 semanas                            ║
║     Sugerencia: Cron "0 10 1,15 * *"                    ║
║     [Crear tarea] [Ignorar]                             ║
║                                                         ║
║  Patrones descartados (score < 0.6): 5                  ║
║  Usa --all para verlos                                  ║
║                                                         ║
╚══════════════════════════════════════════════════════════╝
```

### Paso 4: Crear tarea (con confirmacion)

Cuando el usuario elige "Crear tarea":

1. **Generar el prompt** de la tarea basado en el patron observado
2. **Proponer cron expression** basada en la frecuencia temporal detectada
3. **Mostrar preview** al usuario:

```
──────────────────────────────────────
  Nueva tarea programada:

  ID:     sinapsis-weekly-audit
  Cron:   0 9 * * 1 (lunes 9:00)
  Prompt: "Ejecuta /audit y guarda el
          resultado en watchdog.log.
          Si hay problemas criticos,
          genera un resumen."

  ¿Confirmar? [Si] [Editar] [Cancelar]
──────────────────────────────────────
```

4. **Crear** usando `mcp__scheduled-tasks__create_scheduled_task` con los parametros confirmados

## Tareas predefinidas de Sinapsis

Ademas de la deteccion automatica, `/auto-schedule` ofrece tareas predefinidas listas para activar:

| Tarea | ID | Cron sugerido | Que hace |
|-------|-----|---------------|----------|
| **Audit semanal** | `sinapsis-weekly-audit` | `0 9 * * 1` (lunes 9h) | Ejecuta `/audit --quiet`, reporta solo problemas |
| **Decay check** | `sinapsis-decay-check` | `0 0 * * 0` (domingo 0h) | Aplica decay a instincts sin actividad, archiva < 0.2 |
| **Watchdog diario** | `sinapsis-daily-watchdog` | `0 8 * * 1-5` (L-V 8h) | Health check del proyecto activo, log resultado |
| **Observations cleanup** | `sinapsis-obs-cleanup` | `0 3 1 * *` (1o del mes 3h) | Archiva observations > 30 dias, comprime archivos |
| **Instinct evolution** | `sinapsis-monthly-evolve` | `0 10 1 * *` (1o del mes 10h) | Ejecuta `/evolve` y reporta candidatos a evolucion |

Uso:
```
/auto-schedule --preset weekly-audit
/auto-schedule --preset all           # Activa todas las predefinidas
/auto-schedule --list                 # Lista tareas activas de Sinapsis
```

## Opciones

| Flag | Efecto |
|------|--------|
| `/auto-schedule` | Analiza patrones y sugiere tareas |
| `/auto-schedule --preset <id>` | Activa una tarea predefinida |
| `/auto-schedule --preset all` | Activa todas las tareas predefinidas |
| `/auto-schedule --list` | Lista tareas programadas de Sinapsis |
| `/auto-schedule --all` | Muestra todos los candidatos (sin filtro de score) |
| `/auto-schedule --disable <id>` | Desactiva una tarea sin borrarla |
| `/auto-schedule --dry-run` | Muestra que crearia sin crear nada |

## Prompts de tareas predefinidas

### sinapsis-weekly-audit
```
Ejecuta una auditoria del ecosistema Sinapsis siguiendo las instrucciones de /audit.
Usa el flag --quiet para mostrar solo problemas.
Si encuentras problemas criticos (duplicados, contradicciones), genera un resumen
de 3-5 lineas y guardalo en ~/.claude/homunculus/watchdog.log con timestamp.
No hagas cambios automaticos — solo reporta.
```

### sinapsis-decay-check
```
Lee todos los ficheros YAML de instincts en ~/.claude/homunculus/instincts/personal/
y en ~/.claude/homunculus/projects/*/instincts/personal/.
Para cada instinct, verifica el campo "last_observed" (o fecha de ultima modificacion).
Si han pasado mas de 7 dias sin observacion, reduce confidence en 0.02.
Si confidence cae por debajo de 0.2, mueve el fichero a una carpeta _archived/ adyacente.
Reporta: cuantos instincts actualizados, cuantos archivados.
```

### sinapsis-daily-watchdog
```
Ejecuta un health check del sistema Sinapsis siguiendo las instrucciones de /watchdog.
Verifica: hooks activos, ultima observacion, instincts en decay, errores recientes.
Si hay errores nuevos no cubiertos por gotchas existentes, marca como "NUEVO — investigar".
Guarda resultado en ~/.claude/homunculus/watchdog.log con timestamp.
```

### sinapsis-obs-cleanup
```
Busca ficheros observations.jsonl en ~/.claude/homunculus/ y subdirectorios.
Para cada fichero > 5MB o con observaciones > 30 dias:
1. Mover observaciones antiguas a observations.archive/observations-YYYYMMDD.jsonl
2. Mantener solo ultimos 30 dias en el fichero principal
Reporta: espacio liberado, ficheros archivados.
```

### sinapsis-monthly-evolve
```
Ejecuta un analisis de evolucion de instincts siguiendo las instrucciones de /evolve.
NO generar ficheros (no usar --generate).
Solo analizar y reportar:
- Clusters detectados
- Candidatos a skill/command/agent
- Instincts que podrian promoverse a global
Guardar resumen en ~/.claude/homunculus/watchdog.log con timestamp.
```

## Integracion con el ecosistema

- **observe.sh**: Las observaciones son el input para la deteccion de patrones
- **/watchdog**: Las tareas de watchdog se crean via auto-schedule
- **/audit**: El audit semanal es una tarea predefinida
- **/evolve**: La evolucion mensual es una tarea predefinida
- **MCP scheduled-tasks**: Backend real para la programacion (cron + one-time + manual)

## Notas tecnicas

- Las tareas se crean usando el MCP `scheduled-tasks` de Claude Code
- Cada tarea se almacena como skill en `~/.claude/scheduled-tasks/<id>/SKILL.md`
- Las tareas se ejecutan en sesiones independientes (no interfieren con tu trabajo)
- Si Claude Code no esta abierto, las tareas pendientes se ejecutan al siguiente inicio

---

*Sinapsis — Auto-Schedule | [SalgadoIA](https://salgadoia.com)*
