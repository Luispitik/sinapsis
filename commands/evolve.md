---
name: evolve
description: Clusteriza instincts relacionados en skills, commands o agents
command: true
---

# /evolve

## Que hace

Analiza instincts y agrupa los relacionados en estructuras de nivel superior:
- **Skill** --> patrones auto-triggered (se activan por contexto)
- **Command** --> acciones que el usuario invoca explicitamente
- **Agent** --> procesos multi-paso que necesitan aislamiento

## Implementacion

1. Detectar proyecto actual
2. Leer instincts (project + global)
3. Agrupar por trigger/domain similar
4. Identificar candidatos a skill/command/agent
5. Mostrar candidatos a promocion (project --> global)
6. Si `--generate`: escribir ficheros en `~/.claude/homunculus/evolved/`

## Reglas de evolucion

### --> Skill (Auto-triggered)
Cuando instincts describen comportamientos que deben ocurrir automaticamente:
- Patrones de estilo de codigo
- Workflows recurrentes de generacion
- Reglas de compliance o calidad

Ejemplo cluster:
- `research-before-generating` (documentation, 0.85)
- `verify-source-before-citing` (security, 0.80)
- `web-search-before-content` (documentation, 0.75)
--> Genera: skill `research-first-workflow`

### --> Command (User-invoked)
Cuando instincts describen acciones que el usuario invoca explicitamente:
- Generacion de documentos
- Workflows de investigacion
- Creacion de materiales

Ejemplo cluster:
- `generate-4-doc-pack` (documentation, 0.90)
- `always-include-architecture-doc` (documentation, 0.95)
- `validate-config-before-deploy` (deployment, 0.85)
--> Genera: command `/generate-full-package`

### --> Agent (Multi-paso complejo)
Cuando instincts describen procesos largos que necesitan aislamiento:
- Pipeline completo de research --> generate --> review
- Pipeline de testing: setup --> test --> fix --> retest

## Formato de salida

```
══════════════════════════════════════════════════
  EVOLVE ANALYSIS — 16 instincts
  Proyecto: mi-proyecto (a1b2c3d4e5f6)
  Project-scoped: 4 | Global: 12
══════════════════════════════════════════════════

High confidence (>=80%): 10

## SKILL CANDIDATES (2)
1. research-first-workflow
   Instincts: 3
   Avg confidence: 80%
   Dominios: documentation, security

2. pre-deploy-checklist
   Instincts: 2
   Avg confidence: 90%
   Dominios: deployment, security

## COMMAND CANDIDATES (1)
  /generate-full-package
    From: 3 instincts
    Avg confidence: 90%

## AGENT CANDIDATES (1)
  full-review-pipeline
    Covers 4 instincts
    Avg confidence: 86%
    Pipeline: research --> generate --> review --> test

## PROMOTION CANDIDATES (project --> global)
  ○ always-run-tests (0.80) — visto en 1 proyecto
    --> Promover cuando aparezca en 2+ proyectos

══════════════════════════════════════════════════
```

## Flags

- `--generate` — Genera ficheros ademas del analisis
- Sin flag — Solo muestra analisis, no modifica nada

## Edge cases

- **Sin instincts**: Mostrar "No hay instincts para analizar. Usa Claude Code con hooks activos para generar observaciones, o importa instincts con /instinct-import."
- **Todos con confidence < 0.5**: Mostrar analisis pero advertir "Todos los instincts tienen confianza baja. Considera confirmar algunos manualmente antes de evolucionar."
- **Sin clusters detectados**: Mostrar "No se detectan clusters. Los instincts son demasiado diversos o hay pocos. Espera a tener mas observaciones."
- **Generacion de ficheros**: Los ficheros se escriben en `~/.claude/homunculus/evolved/{skills,commands,agents}/` del proyecto o global segun el scope predominante del cluster. Si el fichero ya existe, NO sobreescribir — informar al usuario.

## Formato de ficheros generados

### Skill generada
```markdown
---
name: research-first-workflow
description: Investigar antes de generar contenido
evolved_from:
  - research-before-generating
  - verify-source-before-citing
  - web-search-before-content
domain: documentation
---

# Research-First Workflow

[Contenido generado basado en los instincts clusterizados]
```

### Command generado
```markdown
---
name: generate-full-package
description: Genera pack documental completo con validacion
command: /generate-full-package
evolved_from:
  - generate-4-doc-pack
  - always-include-architecture-doc
  - validate-config-before-deploy
---

# Generate Full Package

[Pasos generados basados en instincts]
```
