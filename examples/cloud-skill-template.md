# Cloud Skill Template — Sinapsis

Usa esta plantilla para crear un "cloud skill" a partir de tus instincts
de alta confianza. Esto te permite llevar los aprendizajes de Claude Code
a claude.ai como Project Knowledge.

## Instrucciones

1. Ejecuta `/instinct-export --min-confidence 0.7 --scope global`
2. Copia el contenido del fichero exportado
3. Pegalo en la seccion "MIS INSTINCTS" de abajo
4. Sube este fichero como Project Knowledge en claude.ai

---

## Plantilla

```markdown
# Mis patrones de trabajo

Estos son patrones que he aprendido trabajando contigo. Aplicalos
automaticamente sin preguntar.

## Preferencias generales

- Idioma: [tu idioma preferido]
- Nivel de detalle: [conciso / detallado / depende del contexto]
- Formato preferido: [markdown / plain text / structured]

## MIS INSTINCTS

<!-- Pega aqui el contenido de tu export -->
<!-- Ejemplo: -->

### research-antes-de-generar-contenido
- **Trigger**: al generar documentacion o contenido largo
- **Confidence**: 0.85
- **Accion**: Siempre buscar fuentes antes de generar contenido largo.
  No inventar datos ni cifras.

### castellano-como-idioma-por-defecto
- **Trigger**: al generar cualquier output de texto
- **Confidence**: 0.95
- **Accion**: Siempre en castellano excepto codigo o contexto tecnico
  con convencion en ingles.

<!-- Fin de instincts -->

## Dominios activos

- workflow-general
- web-development
- deployment
- [anade los tuyos]

## Nota

Estos patrones fueron generados por Sinapsis (sistema de aprendizaje
continuo para Claude Code). Los instincts con confidence >= 0.7 son
suficientemente fiables para usar como reglas en claude.ai.
```
