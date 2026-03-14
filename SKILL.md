---
name: sinapsis
description: |
  Sistema de aprendizaje continuo para Claude Code. Observa sesiones,
  detecta patrones recurrentes, los cristaliza como instincts atomicos
  con confidence scoring, y los evoluciona en skills/commands/agents.
  USAR SIEMPRE cuando el usuario diga "que patrones he repetido", "aprende esto",
  "recuerda este patron", "evoluciona instincts", "/instinct-status", "/evolve",
  "/instinct-export", "/instinct-import", "/instinct-cloud", "/promote", "/projects", "/dna", o cuando se quiera
  revisar que ha aprendido Claude Code de sesiones anteriores.
  Tambien responde a "/analyze", "/gotcha", "/journal", "/audit", "/watchdog", "/auto-schedule".
author: SalgadoIA
version: 1.1.0
origin: Adapted from ECC v2.1 (affaan-m/everything-claude-code)
auto_activate: true
---

# Sinapsis -- Sistema de Aprendizaje Continuo

> *Cada sesion crea una conexion. Sinapsis las convierte en instinto.*

## Arquitectura

Pipeline de 4 fases:

```
Observacion --> Deteccion de patrones --> Instincts --> Evolucion
   (hooks)        (observer agent)        (YAML)      (/evolve)
```

### Fase 1: Observacion

Hooks deterministas (PreToolUse + PostToolUse) capturan cada tool call:
- tool_name, input, output, session_id, cwd
- Escritura a `~/.claude/homunculus/projects/<hash>/observations.jsonl`
- Guards: skip subagents, skip minimal profile, skip automated sessions
- Scrub de secrets (API keys, tokens, passwords)

### Fase 2: Deteccion de patrones (`/analyze`)

El comando `/analyze` invoca el observer agent para analizar observations.jsonl buscando:
1. **Correcciones del usuario** -- "No, usa X en vez de Y" --> instinct
2. **Workflows repetidos** -- secuencias de tools que se repiten --> instinct
3. **Preferencias de herramientas** -- siempre Read antes de Edit --> instinct
4. **Resolucion de errores** -- error + fix pattern --> instinct

### Fase 3: Instincts

Ficheros YAML atomicos. Cada instinct tiene:
- `id`: identificador kebab-case
- `trigger`: cuando se activa
- `confidence`: 0.0 a 1.0
- `domain`: dominio tematico
- `scope`: project o global

### Fase 4: Evolucion

`/evolve` clusteriza instincts relacionados en:
- **Skill** -- patrones auto-triggered (se activan por contexto)
- **Command** -- acciones que el usuario invoca explicitamente
- **Agent** -- procesos multi-paso que necesitan aislamiento

## Modelo de ejecucion del pipeline

| Fase | Trigger | Automatico? |
|------|---------|-------------|
| 1. Observacion | Cada tool call (hooks) | Si (si hooks activos) |
| 2. Deteccion de patrones | `/analyze` | Manual o via `/auto-schedule` |
| 3. Instincts | Output de `/analyze` | Automatico |
| 4. Evolucion | `/evolve` | Manual |

## Decisiones arquitectonicas

### Por que hooks y no skills para observar
Las skills son probabilisticas (Claude decide si activarlas). Los hooks son deterministas: se ejecutan el 100% de las veces. Cero patrones perdidos.

### Por que PreToolUse + PostToolUse y no Stop
El hook Stop se ejecuta una vez al final. Pre/Post capturan cada tool call individual con input y output.

### Por que project-scoped
Sin scoping, los patrones de un proyecto React contaminan un proyecto Django. El hash SHA256 del git remote URL genera un ID portable.

## Dominios

8 dominios genericos por defecto:

| Dominio | Descripcion |
|---------|------------|
| `workflow-general` | Patrones cross-proyecto (git, tools, flujo de trabajo) |
| `web-development` | Frontend, backend, APIs, frameworks web |
| `saas-development` | SaaS, multi-tenancy, subscriptions, plataformas |
| `deployment` | CI/CD, Docker, servidores, infraestructura |
| `automation` | Scripts, workflows automatizados, integraciones |
| `documentation` | Docs, READMEs, comentarios, especificaciones |
| `testing` | Tests unitarios, integracion, E2E, QA |
| `security` | Auth, permisos, secrets, compliance |

Los dominios son configurables en `config.json`. Anade los que necesites.

## Modelo de instinct

```yaml
---
id: ejemplo-instinct-descriptivo
trigger: "al hacer X en contexto Y"
confidence: 0.7
domain: "workflow-general"
source: "session-observation"
scope: project
---

# Titulo descriptivo

## Action
Que hacer -- concreto, accionable.

## Evidence
- Que observaciones lo generaron
- Frecuencia
- Ultima observacion: fecha
```

## Estructura de ficheros

```
~/.claude/homunculus/
├── identity.json
├── config.json
├── projects.json
├── observations.jsonl
├── instincts/
│   ├── personal/
│   └── inherited/
├── evolved/
│   ├── skills/
│   ├── commands/
│   └── agents/
└── projects/
    └── <hash>/
        ├── project.json
        ├── observations.jsonl
        ├── observations.archive/
        ├── instincts/
        │   ├── personal/
        │   └── inherited/
        └── evolved/
            ├── skills/
            ├── commands/
            └── agents/
```

## Comandos

| Comando | Que hace |
|---------|----------|
| `/instinct-status` | Muestra instincts con confidence scoring |
| `/evolve` | Analiza y clusteriza instincts |
| `/evolve --generate` | Genera ficheros de skills/commands/agents |
| `/instinct-export` | Exporta instincts (filtrable) |
| `/instinct-import <file>` | Importa instincts con control de scope |
| `/promote [id]` | Promueve instinct project --> global |
| `/projects` | Lista proyectos con estadisticas |
| `/instinct-cloud` | Genera skill para claude.ai Personalizar con instincts condensados |
| `/dna` | Detecta stack, hereda instincts de proyectos similares, genera MEMORY.md |
| `/analyze` | Ejecuta observer: detecta patrones en observaciones y crea instincts |
| `/gotcha` | Captura error→fix como instinct tipo gotcha con severity |
| `/journal` | Diario de proyecto: registra pasos, decisiones y gotchas para replicabilidad |
| `/audit` | Audita skills, instincts, duplicados y salud del sistema |
| `/watchdog` | Health monitor: build, deploy, errores, estado del sistema |
| `/auto-schedule` | Detecta acciones repetidas y sugiere tareas programadas |

## Confidence y decay

| Escenario | Ajuste |
|-----------|--------|
| Patron observado de nuevo | +0.05 |
| Usuario confirma explicitamente | +0.1 |
| Usuario contradice | -0.1 |
| 1 semana sin observacion | -0.02 |
| Confidence < 0.2 | Se archiva (no se borra) |

## Criterios de promocion (project --> global)

- Mismo instinct ID en **2+ proyectos** diferentes
- Confidence media **>= 0.8**
- Dominio compatible con global

**Regla: en duda, scope project. Promover despues es seguro. Contaminar global es costoso.**

## Sistema de memoria de 3 capas

| Capa | Fichero | Proposito |
|------|---------|-----------|
| **Skill** | `SKILL.md` | Arquitectura, reglas, comandos |
| **Memory** | `MEMORY.md` | Decisiones de proyecto, contexto actual |
| **Env** | `.env.local` | Variables sensibles, paths locales |

## Integracion con Claude web

Exporta instincts de alta confianza como cloud skill:
1. `/instinct-export --min-confidence 0.7`
2. Usa plantilla `examples/cloud-skill-template.md`
3. Sube como Project Knowledge en claude.ai

## Project DNA — Herencia Inteligente

El comando `/dna` analiza el ADN tecnologico de un proyecto nuevo y transfiere conocimiento de proyectos anteriores.

### Como funciona la deteccion de stack

`/dna` escanea ficheros de configuracion en el directorio actual para identificar tecnologias:

| Fichero escaneado | Tecnologias detectadas |
|-------------------|----------------------|
| `package.json` | Next.js, React, Supabase, Stripe, Prisma, Tailwind, shadcn, Vercel AI SDK, next-intl |
| `requirements.txt` / `pyproject.toml` | Django, FastAPI, Flask, SQLAlchemy, etc. |
| `Cargo.toml` | Rust y sus crates |
| `go.mod` | Go y sus modulos |
| `docker-compose.yml` / `Dockerfile` | Servicios de infraestructura (postgres, redis, nginx) |
| `.env.example` / `.env.local` | Servicios externos (Supabase, Stripe, OpenAI, etc.) |
| `prisma/schema.prisma` | Base de datos y provider |
| `tailwind.config.*` | Tailwind CSS |
| `next.config.*` | Next.js |
| `vercel.json` / `netlify.toml` | Plataforma de deployment |
| `.github/workflows/` | CI/CD |

Se extraen nombres de tecnologias, versiones cuando estan disponibles, y la fuente de deteccion.

### Como funciona el similarity scoring

Se usa el coeficiente de Jaccard entre stacks:

```
similarity = |stack_actual ∩ stack_proyecto| / |stack_actual ∪ stack_proyecto| × 100
```

Solo se muestran proyectos con >= 50% de match, ordenados por similitud descendente (top 5).

### Como funciona la herencia de instincts

1. Se leen todos los instincts globales de `~/.claude/homunculus/instincts/personal/`
2. Se filtran por dominio usando la tabla de mapping stack-a-dominio
3. Se agrupan por nivel de confianza (alta >= 0.90, fuerte 0.80-0.89, moderada 0.60-0.79)
4. Solo se heredan instincts con confidence >= 0.60
5. Al heredar, se copian a `.claude/instincts/inherited/` del proyecto con `scope: project`

### Mapping stack-a-dominio

| Tecnologia | Dominios mapeados |
|-----------|------------------|
| Next.js, React, Vue, Angular, Svelte | `saas-development`, `web-development` |
| Supabase | `saas-development`, `supabase-patterns` |
| Stripe, Lemon Squeezy | `stripe-billing`, `saas-development` |
| Docker, Kubernetes, Nginx | `infraestructura`, `deployment` |
| n8n | `automation`, `n8n-workflows` |
| Python, Django, FastAPI, Flask | `workflow-general`, `web-development` |
| Prisma, Drizzle, TypeORM | `saas-development`, `web-development` |
| Tailwind CSS, shadcn | `web-development`, `saas-development` |
| Vercel AI SDK, OpenAI, Anthropic | `saas-development`, `ai-integration` |
| GitHub Actions, CI/CD | `deployment`, `automation` |
| Rust | `systems-development`, `workflow-general` |
| Go | `systems-development`, `workflow-general` |
| PostgreSQL, MySQL, SQLite | `saas-development`, `web-development` |
| Redis, RabbitMQ, Kafka | `infraestructura`, `deployment` |
| next-intl, i18n | `saas-development`, `web-development` |
| Vercel, Netlify, Railway | `deployment` |

### Como funciona la auto-generacion de MEMORY.md

`/dna` puede generar un `MEMORY.md` inicial para el proyecto que incluye:

1. **Stack detectado** — tabla con tecnologia, version y fuente
2. **Ficheros clave** — template vacio para completar manualmente
3. **Gotchas conocidos** — pre-poblado desde instincts heredados de alta confianza
4. **APIs y Servicios** — auto-detectado desde variables de entorno (.env.example)
5. **Deployment** — template vacio para configurar despues
6. **Decisiones de arquitectura** — tabla vacia para documentar conforme avanza el proyecto
7. **Sistema de 3 capas** — recordatorio de como funciona la memoria (SKILL.md / MEMORY.md / .env.local)

Esto da al proyecto un punto de partida con conocimiento heredado en lugar de empezar de cero.

## Gotcha Auto-Capture

Los gotchas son instincts especiales que capturan patrones error→fix:
- **Manual**: `/gotcha` analiza la sesion actual buscando el error mas reciente y su resolucion
- **Auto**: El observer detecta patrones `tool(X)→error→correccion→tool(Y)→exito` en observations.jsonl
- Cada gotcha tiene `type: gotcha` y `severity: low|medium|high|critical`
- Se integran con `/dna` (inyecta gotchas conocidos en MEMORY.md de proyectos nuevos)
- Promocion a global con umbral mas bajo (confidence >= 0.75 en 2+ proyectos)

## Ecosystem Audit

`/audit` escanea el ecosistema completo buscando problemas:
- **Duplicados exactos**: Skills con mismo contenido y diferente nombre
- **Duplicados semanticos**: Skills con >70% overlap en descripcion
- **Skills minimas**: <30 lineas utiles → candidatas a merge
- **Sin uso reciente**: No aparecen en observaciones de 30 dias
- **Instincts problematicos**: Baja confianza, contradicciones, dominio incorrecto
- **Salud del sistema**: Estructura, config, hooks, corrupcion
- Con `--fix`: Correccion automatica con confirmacion (nunca borra, siempre archiva)

## Health Watchdog

`/watchdog` monitoriza salud del sistema y del proyecto:
- **Sistema**: Hooks activos, ultima observacion, instincts decaying, config valido
- **Proyecto**: Build status, deploy status, health endpoint, errores recientes
- **Alertas**: Errores criticos en observe.sh emiten warnings en stderr
- **Log**: Escribe resumen en `~/.claude/homunculus/watchdog.log` para ver tendencias
- Cruza errores con gotchas existentes: si ya tiene solucion → la muestra

## Project Journal

`/journal` mantiene un `JOURNAL.md` en cada proyecto con trazabilidad completa:
- **Pasos**: Cada accion relevante queda registrada con fecha (`[STEP]`)
- **Decisiones**: Arquitectura, stack, herramientas — con razon y alternativas descartadas (`[DECISION]`)
- **Gotchas**: Errores encontrados y sus soluciones (`[ERROR→FIX]`)
- **Auto-sync**: Con `--auto-sync`, sincroniza con observaciones recientes
- **Resumen**: Con `--summary`, genera resumen ejecutivo del proyecto
- Complementa MEMORY.md: MEMORY es "que sabe Claude", JOURNAL es "que se ha hecho, cuando y por que"

## Auto-Schedule

`/auto-schedule` detecta acciones manuales repetidas y las convierte en tareas programadas:
- **Deteccion**: Analiza observations.jsonl buscando comandos/workflows ejecutados 3+ veces con patron temporal
- **Scoring**: Frecuencia (40%) + regularidad temporal (30%) + complejidad (20%) + recencia (10%)
- **Presets**: 5 tareas predefinidas listas para activar (audit semanal, decay check, watchdog diario, obs cleanup, evolve mensual)
- **Backend**: Usa MCP scheduled-tasks de Claude Code para la programacion real
- Las tareas se ejecutan en sesiones independientes, no interfieren con tu trabajo

## Auditoria de skills (checklist manual)

Checklist periodico:
- Revisar instincts con confidence < 0.4
- Verificar no hay duplicados o contradictorios
- Comprobar dominios correctos
- Ejecutar `/instinct-status` para vision general
- Ejecutar `/evolve` para ver candidatos
- Revisar `evolved/` -- eliminar obsoletas
- Confirmar que globales son realmente cross-proyecto

---

*Adaptado de [ECC v2.1](https://github.com/affaan-m/everything-claude-code) | Empaquetado por [SalgadoIA](https://salgadoia.com)*

<sub>Builded by SalgadoIA</sub>
