---
name: watchdog
description: Health watchdog que monitoriza el estado del sistema Sinapsis y los deploys
trigger: /watchdog
---

# /watchdog — Health Watchdog

Monitoriza la salud del ecosistema Sinapsis y detecta problemas de deploy/build/runtime para actuar proactivamente.

## Modos de uso

### 1. Check manual: `/watchdog`

Ejecuta un health check completo y muestra estado:

```
╔══════════════════════════════════════════════════════════╗
║  WATCHDOG — Sinapsis Health Monitor                     ║
╠══════════════════════════════════════════════════════════╣
║                                                         ║
║  🟢 SISTEMA SINAPSIS                                    ║
║  ───────────────────────────────                        ║
║  Hooks activos:          ✓ PreToolUse + PostToolUse     ║
║  Ultima observacion:     hace 2 min                     ║
║  observations.jsonl:     847 lineas (1.2 MB)            ║
║  Instincts activos:      42 (28 global + 14 proyecto)   ║
║  Instincts decaying:     3 (sin obs > 2 semanas)        ║
║  Config valido:          ✓                              ║
║                                                         ║
║  🟡 PROYECTO ACTUAL: mi-saas                            ║
║  ───────────────────────────────                        ║
║  Ultimo build:           ✓ exitoso (hace 45 min)        ║
║  Ultimo deploy:          ⚠ warning (hace 2h)            ║
║    → 3 warnings de depreciacion en build log            ║
║  Health endpoint:        ✓ 200 OK (150ms)               ║
║  Errores recientes:      2 en ultimas 24h               ║
║    → NEXT_REDIRECT en /api/auth (conocido, gotcha)      ║
║    → TypeError en /dashboard (nuevo)                    ║
║                                                         ║
║  📋 ACCIONES SUGERIDAS                                  ║
║  ───────────────────────────────                        ║
║  1. Investigar TypeError en /dashboard                  ║
║  2. Considerar archivar 3 instincts en decay            ║
║  3. Ejecutar /audit para check completo                 ║
║                                                         ║
╚══════════════════════════════════════════════════════════╝
```

### 2. Deteccion automatica via hooks

El hook observe.sh detecta patrones de fallo en las observaciones:

**Patrones monitorizados:**

| Patron | Deteccion | Accion |
|--------|-----------|--------|
| Build fail repetido | 2+ `Bash` con `npm run build` + exit code != 0 en misma sesion | Sugerir `/gotcha` |
| Deploy fail | `Bash` con `deploy`/`push` + error en output | Alertar + sugerir rollback |
| Test suite rojo | `Bash` con `test`/`jest`/`vitest` + failures > 0 | Listar tests fallidos |
| Error repetido | Mismo error string en 3+ observaciones | Auto-crear gotcha candidato |
| Observaciones paradas | >24h sin nuevas observaciones en proyecto activo | Verificar hooks |
| Disk space | observations.jsonl > 10MB (umbral de archivo automatico) | Verificar que auto-archive funciono |
| Instinct decay masivo | >10 instincts con confidence < 0.3 | Sugerir `/audit --fix` |

### 3. Health checks de proyecto

`/watchdog` intenta detectar y verificar:

**A. Build status:**
- Buscar en observaciones recientes: `npm run build`, `next build`, `cargo build`, etc.
- Ultimo exit code: 0 = ✓, != 0 = ✗
- Si no hay builds recientes → "Sin datos de build"

**B. Deploy status:**
- Buscar en observaciones: `vercel deploy`, `git push`, `docker deploy`, etc.
- Verificar si hay errores post-deploy en observaciones posteriores
- Si no hay deploys recientes → "Sin datos de deploy"

**C. Health endpoint (si disponible):**
- Buscar URL en `.env.example` o `MEMORY.md` (NUNCA leer `.env` o `.env.local` directamente — pueden contener secrets)
- Si existe `NEXT_PUBLIC_URL`, `APP_URL`, o similar en `.env.example`:
  - Intentar `curl -s -o /dev/null -w "%{http_code}" <url>/api/health`
  - 200 = ✓, 4xx/5xx = ✗, timeout = ⚠
- Si no hay URL configurada → "No configurado"

**D. Errores recientes:**
- Buscar en observations.jsonl ultimas 24h:
  - Outputs con "error", "Error", "ERROR", "failed", "FAILED"
  - Filtrar falsos positivos (strings que contienen "error" en contexto normal)
  - Cruzar con gotchas existentes: si el error ya tiene gotcha → marcar como "conocido"
  - Si el error es nuevo → marcar como "NUEVO — investigar"

### 4. Opciones

| Flag | Efecto |
|------|--------|
| `/watchdog` | Health check completo |
| `/watchdog --system` | Solo estado del sistema Sinapsis |
| `/watchdog --project` | Solo estado del proyecto actual |
| `/watchdog --errors` | Solo errores recientes con analisis |
| `/watchdog --quiet` | Solo muestra problemas (omite lo que esta OK) |

### 5. Integracion con el ecosistema

**Con /gotcha:**
- Cuando watchdog detecta un error nuevo → sugiere ejecutar `/gotcha` para capturarlo
- Cuando un error coincide con un gotcha existente → muestra la solucion conocida

**Con /audit:**
- `/watchdog --system` ejecuta un subset del health check de `/audit --health`
- Son complementarios: watchdog es rapido y frecuente, audit es profundo y ocasional

**Con observe.sh:**
- Watchdog lee las observaciones que captura el hook
- Sin hooks activos, watchdog solo puede hacer checks de sistema (no de proyecto)

### 6. Alertas proactivas

Cuando los hooks estan activos, observe.sh puede detectar ciertos patrones en tiempo real y emitir avisos en stderr (que Claude Code muestra como warnings):

```bash
# En observe.sh, seccion de watchdog alerts:
# Si el output contiene patron de error critico:
if echo "$OUTPUT" | grep -qiE "(FATAL|PANIC|OOM|segfault|killed|ENOSPC|out of memory)"; then
  echo "[sinapsis-watchdog] ⚠ Error critico detectado: revisar output" >&2
fi
```

Estos avisos son informativos — no bloquean la ejecucion.

### 7. Log de watchdog

Cada ejecucion de `/watchdog` escribe un resumen en:
```
~/.claude/homunculus/watchdog.log
```

Formato: una linea JSON por check:
```json
{"timestamp":"2024-01-15T10:30:00Z","project":"mi-saas","status":"warning","issues":2,"details":"deploy_warning,new_error"}
```

Esto permite ver tendencias: ¿el proyecto esta mejorando o empeorando?

---

*Sinapsis — Health Watchdog | [SalgadoIA](https://salgadoia.com)*
