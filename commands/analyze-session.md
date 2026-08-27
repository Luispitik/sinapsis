---
name: analyze-session
description: >
  Analiza la sesion en profundidad: revisa observaciones, detecta patrones semanticos
  (errores, correcciones, workflows, preferencias), y propone instincts accionables.
  Mucho mas potente que revisar proposals crudas del regex.
---

# /analyze-session -- Analisis Semantico de Sesion

> Analiza observaciones reales de la sesion, detecta patrones semanticos,
> y propone instincts de alta calidad. Usa la inteligencia de Claude para
> entender QUE paso, no solo que un error ocurrio.

---

## Trigger

Run with `/analyze-session`, "analyze session", or "review proposals".

---

## Process

### Step 1: Gather ALL Session Data

Read these three files in parallel:

1. **`~/.claude/skills/_instinct-proposals.json`** -- Raw proposals from the deterministic session-learner regex.
   Extract: pending proposals, session date, evidence strings.

2. **`~/.claude/homunculus/projects/`** -- Find the most recently modified project directory.
   Read the last 500 lines of its `observations.jsonl`.
   Each line is a JSON object with: `timestamp`, `event` (tool_start|tool_complete), `tool`, `session`, `project_id`, `project_name`, `input`, `output`.

3. **`~/.claude/skills/_instincts-index.json`** -- Existing knowledge base.
   Extract: all instinct IDs, trigger_patterns, domains, levels. Used for dedup and gap detection.

If `observations.jsonl` does not exist or is empty, fall back to **Quick Mode** (Step 1B).

### Step 1B: Quick Mode (Fallback -- No Observations)

If no observations are available, show:

```
ANALISIS DE SESION -- Modo rapido (sin observaciones)

  No se encontraron observaciones recientes en ~/.claude/homunculus/projects/.
  Usando solo las proposals del session-learner (regex deterministico).

  Nota: Para analisis semantico completo, necesitas sesiones con
  el observer activo (homunculus).
```

Then skip directly to Step 3B (legacy proposal review from the old analyze-session flow):
- Show each pending proposal with `[C] Confirm  [X] Discard`
- For confirmed: ask user for inject text and trigger_pattern
- Add to `_instincts-index.json` with level "draft"
- Summary and exit.

---

### Step 2: Semantic Analysis (Core -- This Is the Key Improvement)

Analyze the observations looking for **5 types of patterns**. For each type, scan the observations systematically:

#### 2.1 Error Gotchas

Look for pairs: `tool_start` followed by `tool_complete` where output contains error indicators (`error`, `Error`, `ENOENT`, `EPERM`, `command not found`, `No such file`, `Permission denied`, `SyntaxError`, `TypeError`, non-zero exit codes), followed by a SECOND call to the same or related tool that succeeds.

**Key**: Extract WHAT the error was and HOW it was fixed. Not just "Bash error" but the specific gotcha:
- "find -printf doesn't work on macOS, use stat instead"
- "Edit fails when old_string has trailing whitespace that doesn't match"
- "npm install needs --legacy-peer-deps for React 19 compatibility"

#### 2.2 User Corrections

Look for the same file being edited multiple times (multiple `Edit` or `Write` calls to the same `file_path` within a short window). This indicates Claude got it wrong and the user corrected.

**Key**: Identify WHAT was being corrected:
- Style: formatting, naming conventions, spacing
- Logic: wrong conditional, missing edge case
- Architecture: wrong file location, wrong pattern
- Content: wrong text, wrong values, wrong translations

#### 2.3 Workflow Patterns

Look for repeated tool sequences (3+ tools in the same order, appearing 2+ times). Common patterns:
- `Read -> Edit -> Bash(test)` = TDD cycle
- `Grep -> Read -> Edit` = search-then-fix pattern
- `Bash(git) -> Bash(git) -> Bash(git)` = git workflow
- `Read -> Read -> Read -> Write` = research-then-create

**Key**: Only flag sequences that repeat. A one-off sequence is not a pattern.

#### 2.4 Preference Signals

Look for consistent choices across the session:
- Always using `const` over `let`
- Always writing tests before implementation (TDD)
- Always reading a file before editing (defensive coding)
- Specific tools preferred (e.g., `Grep` over `Bash(grep)`)
- Language patterns in user messages (Spanish vs English in different contexts)

#### 2.5 Missing Knowledge

Look for places where:
- Claude had to make multiple attempts at the same task (3+ retries)
- The user provided information Claude should have known (project structure, API patterns, naming conventions)
- A tool was used with wrong arguments first, then corrected

---

### Step 3: Present Enriched Proposals

For each detected pattern (from semantic analysis + raw proposals), present:

```
============================================
ANALISIS SEMANTICO DE SESION
============================================

  Proyecto:      {project_name}
  Observaciones: {observation_count} eventos analizados
  Proposals raw: {raw_proposal_count} del session-learner
  Fecha:         {date}

--------------------------------------------
PATRON 1 de N
--------------------------------------------

  PATTERN: [nombre descriptivo y especifico]
  Tipo:    error-gotcha | user-correction | workflow | preference | knowledge-gap
  Fuente:  semantic-analysis | session-learner | combined

  Evidencia:
    - [timestamp] Tool X fallo con "error message..."
    - [timestamp] Reintento con Tool X usando argumento diferente -> exito
    - (o: "Archivo Y editado 4 veces en 3 minutos")

  Instinct propuesto:
    inject: "[lo que Claude debe recordar -- max 300 chars, especifico y accionable]"
    trigger_pattern: "[regex que dispara en contexto relevante — sintaxis JavaScript]"
    domain: [general|git|security|frontend|database|auth|deploy|operations|tooling|code-quality|testing|...]

  Confianza: HIGH (3+ ocurrencias) | MEDIUM (2 ocurrencias) | LOW (1 ocurrencia clara)

  [A] Aceptar    [E] Editar    [X] Descartar

--------------------------------------------
PATRON 2 de N
--------------------------------------------
  ... (repeat for each pattern)
```

**Ordering**: Show HIGH confidence patterns first, then MEDIUM, then LOW.

**Dedup**: Before presenting, check each proposed instinct against `_instincts-index.json`:
- If an existing instinct already covers this pattern, show: `(Ya cubierto por instinct "{id}" -- se omite)`
- If an existing instinct partially covers it, suggest: `(Ampliar trigger de instinct existente "{id}"?)`

---

### Step 4: Process Accepted Proposals

For each pattern the user accepts with `[A]`:

1. **Generate instinct ID**: kebab-case from the pattern name (e.g., `find-printf-macos-compat`)
2. **Set level**:
   - HIGH confidence -> `"confirmed"`
   - MEDIUM or LOW confidence -> `"draft"`
3. **Add to `_instincts-index.json`**:
   ```json
   {
     "id": "{generated-id}",
     "trigger_pattern": "{proposed or user-edited regex}",
     "inject": "{proposed or user-edited text, max 300 chars}",
     "level": "confirmed|draft",
     "scope": "project",
     "domain": "{selected domain}",
     "origin": "semantic-analysis",
     "added": "{today YYYY-MM-DD}",
     "occurrences": 0,
     "source_evidence": "{brief evidence summary}"
   }
   ```
4. **Check for trigger_pattern conflicts**: If the regex overlaps with an existing instinct's trigger, warn the user.
5. **No inline flag groups**: los activadores compilan con `new RegExp(pattern, "i")` en Node,
   y **JavaScript no admite `(?i)`** (ni `(?m)`, `(?s)`, `(?x)`): `new RegExp("(?i)foo")` lanza
   *Invalid group*. Escribe el patrón **sin** el prefijo — la insensibilidad a mayúsculas ya
   viene puesta por la flag `"i"`. Es el error más fácil de cometer aquí, porque `(?i)` es la
   grafía natural en Python y en grep, y el más caro: hasta v4.9.1 el `catch` del activador
   descartaba el instinct **en silencio** y se quedaba en el índice para siempre sin dispararse
   ni una vez. Desde v4.9.1 los activadores lo toleran y lo registran, pero un patrón limpio se
   lee mejor y no depende del saneado.

For each pattern the user edits with `[E]`:
- Let the user modify: inject text, trigger_pattern, domain, or confidence level
- Then proceed as `[A]` with the edited values

For each pattern the user discards with `[X]`:
- If it came from `_instinct-proposals.json`, mark as `status: "discarded"`
- If it came from semantic analysis only, just skip it (no persistence needed)

---

### Step 5: Summary with Actionable Stats

```
============================================
ANALISIS COMPLETO
============================================

  Patrones detectados:    {total}
    - Error gotchas:      {count}
    - User corrections:   {count}
    - Workflow patterns:   {count}
    - Preference signals: {count}
    - Knowledge gaps:     {count}

  Resultado:
    Aceptados:    {accepted} -> anadidos a _instincts-index.json
      - confirmed: {high_confidence_count}
      - draft:     {low_confidence_count}
    Editados:     {edited}
    Descartados:  {discarded}
    Ya cubiertos: {dedup_count} (omitidos por instincts existentes)

  Instincts activos: {new_total} (era {old_total})
  Dominios cubiertos: {domain_list}

  Los instincts nuevos se inyectaran automaticamente cuando su
  trigger_pattern coincida con el contexto de herramientas futuras.
  Los de nivel "draft" se promoveran a "confirmed" tras 5+ activaciones.

  Tip: Usa /instinct-status para ver todos los instincts activos.
       Usa /promote para subir instincts de proyecto a globales.
```

---

## Edge Cases

- **No proposals file AND no observations**: Show "No hay datos de sesion. Ejecuta algunas sesiones con el observer activo y el session-learner primero."
- **All proposals already processed + no new patterns in observations**: Show "Todo revisado. No se detectaron patrones nuevos en las observaciones recientes."
- **Observations exist but are very short (<20 events)**: Show note: "Sesion corta ({n} eventos). El analisis semantico funciona mejor con sesiones mas largas (100+ eventos)."
- **Duplicate domain warning**: "Ya tienes un instinct confirmed en dominio '{domain}'. El instinct-activator usa dedup por dominio (uno por dominio, max 3). El de mayor nivel tiene prioridad."
- **Too many patterns detected (>15)**: Show only top 10 by confidence, then: "Se detectaron {n} patrones. Mostrando top 10 por confianza. Usa /analyze-session --all para verlos todos."
