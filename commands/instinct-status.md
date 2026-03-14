---
name: instinct-status
description: Muestra todos los instincts aprendidos (proyecto + globales) con confidence scoring
command: true
---

# /instinct-status

## Que hace

Muestra el estado de todos los instincts del sistema Sinapsis.

## Implementacion

1. Detectar proyecto actual (git remote hash o path)
2. Leer instincts de `~/.claude/homunculus/projects/<hash>/instincts/personal/`
3. Leer instincts globales de `~/.claude/homunculus/instincts/personal/`
4. Mostrar tabla con: ID, trigger, confidence, domain, scope

## Formato de salida

```
══════════════════════════════════════════════════
  INSTINCT STATUS — Sinapsis
  Proyecto: mi-proyecto (a1b2c3d4e5f6)
══════════════════════════════════════════════════

PROJECT-SCOPED (3 instincts):
  ● always-run-tests-before-push   [testing]    0.80
  ● check-env-before-deploy        [deployment] 0.75
  ● use-typescript-strict           [web-dev]    0.70

GLOBAL (5 instincts):
  ● leer-instrucciones-antes-de-ejecutar [workflow]  0.90
  ● research-before-generating     [workflow]  0.85
  ● format-correction-mandatory    [workflow]  0.90
  ● castellano-por-defecto         [workflow]  0.95
  ○ nueva-observacion-pendiente    [automation] 0.35

  ● = confidence >= 0.5  ○ = tentativo (<0.5)

Dominios: workflow(4) testing(1) deployment(1) web-dev(1) automation(1)
Total: 8 instincts | 3 project | 5 global
══════════════════════════════════════════════════
```

## Lo que NO hacer
- No inventar instincts que no existan en los ficheros
- No mostrar observaciones crudas, solo instincts procesados
- No modificar ficheros -- este comando es solo lectura
