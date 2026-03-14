---
name: instinct-export
description: Exporta instincts a fichero para compartir o backup
command: true
---

# /instinct-export

## Que hace

Exporta instincts a un fichero YAML. Filtrable por scope, dominio y confidence.

## Uso

```
/instinct-export                          # Exporta todos
/instinct-export --scope global           # Solo globales
/instinct-export --domain testing         # Solo testing
/instinct-export --min-confidence 0.7     # Solo confidence >= 0.7
```

## Implementacion

1. Detectar proyecto actual
2. Leer instincts segun filtros
3. Generar fichero YAML combinado en `~/.claude/homunculus/exports/`
4. Nombrar: `instincts-export-{fecha}-{filtros}.yaml`
5. Mostrar resumen de lo exportado

## Formato de salida

```
Exportados 8 instincts --> ~/.claude/homunculus/exports/instincts-export-2026-03-14-global.yaml

Resumen:
  workflow-general(3) deployment(2) testing(2) security(1)
  Confidence media: 0.87
  Scope: global(8)
```

## Privacidad

- Solo exporta instincts (patrones), nunca observaciones crudas
- No incluye codigo real, solo descripciones de patrones
- El fichero exportado es portable entre maquinas
