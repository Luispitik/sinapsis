---
name: instinct-import
description: Importa instincts desde fichero con control de scope
command: true
---

# /instinct-import

## Que hace

Importa instincts desde un fichero YAML exportado previamente o compartido.

## Uso

```
/instinct-import <ruta-fichero>                    # Importa como inherited
/instinct-import <ruta> --scope project            # Fuerza scope project
/instinct-import <ruta> --scope global             # Fuerza scope global
/instinct-import <ruta> --dry-run                  # Preview sin escribir
```

## Implementacion

1. Leer y parsear fichero YAML (validar formato frontmatter)
2. Para cada instinct:
   - Validar ID (kebab-case, sin path traversal)
   - Verificar si ya existe (por ID) — si existe, comparar confidence
   - Si nuevo: guardar en `inherited/` del scope correspondiente
   - Si existente con mayor confidence: actualizar
   - Si existente con menor confidence: skip (informar)
3. Mostrar resumen de importacion

## Formato de salida

```
Importando desde: instincts-export-2026-03-14.yaml

  + research-before-generating       --> inherited/global (nuevo, 0.85)
  + verify-source-before-citing      --> inherited/global (nuevo, 0.80)
  · always-include-architecture-doc  --> skip (ya existe con confidence superior 0.95)
  ^ format-correction-mandatory      --> actualizado (0.85 --> 0.90)

Resultado: 2 nuevos, 1 actualizado, 1 omitido
```

## Seguridad

- Validar cada instinct ID contra regex: `^[a-z0-9][a-z0-9-]*[a-z0-9]$` (kebab-case estricto)
- Maximo 128 caracteres por ID
- Rechazar IDs con `..`, `/`, `\`, `.` o que empiecen por `-`
- Si existente con **igual** confidence: skip (mantener el existente)
- **OBLIGATORIO**: Usar `yaml.safe_load()` — NUNCA `yaml.load()` (previene deserializacion insegura)
- No ejecutar codigo del fichero importado — solo parsear YAML
- Validar que el frontmatter contiene solo claves permitidas: id, trigger, confidence, domain, source, scope, type, severity
