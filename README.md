# ravn-trio

Trío PM/WK/RV local en tabs de [herdr](https://herdr.dev): repo de código del dúo `ravn-trio` / `ravn-trio-arch` (Arquetipo A). Spec: robert-flo/PJ-NIRI-rf-omarchy-workstation#58.

## Instalación

```bash
make check                      # shellcheck + tests
sudo make install               # /usr/bin/pj-trio y /usr/share/ravn/trio/
make DESTDIR=pkg install        # para empaquetar
```

Para usarlo desde el checkout: `./pj-trio …` (busca los helpers junto a sí mismo).

Requiere `herdr` ≥ 0.9.5, `jq`, `git` y `notify-send` (libnotify).

## Estructura (lenguaje de diseño de git-setup)

```text
├── pj-trio                  # Launcher: despacha por runtime/commands.tsv; sin subcomando → start
├── trio-status              # Alias de `pj-trio status` (lo invoca el PM)
├── trio-pm-prompt.md        # Plantilla del arranque del PM
├── trio.conf.example        # Defaults: kinds por rol, identidad git, integración herdr
└── runtime/
    ├── commands.tsv         # Catálogo: start, kickoff, status, help
    ├── completion/pj-trio.bash
    ├── helper/set_variable.sh
    ├── lib/                 # presentation, command_catalog, command_interface, dispatch,
    │                        # lifecycle (idénticos a git-setup) + trio_project/config/herdr
    └── scripts/             # start, kickoff, status, help
```

Instalado: todo bajo `/usr/share/ravn/trio/` y `/usr/bin/pj-trio` → symlink al launcher.

## Configuración

`trio.conf` se lee por capas y la última gana: defaults (`/usr/share/ravn/trio/trio.conf`, si no `trio.conf.example`) → override de la máquina en `/zt/ravn/trio/trio.conf` (`TRIO_OVERRIDE_DIR`) → repo (`<proyecto>/.trio/trio.conf`). `PJ_TRIO_CONFIG` reemplaza todas las capas. Nada en `$HOME`.

## Plugin de herdr

`herdr-plugin.toml` declara la acción **New trio** (`ravn.trio.new-trio`) y un link handler para URLs de issues de GitHub. La acción toma el ticket de la URL clicada o del número seleccionado y el proyecto del worktree o cwd del panel, y corre `pj-trio`. Para enlazarlo: `herdr plugin link /usr/share/ravn/trio` (o el checkout).

## `pj-trio`

`pj-trio` es un inicializador idempotente para herdr que prepara un workspace con tres tabs dedicados e independientes a pantalla completa para los roles del trío: **PM**, **WK** y **RV**.

### Uso

```bash
pj-trio [--dry-run] [--no-kickoff] [--print-kickoff] <proyecto> <ticket> [--repo <miembro>]
```

- `<proyecto>`: Ruta al checkout git del proyecto meta (`pj-*`) o nombre del directorio. Si pasás únicamente el nombre, se resuelve contra la variable de entorno `$PJ_TRIO_ROOT`, o por defecto contra el directorio padre de `$PWD` o `/z-drive/tries`.
- `<ticket>`: Identificador del issue o ticket a trabajar (por ejemplo `18` o `999`).
- `--repo <miembro>`: Repositorio miembro opcional, donde vive el issue. Acepta ruta, nombre del directorio, nombre del repo en GitHub (`pj-domina-rf-git-setup` o `robert-flo/pj-domina-rf-git-setup`) o nombre corto único (`rf-git-setup`). Se busca siempre igual, sin depender de `$PWD`: subdirectorios del proyecto (layout de try-clone, `rf-<nombre>`), hermanos y las raíces `$PJ_TRIO_ROOTS` (default `/z-drive/tries`, con el prefijo de fecha de `try clone`). El PM lee el issue con `gh issue view <ticket> -R <dueño>/<miembro>` y el handoff/agentes usan la clave `<miembro>-<ticket>` (no choca el #4 de dos miembros). Se añade al agente mediante `--add-dir`.
- `--dry-run`: Muestra los comandos y la topología sin aplicarlos.
- `--no-kickoff`: No envía el prompt de arranque al PM.
- `--print-kickoff`: Imprime el prompt de arranque renderizado y sale (para pegarlo a mano).

### Disposición de Tabs (Topología)

En lugar de dividir un único tab en paneles pequeños, `pj-trio` crea o reutiliza tres tabs en herdr a pantalla completa dentro del workspace, garantizando que cada agente tenga el espacio completo de terminal sin splits:

- **pm**: Tab raíz para la coordinación y gestión del ticket. Panel etiquetado como `PM-<ticket>`, con agente `pm-<miembro corto>-<ticket>`.
- **wk**: Tab dedicado a la implementación de cambios y código. Panel etiquetado como `WK-<ticket>`, con agente `wk-<proyecto>-<ticket>`.
- **rv**: Tab dedicado a la revisión técnica y validación de entregas. Panel etiquetado como `RV-<ticket>`, con agente `rv-<proyecto>-<ticket>`.

El directorio de trabajo (`cwd`) para los tres tabs es la carpeta del proyecto meta (`pj-*`). Si se especifica un repositorio miembro con `--repo`, la ruta resuelta se inyecta como contexto adicional al agente mediante `--add-dir <ruta-miembro>`.

### Etiquetado de Workspace

La etiqueta del espacio de trabajo se genera automáticamente:
- Sin `--repo`: `trio <proyecto>#<ticket>`
- Con `--repo`: `trio <proyecto>/<miembro>#<ticket>`

`<proyecto>` sale de `proyecto:` en `proyecto.yml` (o del remoto origin) y `<miembro>` del remoto origin, así que los clones con fecha de `try clone` no ensucian las etiquetas.

### Configuración de Kinds por Rol

El tipo de agente a iniciar en cada rol se define mediante variables en un archivo de configuración:

- `PM_KIND`: Kind del agente para el rol PM (por ejemplo `"agy"`).
- `WK_KIND`: Kind del agente para el rol WK (por ejemplo `"agy"`).
- `RV_KIND`: Kind del agente para el rol RV (por ejemplo `"agy"`).

Si dejás un valor vacío (`""`), el tab correspondiente queda en un shell interactivo para que arranques el proceso manualmente.

El archivo de configuración se busca en el siguiente orden de precedencia:

1. Ruta definida en la variable de entorno `PJ_TRIO_CONFIG`.
2. Archivo `.trio/trio.conf` dentro del proyecto objetivo.
3. Archivo del sistema `/usr/share/ravn/trio/trio.conf`.
4. Archivo de respaldo `trio.conf.example` (junto a `pj-trio`).
5. Archivo `trio.conf.example` (junto a `pj-trio`) dentro del proyecto objetivo.

### Rol Directo y Verificación

Cuando el kind configurado es `agy`, cada tab arranca el agente directamente con su rol asignado (`--agent PM-<proyecto>`, `--agent WK-<proyecto>`, `--agent RV-<proyecto>`), sin pasar por menús interactivos ni selectores manuales.

Antes de inicializar, `pj-trio` consulta `agy agents` para verificar que los agentes del proyecto existan en el sistema (registrados en agy). Si alguno falta, la ejecución se detiene con un mensaje de error explícito.

### Integración Idempotente con herdr

Antes de arrancar los agentes, `pj-trio` verifica mediante `herdr integration status` que la integración correspondiente al kind (para `agy`, la definida en `TRIO_HERDR_INTEGRATION_AGY` de la config) esté instalada. Si falta, la instala automáticamente mediante `herdr integration install <target>`.

### Idempotencia

Si ejecutás `pj-trio` una segunda vez con los mismos argumentos:
- Detecta el workspace existente por su etiqueta.
- Reutiliza los tabs `pm`, `wk` y `rv` ya creados.
- No duplica procesos ni paneles de agentes en ejecución.
- Mantiene exactamente 3 tabs y 3 paneles en total, sin splits residuales ni paneles huérfanos.

### El PM maneja a WK y RV (#60)

- **Nombres de agente:** `pm|wk|rv-<miembro corto>-<ticket>` (o `<proyecto>` sin `--repo`), en minúsculas y saneados para herdr (≤32, `^[a-z][a-z0-9_-]*$`). Se quitan los prefijos `pj-domina-`, `rf-`, `fo-` (`rf-pj-domina-rf-git-setup` #3 → `pm-git-setup-3`); si aún no cabe se trunca y se agrega un hash de 4 caracteres. Es determinista: si ese ticket ya tiene su trío corriendo, `pj-trio` avisa y no lo duplica.
- **Arranque automático:** tras abrir los tabs, `pj-trio` renderiza `trio-pm-prompt.md` y lo envía con `herdr agent prompt pm-<miembro corto>-<ticket> "…"`. El marcador es `<proyecto>/.trio/<ticket>/status.json`: si existe, no se reenvía (idempotente). Si el envío falla, pegá la salida de `pj-trio --print-kickoff …`.
- **Handoff único:** `<proyecto>/.trio/<ticket>/` con `plan.md`, `wk.md`, `rv.md` y `status.json`, commiteado en el meta-repo; nombra solo roles y nunca se duplica en los repos miembros.
- **El PM pinguea** a WK y RV con `herdr agent prompt`, espera con `herdr agent wait … --timeout 600000` (reintenta si falla) y confirma con `herdr agent read` más el archivo de entrega.
- **Merge:** tras `APRUEBO <sha>` de RV, el PM mergea con `gh pr merge --squash --delete-branch --match-head-commit <sha>` sin esperar otra orden.
- **Worktree nuevo por ticket**, siempre; nunca se reutiliza uno viejo.
- **Identidad git:** `TRIO_GIT_NAME`/`TRIO_GIT_EMAIL` de la config; `pj-trio` la fija con `git config` local en el meta-repo y el miembro (los worktrees la heredan). El PM no la toca.
- **Reintento y aviso (#61):** si un paso falla (wait con error o vencido; agente blocked, agent_prompt_stalled, unknown o ausente; idle sin archivo de entrega), el PM lo reintenta una sola vez. Si vuelve a fallar se detiene, escribe `status.json` con `needs-roberto` y la cola del panel, y lanza `notify-send`. Nunca responde por su cuenta un diálogo de aprobación. Las alertas al teléfono quedan fuera de alcance.
- **`trio-status`:** helper que escribe `status.json` y avisa:
  `trio-status [--dry-run] [--notify] [--cola-de <agente>] [--error <texto>] [--pr <url>] [--head <sha>] [--intentos N] <trio_dir> <estado> <paso>`.
  Esquema: `ticket`, `estado` (`en-curso`|`hecho`|`needs-roberto`), `paso` (`plan`|`wk`|`rv`|`merge`|`cierre`), `error`, `intentos`, `timestamp` (ISO 8601), `pr`, `head`, `cola`. Conserva las claves previas del archivo.
- **Prueba sin herdr:** `tests/test-pj-trio-dry-run.sh`.
