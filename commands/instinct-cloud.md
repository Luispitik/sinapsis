---
name: instinct-cloud
description: Genera una skill lista para subir a claude.ai Personalizar con todos los instincts condensados
command: true
---

# /instinct-cloud

## Que hace

Genera un fichero SKILL.md listo para copiar y pegar en claude.ai > Personalizar > Skills. Condensa TODOS los instincts (globales + proyecto) en un formato compacto de tablas agrupadas por dominio.

## Uso

```
/instinct-cloud                    # Genera cloud skill con todos los instincts
```

## Implementacion

### Paso 1: Recopilar instincts y gotchas

1. Leer todos los ficheros YAML de `~/.claude/homunculus/instincts/personal/` (scope global)
2. Si estamos dentro de un proyecto (cwd tiene git remote):
   - Calcular hash del proyecto
   - Leer instincts de `~/.claude/homunculus/projects/<hash>/instincts/personal/`
3. Incluir ficheros con `type: gotcha` — estos van a la seccion "Gotchas tecnicos"
4. Parsear cada instinct: id, trigger, action, confidence, domain, scope, type, severity

### Paso 2: Leer identidad

1. Leer `~/.claude/homunculus/identity.json`
2. Extraer: nombre, rol, stack, idioma, preferencias clave
3. Si no existe, omitir seccion "Quien soy"

### Paso 3: Generar cloud skill

Crear fichero Markdown con esta estructura exacta:

```markdown
---
name: mis-instincts
description: Instincts condensados de Sinapsis -- reglas aprendidas de sesiones reales
auto_activate: true
---

# Mis Instincts (Sinapsis Cloud Sync)

> Generado automaticamente por Sinapsis el {fecha}.
> {N} instincts de {M} dominios.

## Quien soy

| Campo | Valor |
|-------|-------|
| Nombre | {identity.name} |
| Rol | {identity.role} |
| Stack | {identity.stack} |
| Idioma | {identity.language} |

## Reglas por dominio

### workflow-general

| Regla | Trigger | Confidence |
|-------|---------|------------|
| {action condensada} | {trigger} | {confidence} |
| ... | ... | ... |

### saas-development

| Regla | Trigger | Confidence |
|-------|---------|------------|
| ... | ... | ... |

{repetir para cada dominio que tenga instincts}

## Gotchas tecnicos

| Contexto | Hacer | No hacer |
|----------|-------|----------|
| {extraido de instincts tipo correccion} | {action} | {lo que se corrigio} |

## Proyectos

| Proyecto | Dominio principal | Instincts |
|----------|-------------------|-----------|
| {nombre} | {dominio} | {count} |

{solo si existe ~/.claude/homunculus/projects.json}
```

### Paso 4: Escribir fichero

1. Crear directorio `~/.claude/homunculus/exports/` si no existe
2. Escribir a `~/.claude/homunculus/exports/cloud-skill-{YYYY-MM-DD}.md`
3. Si ya existe uno del mismo dia, sobreescribir (es regenerable)

### Paso 5: Mostrar resumen

```
══════════════════════════════════════════════════
  CLOUD SYNC — Sinapsis
  Generada skill para claude.ai Personalizar
══════════════════════════════════════════════════

Instincts incluidos: {total}
  {dominio1}({count}) {dominio2}({count}) {dominio3}({count})
  {dominio4}({count}) {dominio5}({count}) ...

Fichero: ~/.claude/homunculus/exports/cloud-skill-{fecha}.md

Siguiente paso:
  1. Abre claude.ai → Personalizar → Skills
  2. Crea nueva skill (o actualiza la existente)
  3. Pega el contenido del fichero generado
  4. Guarda

══════════════════════════════════════════════════
```

## Reglas de condensacion

- Cada instinct se reduce a UNA fila de tabla: action condensada (max 80 chars), trigger, confidence
- Si hay instincts con action similar (>80% overlap), fusionar en uno con la confidence mas alta
- Ordenar dentro de cada dominio por confidence descendente
- Instincts con confidence < 0.3 se excluyen (demasiado inciertos para cloud)
- Los gotchas tecnicos se extraen de: (a) instincts con `type: gotcha` y severity >= medium, (b) instincts cuyo source sea "user-correction" o cuya action contenga "no hacer", "evitar", "nunca"
- Solo incluir gotchas con confidence >= 0.5 en la cloud skill

## Diferencia con /instinct-export

| | /instinct-export | /instinct-cloud |
|---|---|---|
| Formato | YAML crudo | Markdown condensado (SKILL.md) |
| Destino | Backup / compartir entre maquinas | claude.ai Personalizar |
| Contenido | Instincts individuales completos | Tablas condensadas por dominio |
| Filtros | scope, domain, min-confidence | Ninguno (exporta todo >= 0.3) |

## Privacidad

- Solo exporta patrones aprendidos, nunca observaciones crudas ni codigo
- El fichero generado es autocontenido y no referencia paths locales
- Seguro para subir a claude.ai como skill personal
