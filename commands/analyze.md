---
name: analyze
description: Ejecuta el observer agent para detectar patrones en observaciones y crear instincts
trigger: /analyze
---

# /analyze — Deteccion de Patrones (Fase 2 del Pipeline)

Invoca el observer agent para analizar observations.jsonl y crear instincts automaticamente. Este es el puente entre la Fase 1 (Observacion) y la Fase 3 (Instincts).

## Por que es necesario

El pipeline de Sinapsis tiene 4 fases:
```
Fase 1: observe.sh captura → observations.jsonl
Fase 2: /analyze detecta patrones → instincts YAML    ← ESTE COMANDO
Fase 3: /instinct-status muestra instincts
Fase 4: /evolve clusteriza instincts
```

Sin `/analyze`, las observaciones se acumulan pero nunca se convierten en instincts.

## Uso

```
/analyze                     # Analiza observaciones del proyecto actual
/analyze --global            # Analiza observaciones globales
/analyze --all               # Analiza todos los proyectos
/analyze --dry-run           # Muestra que instincts crearia sin escribir
/analyze --min-obs 5         # Solo patrones con 5+ observaciones (default: 3)
```

## Implementacion

### Paso 1: Leer observaciones

1. Detectar proyecto actual (via git remote hash)
2. Leer `~/.claude/homunculus/projects/<hash>/observations.jsonl`
3. Si `--global`: leer `~/.claude/homunculus/observations.jsonl`
4. Si `--all`: leer todos los `projects/*/observations.jsonl`
5. Parsear cada linea JSON, agrupar por sesion

### Paso 2: Detectar patrones

Seguir las instrucciones del observer agent (`agents/sinapsis-observer.md`):

**A. Correcciones del usuario:**
- Buscar secuencias: tool_call → output → siguiente tool_call que deshace/corrige
- Indicadores: misma herramienta usada 2x seguidas, Edit que revierte Edit anterior
- → Crear instinct con confidence 0.5

**B. Workflows repetidos:**
- Detectar secuencias de 2-4 tools que aparecen en 3+ sesiones diferentes
- Ejemplo: `Grep → Read → Edit` en 5 sesiones → instinct "verificar antes de editar"
- → Confidence segun tabla: 3-5 obs → 0.5, 6-10 → 0.7, 11+ → 0.85

**C. Preferencias de herramientas:**
- Herramienta X siempre usada antes de herramienta Y
- Herramienta A preferida sobre herramienta B en mismo contexto
- → Confidence segun frecuencia

**D. Patrones error→fix (gotchas):**
- tool_call → error en output → correccion → exito
- → Crear instinct con `type: gotcha` y severity estimada

### Paso 3: Deduplicar

Antes de crear un instinct nuevo:
1. Leer instincts existentes en `instincts/personal/`
2. Si existe uno con trigger similar (>80% overlap en palabras):
   - Actualizar confidence del existente (incrementar +0.05)
   - Actualizar evidence con nueva fecha
   - NO crear duplicado
3. Si es nuevo: crear fichero YAML

### Paso 4: Escribir instincts

Para cada patron detectado:
1. Generar ID kebab-case descriptivo
2. Asignar dominio segun tools usadas (Read/Edit→web-development, Bash deploy→deployment, etc.)
3. Asignar scope (project por defecto, global solo para patrones de workflow puro)
4. Escribir YAML en `~/.claude/homunculus/projects/<hash>/instincts/personal/`
5. Para globales: `~/.claude/homunculus/instincts/personal/`

### Paso 5: Mostrar resumen

```
╔══════════════════════════════════════════════════════════╗
║  ANALYZE — Sinapsis Pattern Detection                   ║
╠══════════════════════════════════════════════════════════╣
║                                                         ║
║  Proyecto: mi-saas (a1b2c3d4)                           ║
║  Observaciones analizadas: 347 (12 sesiones)            ║
║                                                         ║
║  📋 PATRONES DETECTADOS: 5                              ║
║  ───────────────────────────────                        ║
║                                                         ║
║  NUEVOS (3):                                            ║
║    + grep-before-edit              0.50  web-development ║
║    + gotcha-cache-invalidation     0.70  web-development ║
║    + always-read-skill-first       0.85  workflow-general║
║                                                         ║
║  ACTUALIZADOS (2):                                      ║
║    ^ research-before-generating    0.75→0.80  docs      ║
║    ^ test-after-edit               0.60→0.65  testing   ║
║                                                         ║
║  DESCARTADOS (1):                                       ║
║    · patron-ambiguo (< 3 observaciones)                 ║
║                                                         ║
╚══════════════════════════════════════════════════════════╝
```

## Edge cases

- **Sin observaciones**: "No hay observaciones para analizar. Asegurate de que los hooks estan activos en settings.json y usa Claude Code normalmente. Las observaciones se capturan automaticamente."
- **Observaciones insuficientes** (< 10 lineas): "Solo {N} observaciones encontradas. Se necesitan al menos 10 para detectar patrones fiables. Sigue usando Claude Code."
- **Todos los patrones ya existen**: "Todos los patrones detectados ya estan capturados como instincts. No hay novedades."
- **--dry-run**: Mostrar patrones que se crearian pero NO escribir ficheros

## Configuracion

Usa valores de `config.json`:
- `observer.min_observations_before_instinct`: minimo de observaciones para crear instinct (default: 3)
- `observer.model`: modelo a usar si se invoca como subagent (default: haiku)

## Frecuencia recomendada

- **Manual**: Ejecutar `/analyze` cada 1-2 semanas, o cuando tengas 100+ observaciones nuevas
- **Automatica**: Usar `/auto-schedule --preset` para programar analisis mensual
- **Despues de sesion larga**: Si una sesion genera 50+ tool calls, ejecutar `/analyze` al final

---

*Sinapsis — Pattern Detection | [SalgadoIA](https://salgadoia.com)*
