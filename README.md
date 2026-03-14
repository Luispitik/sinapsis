# Sinapsis

> *Cada sesion crea una conexion. Sinapsis las convierte en instinto.*

**Sistema de aprendizaje continuo para Claude Code.**

---

## Que es Sinapsis

Imagina que contratas a un aprendiz. El primer dia no sabe nada de como trabajas. Pero te observa: ve que siempre lees las instrucciones antes de ejecutar, que prefieres castellano, que odias que te pregunten cosas que ya explicaste. Al cabo de una semana, ese aprendiz anticipa tus preferencias sin que se lo pidas.

Sinapsis convierte a Claude Code en ese aprendiz.

Cada vez que usas Claude Code, Sinapsis observa silenciosamente tus patrones: que herramientas usas, en que orden, que corriges, que repites. Esas observaciones se destilan en **instincts** -- reglas atomicas con un nivel de confianza -- que Claude Code aplica automaticamente en sesiones futuras.

No es magia. Es un pipeline de 4 fases, determinista y transparente.

---

## Como funciona

```
┌─────────────────────────────────────────────────────────┐
│  FASE 1: OBSERVACION (hooks -- 100% determinista)       │
│                                                         │
│  PreToolUse + PostToolUse --> observe.sh                 │
│  Captura: tool_name, input, output, session_id, cwd     │
│  Escribe: ~/.claude/homunculus/projects/<hash>/          │
│           observations.jsonl                             │
│                                                         │
│  Guards: skip subagents, skip minimal profile,           │
│          skip automated sessions, scrub secrets          │
└──────────────────────┬──────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────┐
│  FASE 2: DETECCION DE PATRONES (observer agent)         │
│                                                         │
│  Analiza observations.jsonl buscando:                    │
│  - Correcciones del usuario ("No, usa X en vez de Y")   │
│  - Resolucion de errores (error --> fix --> patron)      │
│  - Workflows repetidos (Grep --> Read --> Edit)          │
│  - Preferencias de herramientas                         │
│                                                         │
│  Confidence: 1-2 obs --> 0.3 | 3-5 --> 0.5              │
│              6-10 --> 0.7    | 11+ --> 0.85              │
└──────────────────────┬──────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────┐
│  FASE 3: INSTINCTS (ficheros YAML atomicos)             │
│                                                         │
│  Cada instinct = 1 trigger + 1 action + confidence      │
│  Scope: project (por hash de git remote) o global       │
│  Dominios: workflow-general, web-development,            │
│    saas-development, deployment, automation,             │
│    documentation, testing, security                      │
└──────────────────────┬──────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────┐
│  FASE 4: EVOLUCION (/evolve)                            │
│                                                         │
│  Clusteriza instincts relacionados -->                   │
│  --> Skill (patrones auto-triggered)                     │
│  --> Command (acciones invocadas por usuario)            │
│  --> Agent (procesos multi-paso complejos)               │
│                                                         │
│  Promocion: project --> global cuando aparece en 2+      │
│  proyectos con confidence >= 0.8                         │
└─────────────────────────────────────────────────────────┘
```

---

## Instalacion rapida

### Con script

```bash
bash install.sh
```

El script crea la estructura de directorios, copia ficheros de configuracion y registra la skill.

### Manual

```bash
# 1. Crear estructura
mkdir -p ~/.claude/homunculus/{instincts/{personal,inherited},evolved/{agents,skills,commands},projects}

# 2. Copiar configuracion
cp identity.json ~/.claude/homunculus/identity.json
cp config.json ~/.claude/homunculus/config.json

# 3. Copiar seed instincts
cp instincts/personal/sinapsis-seed.yaml ~/.claude/homunculus/instincts/personal/

# 4. Instalar skill
mkdir -p ~/.claude/skills/sinapsis/
cp SKILL.md ~/.claude/skills/sinapsis/
cp -r hooks/ ~/.claude/skills/sinapsis/hooks/
cp -r agents/ ~/.claude/skills/sinapsis/agents/
cp -r commands/ ~/.claude/skills/sinapsis/commands/

# 5. Instalar commands
mkdir -p ~/.claude/commands/
cp commands/*.md ~/.claude/commands/
```

---

## Configuracion de hooks (opcional)

Los hooks permiten observacion automatica de cada tool call. Anadir a `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "*",
      "hooks": [{
        "type": "command",
        "command": "bash ~/.claude/skills/sinapsis/hooks/observe.sh pre",
        "async": true,
        "timeout": 10
      }]
    }],
    "PostToolUse": [{
      "matcher": "*",
      "hooks": [{
        "type": "command",
        "command": "bash ~/.claude/skills/sinapsis/hooks/observe.sh post",
        "async": true,
        "timeout": 10
      }]
    }]
  }
}
```

> **Nota**: Sin hooks, Sinapsis funciona con los comandos manuales (`/evolve`, `/instinct-status`, etc.) pero no captura observaciones automaticamente.

---

## Personalizacion

### identity.json

Fichero con tu perfil. Edita los campos segun tu contexto:

```json
{
  "name": "Tu nombre",
  "role": "Tu rol",
  "stack": ["tus", "tecnologias"],
  "marcas": [],
  "location": "Tu ciudad",
  "language": "es"
}
```

### config.json

Configuracion del sistema: dominios, umbrales, decay. Los valores por defecto son genericos y funcionan para cualquier desarrollador.

### Seed instincts

El sistema incluye un instinct semilla: "Leer SKILL.md antes de ejecutar cualquier skill". Puedes anadir los tuyos en `~/.claude/homunculus/instincts/personal/`.

---

## Comandos disponibles

| Comando | Que hace |
|---------|----------|
| `/instinct-status` | Muestra instincts (proyecto + globales) con confidence |
| `/evolve` | Analiza y clusteriza instincts en skills/commands/agents |
| `/evolve --generate` | Ademas genera los ficheros |
| `/instinct-export` | Exporta instincts (filtrable por scope/domain/confidence) |
| `/instinct-import <file>` | Importa instincts con control de scope |
| `/promote [id]` | Promueve instinct de proyecto a global |
| `/projects` | Lista proyectos conocidos con estadisticas |
| `/instinct-cloud` | Genera skill para claude.ai Personalizar con instincts condensados |
| `/dna` | Detecta stack, hereda instincts de proyectos similares, genera MEMORY.md |
| `/analyze` | Ejecuta observer: detecta patrones en observaciones y crea instincts |
| `/gotcha` | Captura error→fix como instinct tipo gotcha con severity |
| `/journal` | Diario de proyecto: pasos, decisiones y gotchas para replicabilidad |
| `/audit` | Audita skills, instincts, duplicados y salud del ecosistema |
| `/watchdog` | Health monitor: build, deploy, errores recientes, estado del sistema |
| `/auto-schedule` | Detecta acciones repetidas y las convierte en tareas programadas |

---

## Project DNA — Herencia inteligente

Cuando empiezas un proyecto nuevo, `/dna` escanea el stack (package.json, prisma, docker, .env...) y lo compara con proyectos anteriores. Si encuentra similitudes, te ofrece heredar los instincts relevantes.

```
══════════════════════════════════════════════════
  PROJECT DNA — Sinapsis
══════════════════════════════════════════════════

Stack detectado:
  ✓ Next.js 16 (package.json)
  ✓ Supabase (@supabase/ssr)
  ✓ Stripe (@stripe/stripe-js)
  ✓ Prisma (prisma/schema.prisma)

Proyectos similares:
  1. mi-saas-anterior (85% match)

Instincts heredables: 12
  ● locale-prefix-always       0.95
  ● prisma-json-stringify      0.90
  ● stripe-id-en-user          0.90
  ... +9 mas

[Heredar todos] [Elegir] [No]
══════════════════════════════════════════════════
```

Ademas genera un `MEMORY.md` inicial basado en el stack detectado, con secciones pre-rellenadas de gotchas conocidos.

---

## Cloud Sync

`/instinct-cloud` condensa todos tus instincts en una unica skill lista para subir a claude.ai → Personalizar. Asi Claude web tambien tiene acceso a tus reglas aprendidas sin necesidad de ficheros locales.

---

## Que diferencia a Sinapsis de ECC v2.1

| Capacidad | ECC v2.1 | Sinapsis |
|-----------|----------|----------|
| Observar patrones y crear instincts | ✅ | ✅ |
| Confidence scoring con decay | ✅ | ✅ |
| Project scoping | ✅ | ✅ |
| Evolucion en skills/commands/agents | ✅ | ✅ |
| Pattern analyzer (/analyze — Fase 2 invocable) | ❌ | ✅ |
| Auto-schedule (tareas programadas inteligentes) | ❌ | ✅ |
| Gotcha auto-capture (error→fix patterns) | ❌ | ✅ |
| Ecosystem audit (/audit) | ❌ | ✅ |
| Health watchdog (/watchdog) | ❌ | ✅ |
| Project Journal (trazabilidad y replicabilidad) | ❌ | ✅ |
| Scrub secrets avanzado (JWT, PEM, Bearer) | ❌ | ✅ |
| Dominios personalizables (8 por defecto) | ❌ | ✅ |
| Sistema de marcas (multi-brand) | ❌ | ✅ |
| Memoria 3 capas (MEMORY + SKILL + .env) | ❌ | ✅ |
| Cloud sync con claude.ai | ❌ | ✅ |
| Project DNA (herencia inteligente) | ❌ | ✅ |
| MEMORY.md auto-generator | ❌ | ✅ |
| Metodologia de auditoria de skills | ❌ | ✅ |
| Instalador automatico | ❌ | ✅ |

---

## Estructura de ficheros

```
~/.claude/homunculus/
├── identity.json           # Tu perfil
├── config.json             # Configuracion del sistema
├── projects.json           # Registry de proyectos detectados
├── observations.jsonl      # Observaciones globales (fallback)
├── instincts/
│   ├── personal/           # Instincts globales auto-aprendidos
│   └── inherited/          # Instincts importados de otros
├── evolved/
│   ├── skills/             # Skills evolucionadas
│   ├── commands/           # Commands evolucionados
│   └── agents/             # Agents evolucionados
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

---

## Confidence scoring

| Observaciones | Confidence |
|--------------|------------|
| 1-2 | 0.3 (tentativo) |
| 3-5 | 0.5 (moderado) |
| 6-10 | 0.7 (fuerte) |
| 11+ | 0.85 (muy fuerte) |
| Confirmacion explicita del usuario | +0.1 |
| Contradiccion del usuario | -0.1 |
| 1 semana sin observacion | -0.02 (decay) |
| Confidence < 0.2 | Se archiva (no se borra) |

### Criterios de promocion (project --> global)

- Mismo instinct ID en **2+ proyectos** diferentes
- Confidence media **>= 0.8**
- Dominio compatible con global

---

## Integracion con Claude web (cloud skill)

Sinapsis vive en Claude Code (CLI), pero puedes exportar tus instincts como un cloud skill para usar en claude.ai:

1. Ejecuta `/instinct-export --min-confidence 0.7`
2. Usa la plantilla en `examples/cloud-skill-template.md`
3. Pega tus instincts exportados en la seccion correspondiente
4. Sube como Project Knowledge en claude.ai

---

## Sistema de memoria de 3 capas

Sinapsis opera dentro de un ecosistema de memoria de 3 capas:

| Capa | Fichero | Proposito | Persistencia |
|------|---------|-----------|-------------|
| **Skill** | `SKILL.md` | Arquitectura, reglas, comandos del sistema | Permanente (versionado) |
| **Memory** | `MEMORY.md` | Decisiones de proyecto, contexto actual | Por proyecto |
| **Env** | `.env.local` | Variables sensibles, API keys, paths locales | Local (nunca en git) |

Sinapsis lee SKILL.md para saber como operar, consulta MEMORY.md para contexto del proyecto actual, y respeta .env.local para configuracion sensible.

---

## Auditoria de skills (metodologia)

Cada cierto tiempo conviene auditar que las skills generadas por `/evolve` sigan siendo utiles:

- [ ] Revisar instincts con confidence < 0.4 -- considerar archivar
- [ ] Verificar que no hay instincts duplicados o contradictorios
- [ ] Comprobar que los dominios asignados son correctos
- [ ] Ejecutar `/instinct-status` y revisar la distribucion por dominio
- [ ] Ejecutar `/evolve` (sin --generate) para ver candidatos de evolucion
- [ ] Revisar skills en `evolved/` -- eliminar las obsoletas
- [ ] Confirmar que los instincts globales realmente son cross-proyecto

---

## Origen y creditos

Sinapsis nace como una evolucion de [Everything Claude Code (ECC) v2.1](https://github.com/affaan-m/everything-claude-code) por [affaan-m](https://github.com/affaan-m), que establecio el concepto original de hooks de observacion y aprendizaje para Claude Code.

A partir de esa base, Sinapsis ha sido reescrito, ampliado y empaquetado como un sistema independiente con 18+ features diferenciales: pattern analyzer, gotcha auto-capture, ecosystem audit, health watchdog, project journal, advanced secret scrubbing, project DNA, cloud sync, auto-schedule, y mas.

Gracias a affaan-m por abrir el camino.

---

## Licencia

Apache 2.0 — ver [LICENSE](./LICENSE)

---

## Autor

**Luis Salgado** — [SalgadoIA](https://salgadoia.com) · [NorteIA](https://norteia.com)

<sub>Builded by SalgadoIA</sub>
