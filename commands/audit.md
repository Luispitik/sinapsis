---
name: audit
description: Audita skills, instincts y salud general del ecosistema Sinapsis
trigger: /audit
---

# /audit — Auditoria del Ecosistema

Escanea el ecosistema completo de skills e instincts buscando problemas, duplicados, y oportunidades de mejora.

## Ejecucion

Cuando el usuario dice `/audit`:

### Paso 1: Escanear skills locales

Leer `~/.claude/skills/` y para cada skill:
1. Leer el SKILL.md (o fichero principal)
2. Extraer: nombre, description, version, tags, tamaño (lineas)
3. Calcular hash del contenido (para detectar duplicados exactos)
4. Verificar que tiene frontmatter valido (name, description, auto_activate)

### Paso 2: Detectar problemas

**A. Duplicados exactos** (mismo contenido, diferente nombre):
- Comparar hashes de contenido
- Marcar como "DUPLICADO EXACTO" con referencia al original

**B. Duplicados semanticos** (nombre/descripcion similar, contenido diferente):
- Comparar nombres con distancia de Levenshtein o overlap de palabras
- Si 2 skills comparten >70% de palabras en su description → marcar como "POSIBLE DUPLICADO"

**C. Skills pequeñas** (candidates a merge):
- Si SKILL.md tiene < 30 lineas utiles (excluyendo frontmatter y lineas vacias)
- Marcar como "SKILL MINIMA — considerar merge"

**D. Skills sin uso reciente**:
- Buscar en observations.jsonl si alguna skill ha sido referenciada en los ultimos 30 dias
- Si no aparece → marcar como "SIN USO RECIENTE"
- Nota: esto solo funciona si los hooks estan activos

**E. Instincts problematicos**:
- Confidence < 0.4 → "CONFIANZA BAJA — considerar archivar"
- Instincts contradictorios (mismo trigger, acciones opuestas) → "CONTRADICCION"
- Instincts duplicados (mismo id en diferentes scopes) → "DUPLICADO"
- Instincts sin evidence → "SIN EVIDENCIA"
- Dominio incorrecto (trigger no encaja con dominio) → "DOMINIO SOSPECHOSO"

**F. Salud del sistema**:
- `~/.claude/homunculus/` existe y tiene estructura correcta
- `config.json` es valido
- `identity.json` tiene campos requeridos (name, language)
- Hooks configurados en `settings.json` (si no, avisar)
- observations.jsonl no esta corrupto (cada linea es JSON valido)
- Tamaño total del directorio homunculus

### Paso 3: Generar informe

Mostrar con formato:

```
╔══════════════════════════════════════════════════════════╗
║  AUDIT — Sinapsis Ecosystem Health                      ║
╠══════════════════════════════════════════════════════════╣
║                                                         ║
║  📊 RESUMEN                                             ║
║  ───────────────────────────────                        ║
║  Skills locales:        42                              ║
║  Instincts (proyecto):  14                              ║
║  Instincts (globales):  28                              ║
║  Gotchas:               8                               ║
║  Observaciones (total): 1,247                           ║
║  Tamano homunculus:     2.3 MB                          ║
║                                                         ║
║  ⚠️  PROBLEMAS ENCONTRADOS: 7                           ║
║  ───────────────────────────────                        ║
║                                                         ║
║  🔴 CRITICO (2)                                         ║
║    • Duplicado exacto: salgadoia-word-creator           ║
║      = anthropic-skills:docx (100% match)               ║
║    • Instinct contradictorio:                           ║
║      vps-por-defecto vs vercel-por-defecto              ║
║                                                         ║
║  🟡 ATENCION (3)                                        ║
║    • Skill minima: salgadoia-whisper (18 lineas)        ║
║      → Considerar merge con salgadoia-audio             ║
║    • 3 instincts con confidence < 0.4:                  ║
║      locale-prefix (0.35), cache-hint (0.28),           ║
║      overlay-net (0.22)                                 ║
║    • Dominio sospechoso: gotcha-prisma en "automation"  ║
║      → Deberia ser "saas-development"                   ║
║                                                         ║
║  🟢 SUGERENCIAS (2)                                     ║
║    • 5 skills sin uso en 30 dias                        ║
║    • 2 instincts candidatos a promocion global          ║
║      (aparecen en 3+ proyectos con conf >= 0.8)         ║
║                                                         ║
║  ✅ SALUD DEL SISTEMA                                   ║
║  ───────────────────────────────                        ║
║  Estructura homunculus:  ✓ OK                           ║
║  config.json:            ✓ Valido                       ║
║  identity.json:          ✓ Completo                     ║
║  Hooks configurados:     ✓ Pre + Post                   ║
║  observations.jsonl:     ✓ Sin corrupcion               ║
║                                                         ║
╚══════════════════════════════════════════════════════════╝
```

## Opciones

| Flag | Efecto |
|------|--------|
| `/audit` | Auditoria completa (skills + instincts + sistema) |
| `/audit --skills` | Solo audita skills locales |
| `/audit --instincts` | Solo audita instincts |
| `/audit --health` | Solo verifica salud del sistema |
| `/audit --fix` | Intenta corregir problemas automaticamente (con confirmacion) |
| `/audit --json` | Output en JSON para procesamiento |

## Auto-fix con `--fix`

Cuando se usa `--fix`, para cada problema encontrado:

1. **Duplicados exactos**: Preguntar cual mantener, borrar el otro
2. **Instincts baja confianza**: Mover a `_archived/` (no borrar)
3. **Dominios incorrectos**: Proponer cambio de dominio, aplicar con confirmacion
4. **Contradicciones**: Mostrar ambos instincts, pedir al usuario que elija
5. **Structure rota**: Recrear directorios faltantes

**Nunca borrar sin confirmacion.** Siempre archivar en vez de borrar.

## Integracion con otras features

- **Health Watchdog**: `/audit --health` es el mismo check que ejecuta el watchdog periodicamente
- **Gotcha**: Los gotchas se incluyen en el conteo de instincts con su tipo diferenciado
- **/evolve**: Tras un audit, sugerir ejecutar `/evolve` si hay instincts suficientes sin clusterizar

## Frecuencia recomendada

- Semanal para proyectos activos
- Antes de ejecutar `/evolve --generate`
- Despues de importar instincts (`/instinct-import`)
- Cuando el ecosistema supere 50 skills o 100 instincts

---

*Sinapsis — Ecosystem Audit | [SalgadoIA](https://salgadoia.com)*
