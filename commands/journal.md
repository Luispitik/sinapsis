---
name: journal
description: Registra pasos dados y decisiones tomadas en el proyecto para trazabilidad y replicabilidad
trigger: /journal
---

# /journal — Diario de Proyecto

Mantiene un documento vivo (`JOURNAL.md`) con los pasos dados y las decisiones tomadas en cada proyecto. Garantiza trazabilidad completa y permite replicar el proyecto desde cero.

## Por que es necesario

Sin un diario, despues de 2 meses trabajando en un proyecto:
- No recuerdas por que elegiste Supabase en vez de Firebase
- No sabes en que orden se implementaron las features
- No puedes replicar el setup para un proyecto similar
- Onboarding de otro dev es un "mira el historial de git"

Con JOURNAL.md, todo queda documentado automaticamente.

## Uso

```
/journal                         # Muestra el diario actual del proyecto
/journal "Decisión: usar Stripe en vez de Lemon Squeezy por soporte EU"
/journal --step "Configurado Prisma con PostgreSQL en Supabase"
/journal --decision "Arquitectura: SSR para pages publicas, CSR para dashboard"
/journal --summary                # Genera resumen ejecutivo del proyecto
/journal --init                  # Crea JOURNAL.md desde cero (si no existe)
```

## Formato de JOURNAL.md

```markdown
# Project Journal

> Generado y mantenido por Sinapsis
> Proyecto: {nombre} | Inicio: {fecha_primer_entry}
> Ultima actualizacion: {fecha}

## Stack

| Tecnologia | Version | Detectada por |
|-----------|---------|---------------|
| Next.js | 16 | package.json |
| Supabase | - | @supabase/ssr |
| Prisma | 6.x | prisma/schema.prisma |

## Cronologia

### Semana 1 (2026-03-10 → 2026-03-16)

#### 2026-03-10
- **[STEP]** Inicializado proyecto con `create-next-app`
- **[STEP]** Configurado Prisma con PostgreSQL en Supabase
- **[DECISION]** Arquitectura: SSR para pages publicas, CSR para dashboard
  - *Razon*: SEO en pages publicas, interactividad en dashboard
  - *Alternativas descartadas*: Full SSR (demasiado lento para dashboard)

#### 2026-03-11
- **[STEP]** Implementado auth con Supabase (email + Google OAuth)
- **[GOTCHA]** Supabase auth necesita 3 gate points: middleware, layout, page
- **[DECISION]** Usar next-intl para i18n en vez de next-translate
  - *Razon*: Mejor soporte App Router, middleware built-in
  - *Alternativas descartadas*: next-translate (no soporta RSC bien)

#### 2026-03-12
- **[STEP]** Configurado Stripe billing con Customer portal
- **[STEP]** Tests E2E con Playwright para flujo de pago
- **[ERROR→FIX]** Stripe webhook fallaba en localhost → usar stripe-cli listen

### Semana 2 (2026-03-17 → 2026-03-23)
...

## Decisiones de arquitectura

| Fecha | Decision | Razon | Alternativas |
|-------|----------|-------|-------------|
| 2026-03-10 | SSR publico + CSR dashboard | SEO + interactividad | Full SSR, Full CSR |
| 2026-03-11 | next-intl para i18n | App Router support | next-translate |
| 2026-03-12 | Stripe (no Lemon Squeezy) | Soporte EU, Tax API | Lemon Squeezy, Paddle |

## Gotchas encontrados

| Fecha | Gotcha | Solucion |
|-------|--------|----------|
| 2026-03-11 | Supabase auth 3 gate points | middleware + layout + page check |
| 2026-03-12 | Stripe webhook localhost | stripe-cli listen |

## Resumen ejecutivo

{Generado con /journal --summary}
```

## Implementacion

### Paso 1: Detectar proyecto

1. Detectar proyecto actual (git remote hash)
2. Buscar `JOURNAL.md` en raiz del proyecto
3. Si no existe y usuario no dijo `--init`: preguntar si crear

### Paso 2: Segun modo

**Modo vista (`/journal` sin argumentos):**
- Leer y mostrar JOURNAL.md formateado
- Mostrar estadisticas: X entries, Y decisiones, Z gotchas

**Modo entrada manual (`/journal "texto"` o `--step` o `--decision`):**
1. Parsear tipo de entrada:
   - `--step "texto"` → `[STEP]`
   - `--decision "texto"` → `[DECISION]` (pedir razon y alternativas)
   - Sin flag: inferir tipo por contenido ("Decisión:" → DECISION, resto → STEP)
2. Determinar semana y fecha actual
3. Insertar entrada en la seccion cronologica correcta
4. Si es DECISION: tambien añadir a tabla "Decisiones de arquitectura"
5. Si es GOTCHA: tambien añadir a tabla "Gotchas encontrados"

**Modo init (`--init`):**
1. Crear JOURNAL.md con template base
2. Si `/dna` ya detecto stack: pre-poblar seccion Stack
3. Si existen gotchas del proyecto: pre-poblar seccion Gotchas
4. Primera entrada: `[STEP] Proyecto inicializado con Sinapsis`

**Modo resumen (`--summary`):**
1. Leer todo JOURNAL.md
2. Generar resumen ejecutivo de 5-10 lineas:
   - Que se ha construido
   - Decisiones clave tomadas
   - Gotchas encontrados
   - Estado actual del proyecto
3. Insertar/actualizar seccion "Resumen ejecutivo" al final

### Paso 3: Auto-captura via hooks

Cuando los hooks estan activos, observe.sh ya captura tool calls. El journal se puede enriquecer automaticamente:

**Entradas auto-detectables:**
- `Bash` con `npm init` / `create-next-app` / `npx prisma init` → `[STEP] Inicializado {herramienta}`
- `Bash` con `npm install {paquete}` → `[STEP] Añadida dependencia: {paquete}`
- `Bash` con `deploy` / `push` → `[STEP] Deploy realizado`
- Error seguido de fix (patron gotcha) → `[ERROR→FIX] {descripcion}`
- `/gotcha` ejecutado → auto-copiar al journal

**IMPORTANTE**: La auto-captura solo añade entradas si el usuario ejecuta `/journal --auto-sync`. No escribe automaticamente sin permiso (puede generar ruido).

### Paso 4: Formato de escritura

Al añadir una entrada:
1. Abrir JOURNAL.md
2. Encontrar la seccion de la semana actual (o crearla)
3. Encontrar la seccion del dia actual (o crearla)
4. Append la entrada con formato correcto
5. Si es DECISION: actualizar tabla de decisiones
6. Guardar

## Opciones

| Flag | Efecto |
|------|--------|
| `/journal` | Muestra el diario actual |
| `/journal "texto"` | Añade entrada (auto-detecta tipo) |
| `/journal --step "texto"` | Añade paso ejecutado |
| `/journal --decision "texto"` | Añade decision (pide razon + alternativas) |
| `/journal --init` | Crea JOURNAL.md desde cero |
| `/journal --summary` | Genera/actualiza resumen ejecutivo |
| `/journal --auto-sync` | Sincroniza con observaciones recientes |
| `/journal --export` | Exporta journal como documento standalone |

## Integracion con el ecosistema

- **/dna**: Al ejecutar `/dna --init`, se sugiere tambien ejecutar `/journal --init`
- **/gotcha**: Cada gotcha capturado se ofrece añadir al journal
- **/analyze**: Patrones detectados pueden generar entradas de journal
- **MEMORY.md**: El journal complementa a MEMORY.md — MEMORY es "que sabe Claude", journal es "que se ha hecho"
- **/audit**: El audit verifica que JOURNAL.md existe y esta actualizado

## Diferencia con MEMORY.md

| | MEMORY.md | JOURNAL.md |
|---|-----------|------------|
| **Proposito** | Contexto para Claude | Historial para humanos |
| **Contenido** | Stack, APIs, gotchas, decisiones | Cronologia completa paso a paso |
| **Audiencia** | Claude Code (maquina) | Desarrollador (humano) |
| **Formato** | Secciones tecnicas compactas | Cronologico, narrativo |
| **Actualizacion** | `/dna`, manual | `/journal`, auto-sync |
| **Replicabilidad** | Parcial (sabe QUE, no CUANDO) | Total (sabe QUE, CUANDO y POR QUE) |

## Edge cases

- **Proyecto sin JOURNAL.md**: Preguntar si crear. Si no, informar: "Usa `/journal --init` para empezar el diario del proyecto."
- **Proyecto sin git**: Crear journal en cwd con aviso: "Sin git remote, el journal se guarda en el directorio actual."
- **JOURNAL.md muy grande** (>500 lineas): Sugerir crear archivo por trimestre: `JOURNAL-2026-Q1.md`
- **--auto-sync sin hooks**: "No hay observaciones para sincronizar. Activa los hooks para captura automatica."

---

*Sinapsis — Project Journal | [SalgadoIA](https://salgadoia.com)*
