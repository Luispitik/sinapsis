---
name: promote
description: Promueve instincts de scope project a scope global
command: true
---

# /promote

## Que hace

Promueve instincts de project-scoped a global cuando cumplen criterios de madurez.

## Uso

```
/promote                          # Auto-promueve todos los que califican
/promote <instinct-id>            # Promueve uno especifico
/promote --dry-run                # Preview sin escribir
```

## Criterios de auto-promocion

Un instinct se promueve automaticamente cuando:
1. Mismo ID aparece en **2+ proyectos** diferentes
2. Confidence media **>= 0.8**
3. Dominio compatible con global: `workflow-general`, `security`, `testing`, `documentation`, `automation` (los dominios `web-development`, `saas-development`, `deployment` son project-specific por defecto)

Un instinct se promueve manualmente (con `--force`) cuando:
- Solo aparece en 1 proyecto pero confidence >= 0.9
- El usuario confirma explicitamente que es universal

## Implementacion

1. Escanear todos los directorios de proyecto en `~/.claude/homunculus/projects/`
2. Para cada instinct ID, contar en cuantos proyectos aparece
3. Calcular confidence media por instinct ID cross-proyecto
4. Los que cumplen criterios: copiar a `~/.claude/homunculus/instincts/personal/`
5. Actualizar scope a `global` en el frontmatter
6. No borrar la copia project-scoped (conviven)

## Formato de salida

```
══════════════════════════════════════════════════
  PROMOTE ANALYSIS
  Proyectos escaneados: 4
══════════════════════════════════════════════════

AUTO-PROMOTE (cumplen criterios):
  + research-before-generating
    Proyectos: proyecto-a, proyecto-b, proyecto-c (3)
    Confidence media: 0.87
    --> Promovido a global

  + verify-before-deploy
    Proyectos: proyecto-a, proyecto-b (2)
    Confidence media: 0.82
    --> Promovido a global

CANDIDATOS (casi califican):
  ○ always-run-e2e-tests
    Proyectos: proyecto-a (1) — necesita 2+
    Confidence: 0.80

Total: 2 promovidos, 1 candidato pendiente
```
