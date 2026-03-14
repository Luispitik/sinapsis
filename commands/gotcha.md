---
name: gotcha
description: Captura un gotcha (error→fix) como instinct de alta prioridad
trigger: /gotcha
---

# /gotcha — Captura de Gotchas

Captura errores resueltos como instincts tipo gotcha para no repetirlos.

## Modos de uso

### 1. Captura manual: `/gotcha`

Cuando el usuario dice `/gotcha` (opcionalmente con descripcion):

1. **Analizar la sesion actual** buscando el patron error→fix mas reciente:
   - Error/excepcion que ocurrio
   - Que lo causo
   - Como se resolvio
   - Cuanto tiempo/intentos llevo resolverlo

2. **Generar instinct YAML** con formato gotcha:

```yaml
---
id: gotcha-<descripcion-kebab>
trigger: "al encontrar <error/situacion>"
confidence: 0.7
domain: "<dominio-detectado>"
source: "gotcha-capture"
scope: project
type: gotcha
severity: <low|medium|high|critical>
---

# Gotcha: <titulo descriptivo>

## Problema
<Que error/situacion ocurre>

## Causa raiz
<Por que ocurre — la causa real, no el sintoma>

## Solucion
<Fix exacto, con codigo si aplica>

## Prevencion
<Como evitar que vuelva a ocurrir>

## Evidence
- Sesion: <session_id>
- Fecha: <timestamp>
- Proyecto: <nombre>
- Tiempo de resolucion: <si se puede estimar>
```

3. **Guardar** en la carpeta de instincts del proyecto:
   - Proyecto detectado → `~/.claude/homunculus/projects/<hash>/instincts/personal/`
   - Sin proyecto → `~/.claude/homunculus/instincts/personal/`

4. **Mostrar resumen** al usuario con formato:

```
╔══════════════════════════════════════════╗
║  GOTCHA CAPTURADO — Sinapsis            ║
╠══════════════════════════════════════════╣
║                                         ║
║  ID: gotcha-next-cache-corruption       ║
║  Severity: high                         ║
║  Domain: web-development                ║
║  Confidence: 0.70                       ║
║                                         ║
║  Problema:                              ║
║  Next.js devuelve paginas antiguas      ║
║  tras cambiar rutas                     ║
║                                         ║
║  Fix:                                   ║
║  rm -rf .next && npm run build          ║
║                                         ║
║  Guardado en:                           ║
║  instincts/personal/gotcha-next-*.yaml  ║
║                                         ║
╚══════════════════════════════════════════╝
```

### 2. Auto-deteccion (via hooks)

El hook observe.sh ya captura tool calls. La auto-deteccion de gotchas funciona asi:

**Patron a detectar en observations.jsonl:**
```
tool_call(X) → error en output → usuario corrige → tool_call(Y) → exito
```

Cuando el observer agent (Fase 2) encuentra este patron:
1. Clasifica como `type: gotcha` en vez de instinct normal
2. Asigna `severity` segun:
   - **critical**: error que rompe deploy/build/compilacion
   - **high**: error que causa comportamiento inesperado en produccion
   - **medium**: error que causa tiempo perdido en desarrollo
   - **low**: quirk o peculiaridad que conviene recordar
3. Asigna confidence 0.7 (primera vez) — sube si se repite en otro proyecto

### 3. Opciones

| Flag | Efecto |
|------|--------|
| `/gotcha` | Captura el error→fix mas reciente de la sesion |
| `/gotcha <descripcion>` | Captura con descripcion manual |
| `/gotcha --list` | Lista gotchas del proyecto actual |
| `/gotcha --list --global` | Lista gotchas globales |
| `/gotcha --severity high` | Fuerza severity al capturar |

### 4. Listado de gotchas

Con `--list`, mostrar tabla:

```
══════════════════════════════════════════════════════════
  GOTCHAS — proyecto: mi-saas (12 gotchas)
══════════════════════════════════════════════════════════

  SEV   ID                              CONF   DOMAIN
  ───   ──                              ────   ──────
  🔴    gotcha-prisma-json-stringify     0.90   saas-development
  🔴    gotcha-next-cache-corruption     0.85   web-development
  🟡    gotcha-vercel-sitemap-ping       0.70   deployment
  🟢    gotcha-overlay-network-deploy    0.65   deployment
  🟢    gotcha-n8n-curl-ssl             0.60   automation

  Severities: 🔴 critical/high  🟡 medium  🟢 low
══════════════════════════════════════════════════════════
```

### 5. Edge cases

- **Sin errores en sesion**: Mostrar "No se encontraron errores en esta sesion. /gotcha captura el patron error→fix mas reciente. Si resolviste un error hace tiempo, describe que paso: `/gotcha 'descripcion del error y su solucion'`"
- **Error sin resolucion**: Si hay error pero no se resolvio en la misma sesion, capturar como gotcha con severity "low" y confidence 0.3 (necesita mas evidencia)
- **Hooks no activos**: "/gotcha funciona sin hooks — analiza la sesion actual directamente. Para auto-deteccion de gotchas, activa los hooks."

### 6. Integracion con /dna

Cuando `/dna` genera MEMORY.md para un proyecto nuevo:
- Busca gotchas globales y de proyectos similares
- Los inyecta en la seccion "## Gotchas conocidos" de MEMORY.md
- Solo gotchas con confidence >= 0.6 y dominio compatible con el stack detectado

### 6. Promocion automatica

Un gotcha se promueve de project → global cuando:
- Aparece en **2+ proyectos** diferentes (mismo patron de error)
- Confidence media >= 0.75 (umbral mas bajo que instincts normales, porque gotchas son mas criticos)
- El dominio es compatible con global

---

*Sinapsis — Gotcha Auto-Capture | [SalgadoIA](https://salgadoia.com)*
