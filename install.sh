#!/bin/bash
# ═══════════════════════════════════════════════════
#  Sinapsis — Instalador
#  Sistema de aprendizaje continuo para Claude Code
# ═══════════════════════════════════════════════════

set -e

# Colores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOMUNCULUS_DIR="${HOME}/.claude/homunculus"
SKILLS_DIR="${HOME}/.claude/skills/sinapsis"
COMMANDS_DIR="${HOME}/.claude/commands"
SETTINGS_FILE="${HOME}/.claude/settings.json"

echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Sinapsis — Instalador v1.1                      ${NC}"
echo -e "${CYAN}  Cada sesion crea una conexion.                   ${NC}"
echo -e "${CYAN}  Sinapsis las convierte en instinto.              ${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo ""

# ── 1. Crear estructura homunculus ──
echo -e "${GREEN}[1/6]${NC} Creando estructura ~/.claude/homunculus/ ..."
mkdir -p "${HOMUNCULUS_DIR}/instincts/personal"
mkdir -p "${HOMUNCULUS_DIR}/instincts/inherited"
mkdir -p "${HOMUNCULUS_DIR}/evolved/agents"
mkdir -p "${HOMUNCULUS_DIR}/evolved/skills"
mkdir -p "${HOMUNCULUS_DIR}/evolved/commands"
mkdir -p "${HOMUNCULUS_DIR}/projects"
mkdir -p "${HOMUNCULUS_DIR}/exports"
chmod 700 "${HOMUNCULUS_DIR}" 2>/dev/null || true
echo "  Estructura creada (permisos restrictivos aplicados)."

# ── 2. Copiar identity.json y config.json (solo si no existen) ──
echo -e "${GREEN}[2/6]${NC} Copiando configuracion ..."

if [ ! -f "${HOMUNCULUS_DIR}/identity.json" ]; then
  cp "${SCRIPT_DIR}/identity.json" "${HOMUNCULUS_DIR}/identity.json"
  echo "  identity.json copiado (edita los placeholders)."
else
  echo -e "  ${YELLOW}identity.json ya existe, no se sobreescribe.${NC}"
fi

if [ ! -f "${HOMUNCULUS_DIR}/config.json" ]; then
  cp "${SCRIPT_DIR}/config.json" "${HOMUNCULUS_DIR}/config.json"
  echo "  config.json copiado."
else
  echo -e "  ${YELLOW}config.json ya existe, no se sobreescribe.${NC}"
fi

# ── 3. Copiar seed instincts ──
echo -e "${GREEN}[3/6]${NC} Instalando instincts semilla ..."

if [ ! -f "${HOMUNCULUS_DIR}/instincts/personal/sinapsis-seed.yaml" ]; then
  cp "${SCRIPT_DIR}/instincts/personal/sinapsis-seed.yaml" "${HOMUNCULUS_DIR}/instincts/personal/"
  echo "  Seed instinct instalado."
else
  echo -e "  ${YELLOW}Seed instinct ya existe, no se sobreescribe.${NC}"
fi

# ── 4. Instalar skill (siempre actualiza — es el core del sistema) ──
echo -e "${GREEN}[4/6]${NC} Instalando skill en ~/.claude/skills/sinapsis/ ..."
mkdir -p "${SKILLS_DIR}/hooks" "${SKILLS_DIR}/agents"
cp "${SCRIPT_DIR}/SKILL.md" "${SKILLS_DIR}/"
cp "${SCRIPT_DIR}/hooks/observe.sh" "${SKILLS_DIR}/hooks/"
chmod +x "${SKILLS_DIR}/hooks/observe.sh"
cp "${SCRIPT_DIR}/agents/sinapsis-observer.md" "${SKILLS_DIR}/agents/"
echo "  Skill instalada (SKILL.md, hooks y agents se actualizan siempre)."

# ── 5. Instalar commands ──
echo -e "${GREEN}[5/6]${NC} Instalando commands en ~/.claude/commands/ ..."
mkdir -p "${COMMANDS_DIR}"
CMD_COUNT=$(ls -1 "${SCRIPT_DIR}/commands/"*.md 2>/dev/null | wc -l | tr -d ' ')
cp "${SCRIPT_DIR}/commands/"*.md "${COMMANDS_DIR}/"
echo "  ${CMD_COUNT} commands instalados."

# ── 6. Verificar hooks en settings.json ──
echo -e "${GREEN}[6/6]${NC} Verificando hooks ..."

HOOKS_OK=false
if [ -f "$SETTINGS_FILE" ]; then
  if command -v python3 >/dev/null 2>&1 || command -v python >/dev/null 2>&1; then
    PYTHON_CMD="python3"
    command -v python3 >/dev/null 2>&1 || PYTHON_CMD="python"
    HOOKS_OK=$("$PYTHON_CMD" -c "
import json
try:
    with open('$SETTINGS_FILE') as f:
        s = json.load(f)
    hooks = s.get('hooks', {})
    pre = hooks.get('PreToolUse', [])
    post = hooks.get('PostToolUse', [])
    has_pre = any('sinapsis' in str(h) or 'observe.sh' in str(h) for h in pre)
    has_post = any('sinapsis' in str(h) or 'observe.sh' in str(h) for h in post)
    print('true' if has_pre and has_post else 'false')
except:
    print('false')
" 2>/dev/null || echo "false")
  fi
fi

if [ "$HOOKS_OK" = "true" ]; then
  echo "  Hooks detectados en settings.json."
else
  echo ""
  echo -e "  ${YELLOW}NOTA: Hooks no detectados en settings.json${NC}"
  echo "  Para activar observacion automatica, anade a ~/.claude/settings.json:"
  echo ""
  echo '  {'
  echo '    "hooks": {'
  echo '      "PreToolUse": [{'
  echo '        "matcher": "*",'
  echo '        "hooks": [{'
  echo '          "type": "command",'
  echo '          "command": "bash ~/.claude/skills/sinapsis/hooks/observe.sh pre",'
  echo '          "async": true,'
  echo '          "timeout": 10'
  echo '        }]'
  echo '      }],'
  echo '      "PostToolUse": [{'
  echo '        "matcher": "*",'
  echo '        "hooks": [{'
  echo '          "type": "command",'
  echo '          "command": "bash ~/.claude/skills/sinapsis/hooks/observe.sh post",'
  echo '          "async": true,'
  echo '          "timeout": 10'
  echo '        }]'
  echo '      }]'
  echo '    }'
  echo '  }'
  echo ""
  echo "  (Los hooks son opcionales — Sinapsis funciona sin ellos,"
  echo "   pero no capturara observaciones automaticamente.)"
fi

# ── Resumen ──
echo ""
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo -e "${CYAN}  Sinapsis instalado correctamente                ${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo ""
echo "  Estructura:  ~/.claude/homunculus/"
echo "  Skill:       ~/.claude/skills/sinapsis/"
echo "  Commands:    ~/.claude/commands/"
echo "  Config:      ~/.claude/homunculus/config.json"
echo "  Identidad:   ~/.claude/homunculus/identity.json"
echo ""
echo "  Comandos disponibles (${CMD_COUNT}):"
echo "    /instinct-status    Ver instincts aprendidos"
echo "    /evolve             Analizar y clusterizar instincts"
echo "    /promote            Promover instincts a global"
echo "    /projects           Ver proyectos registrados"
echo "    /instinct-export    Exportar instincts"
echo "    /instinct-import    Importar instincts"
echo "    /instinct-cloud     Generar skill para claude.ai"
echo "    /dna                Detectar stack y heredar instincts"
echo "    /analyze            Detectar patrones y crear instincts"
echo "    /gotcha             Capturar error→fix como instinct"
echo "    /journal            Diario de proyecto (pasos + decisiones)"
echo "    /audit              Auditar skills e instincts"
echo "    /watchdog           Health monitor del sistema"
echo "    /auto-schedule      Automatizar tareas repetidas"
echo ""
echo "  Siguiente paso: edita identity.json con tus datos."
echo ""
echo -e "${CYAN}  Builded by SalgadoIA${NC}"
echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
echo ""
