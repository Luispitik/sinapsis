---
name: dna
description: Detecta el stack del proyecto actual y sugiere heredar instincts de proyectos similares
command: true
---

# /dna — Project DNA: Deteccion de Stack y Herencia de Instincts

> *Analiza el ADN tecnologico del proyecto actual, encuentra proyectos hermanos, y hereda su conocimiento.*

## Flujo de ejecucion

Al ejecutar `/dna`, sigue estos pasos EN ORDEN:

---

### Paso 1: Detectar stack del proyecto actual

Escanea estos ficheros en el directorio de trabajo actual (`cwd`):

| Fichero | Que detectar |
|---------|-------------|
| `package.json` | dependencies y devDependencies: Next.js, React, Supabase, Stripe, Prisma, Tailwind, shadcn, Vercel AI SDK, next-intl, etc. Extraer versiones. |
| `requirements.txt` | Librerias Python: Django, FastAPI, Flask, SQLAlchemy, etc. |
| `pyproject.toml` | Proyecto Python moderno: Poetry, dependencias, build system |
| `Cargo.toml` | Proyecto Rust: dependencias, workspace |
| `go.mod` | Proyecto Go: modulos, dependencias |
| `docker-compose.yml` | Servicios de infraestructura: postgres, redis, nginx, etc. |
| `Dockerfile` | Imagen base, multi-stage builds |
| `.env.local` o `.env.example` | Variables de entorno que revelan servicios: SUPABASE_URL, STRIPE_SECRET_KEY, OPENAI_API_KEY, DATABASE_URL, etc. NO leer `.env` real por seguridad — solo `.env.example` o `.env.local` |
| `prisma/schema.prisma` | Modelos de base de datos, provider (postgresql, mysql, sqlite) |
| `tailwind.config.ts` o `tailwind.config.js` | Tailwind CSS presente |
| `next.config.js` o `next.config.ts` o `next.config.mjs` | Next.js config, plugins |
| `tsconfig.json` | TypeScript presente |
| `vercel.json` | Deployment en Vercel |
| `netlify.toml` | Deployment en Netlify |
| `.github/workflows/` | CI/CD con GitHub Actions |

Para cada fichero encontrado:
1. Leer su contenido
2. Extraer tecnologias con version cuando sea posible
3. Anotar la fuente de deteccion

Almacenar el resultado como una lista de objetos:
```
detected_stack = [
  { name: "Next.js", version: "16", source: "package.json" },
  { name: "Supabase", version: null, source: "package.json + .env" },
  { name: "Stripe", version: null, source: "@stripe/stripe-js" },
  { name: "Prisma", version: "6.x", source: "prisma/schema.prisma" },
  { name: "Tailwind CSS", version: "4", source: "tailwind.config.ts" },
  ...
]
```

---

### Paso 2: Leer proyectos pasados

Leer `~/.claude/homunculus/projects.json`. Este fichero contiene un array de proyectos registrados con su stack conocido. Formato esperado:

```json
[
  {
    "name": "DTScope",
    "hash": "abc123...",
    "stack": ["Next.js", "Supabase", "Stripe", "Prisma", "Tailwind CSS"],
    "path": "/ruta/al/proyecto",
    "last_session": "2026-01-15"
  },
  ...
]
```

Si el fichero no existe o esta vacio, informar al usuario y saltar al Paso 4.

---

### Paso 3: Calcular similitud entre proyectos

Para cada proyecto pasado, calcular:

```
similarity = (items en comun entre stack actual y stack del proyecto) / (total items unicos entre ambos) * 100
```

Ejemplo:
- Proyecto actual: [Next.js, Supabase, Stripe, Prisma, Tailwind]
- DTScope: [Next.js, Supabase, Stripe, Prisma]
- Items en comun: 4
- Items unicos totales: 5 (Next.js, Supabase, Stripe, Prisma, Tailwind)
- Similarity: 4/5 = 80%

Ordenar proyectos por similarity descendente. Mostrar los top 5 con >= 50% de match.

---

### Paso 4: Leer instincts globales

Leer TODOS los ficheros `.md` de `~/.claude/homunculus/instincts/personal/`.

Para cada instinct, extraer del frontmatter YAML:
- `id`
- `domain`
- `confidence`
- `trigger`

---

### Paso 5: Filtrar instincts por dominio

Usar esta tabla de mapping stack-a-dominio:

| Tecnologia detectada | Dominios relevantes |
|---------------------|-------------------|
| Next.js, React, Vue, Angular, Svelte | `saas-development`, `web-development` |
| Supabase | `saas-development`, `supabase-patterns` |
| Stripe, Lemon Squeezy | `stripe-billing`, `saas-development` |
| Docker, Kubernetes, Nginx | `infraestructura`, `deployment` |
| n8n | `automation`, `n8n-workflows` |
| Python, Django, FastAPI, Flask | `workflow-general`, `web-development` |
| Prisma, Drizzle, TypeORM | `saas-development`, `web-development` |
| Tailwind CSS, shadcn | `web-development`, `saas-development` |
| Vercel AI SDK, OpenAI, Anthropic | `saas-development`, `ai-integration` |
| GitHub Actions, CI/CD | `deployment`, `automation` |
| Rust | `systems-development`, `workflow-general` |
| Go | `systems-development`, `workflow-general` |
| PostgreSQL, MySQL, SQLite | `saas-development`, `web-development` |
| Redis, RabbitMQ, Kafka | `infraestructura`, `deployment` |
| next-intl, i18n | `saas-development`, `web-development` |
| Vercel, Netlify, Railway | `deployment` |

Recopilar todos los dominios relevantes del stack detectado. Luego filtrar instincts cuyo `domain` este en esa lista.

---

### Paso 6: Agrupar por confianza y mostrar resultado

Agrupar los instincts filtrados en 3 niveles:

| Nivel | Rango | Etiqueta |
|-------|-------|----------|
| Alta confianza | >= 0.90 | `ALTA CONFIANZA` |
| Confianza fuerte | 0.80 - 0.89 | `CONFIANZA FUERTE` |
| Confianza moderada | 0.60 - 0.79 | `CONFIANZA MODERADA` |

NO mostrar instincts con confidence < 0.60 (no son lo suficientemente fiables para heredar).

Formato de salida:

```
══════════════════════════════════════════════════
  PROJECT DNA — Sinapsis
  Proyecto: <nombre del directorio actual>
══════════════════════════════════════════════════

Stack detectado:
  ✓ Next.js 16 (package.json)
  ✓ Supabase (package.json + .env)
  ✓ Stripe (@stripe/stripe-js)
  ✓ Prisma (prisma/schema.prisma)
  ✓ Tailwind CSS (tailwind.config.ts)

Proyectos similares:
  1. DTScope (85% match) — Next.js, Supabase, Stripe, Prisma
  2. ImpulsaFlow (80% match) — Next.js, Prisma, Supabase, Stripe

Instincts heredables (<total>):
  ■ ALTA CONFIANZA (≥ 0.90)
  ● locale-prefix-always-nextintl      [saas-development]   0.95
  ● prisma-json-parse-stringify        [saas-development]   0.90
  ● stripe-customer-id-en-user         [stripe-billing]     0.90
  ● vercel-ai-sdk-await-streamtext     [saas-development]   0.90

  ■ CONFIANZA FUERTE (0.80-0.89)
  ● supabase-auth-3-gate-points        [saas-development]   0.85
  ● next-cache-corruption-windows      [saas-development]   0.85
  ... +N más

  ■ CONFIANZA MODERADA (0.60-0.79)
  ● ejemplo-instinct                   [web-development]    0.70
  ... +N más

Acciones:
  1. Heredar todos los instincts → copia a project scope
  2. Generar MEMORY.md inicial → basado en stack detectado
  3. Ambas
  4. No hacer nada

══════════════════════════════════════════════════
```

---

### Paso 7: Ejecutar la accion elegida

#### Accion 1: Heredar instincts

Para cada instinct filtrado:
1. Copiar el fichero `.md` del instinct desde `~/.claude/homunculus/instincts/personal/` a `.claude/instincts/inherited/` en el proyecto actual
2. Modificar el frontmatter: cambiar `scope: global` a `scope: project` y anadir `inherited_from: global`
3. Confirmar cuantos instincts se copiaron

#### Accion 2: Generar MEMORY.md

Generar un fichero `MEMORY.md` en la raiz del proyecto con el siguiente template:

```markdown
# MEMORY.md — <nombre-proyecto>

> Auto-generado por Sinapsis /dna el <fecha-actual>
> Stack detectado: <lista de tecnologias>

## Stack

| Tecnologia | Version | Fuente |
|-----------|---------|--------|
| Next.js | 16 | package.json |
| Supabase | - | package.json + .env |
| ... | ... | ... |

## Ficheros clave

> Completar manualmente conforme avanza el proyecto.

| Fichero | Proposito |
|---------|-----------|
| `src/app/layout.tsx` | Layout principal |
| `src/lib/supabase.ts` | Cliente Supabase |
| `prisma/schema.prisma` | Schema de base de datos |
| ... | ... |

## Gotchas conocidos

> Pre-poblado desde instincts heredados. Cada gotcha viene de un instinct con alta confianza.

<!-- Los gotchas se generan automaticamente desde los instincts heredados -->
<!-- Formato: - **[instinct-id]**: descripcion del trigger -->

- **[locale-prefix-always-nextintl]**: En next-intl, siempre incluir locale prefix en rutas. Sin el, el middleware redirige y rompe navegacion.
- **[prisma-json-parse-stringify]**: Al guardar JSON en Prisma, siempre usar JSON.parse(JSON.stringify(data)) para evitar errores de serializacion.
- ...

## APIs y Servicios

> Auto-detectado desde .env.example / .env.local. NO incluir valores reales, solo nombres de variables.

| Servicio | Variable de entorno | Configurado |
|----------|-------------------|-------------|
| Supabase | `NEXT_PUBLIC_SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` | ⬜ |
| Stripe | `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` | ⬜ |
| OpenAI | `OPENAI_API_KEY` | ⬜ |
| ... | ... | ... |

## Deployment

> Completar cuando se configure deployment.

| Campo | Valor |
|-------|-------|
| Plataforma | Vercel / Railway / Docker / ... |
| Branch de produccion | `main` |
| URL de produccion | |
| URL de staging | |
| CI/CD | GitHub Actions / ... |

## Decisiones de arquitectura

> Documentar decisiones importantes aqui.

| Fecha | Decision | Razon |
|-------|----------|-------|
| | | |

## Sistema de memoria de 3 capas

Este proyecto usa el sistema Sinapsis de memoria:

| Capa | Fichero | Proposito |
|------|---------|-----------|
| **Skill** | `SKILL.md` | Arquitectura global de Sinapsis, reglas, comandos |
| **Memory** | `MEMORY.md` (este fichero) | Decisiones de ESTE proyecto, contexto actual, stack |
| **Env** | `.env.local` | Variables sensibles, paths locales (NUNCA commitear) |

**Reglas:**
1. SKILL.md es read-only para el proyecto — define como funciona Sinapsis
2. MEMORY.md es el cerebro del proyecto — actualizarlo conforme se toman decisiones
3. .env.local NUNCA se lee automaticamente por seguridad — solo .env.example
4. Antes de cada sesion, Claude debe leer MEMORY.md para tener contexto
5. Al final de cada sesion significativa, actualizar MEMORY.md con nuevas decisiones
```

#### Accion 3: Ambas

Ejecutar Accion 1 y Accion 2 en secuencia.

#### Accion 4: No hacer nada

Mostrar "OK, no se ha modificado nada. Puedes ejecutar /dna de nuevo cuando quieras."

---

## Casos edge

1. **No hay package.json ni ningun fichero de stack**: Informar "No se detecto ningun stack. Asegurate de estar en el directorio raiz del proyecto."
2. **No hay projects.json**: Informar "No hay proyectos registrados aun. Ejecuta /projects para registrar proyectos." y saltar a deteccion de instincts.
3. **No hay instincts globales**: Informar "No hay instincts globales. Usa Sinapsis en algunos proyectos primero para generar instincts."
4. **Proyecto ya tiene instincts heredados**: Preguntar si quiere sobrescribir o hacer merge (mantener el de mayor confidence).
5. **Stack no mapea a ningun dominio conocido**: Mostrar todos los instincts con confidence >= 0.90 como "sugerencias generales".

## Seguridad

- NUNCA leer `.env` (el real). Solo `.env.example` o `.env.local`
- NUNCA incluir valores de variables de entorno en MEMORY.md — solo nombres de variables
- Los instincts heredados se copian, no se enlazan — cambios en global no afectan al proyecto
