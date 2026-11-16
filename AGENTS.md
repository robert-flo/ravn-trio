# AGENTS.md

Repo de código del dúo `ravn-trio` / `ravn-trio-arch` (Arquetipo A, sin daemon).
El empaquetado (PKGBUILD) vive en `ravn-trio-arch`, no acá.

- `make lint` (shellcheck) y `make test` tienen que pasar antes de cada PR.
- Layout instalado: `pj-trio` en `/usr/bin`; `trio-status`, `trio-pm-prompt.md`
  y `trio.conf.example` en `/usr/share/ravn/trio`. `pj-trio` los busca ahí o
  junto a sí mismo (checkout). Nada en `$HOME`.
- Los prompts y los handoffs `.trio/` nombran solo roles (PM, WK, RV), nunca
  plataformas. Qué kind corre cada rol vive solo en la config (`trio.conf`).
- Versión nueva: subí `version` en `herdr-plugin.toml` en el mismo PR (título
  `… · vN.N.N`). Al mergear, `release.yml` crea el tag y el GitHub Release (o
  usa el tag `vN.N.N` si lo empujás) y avisa a `ravn-trio-arch`, que sube el
  PKGBUILD y publica solo. Sin release, el paquete no se entera.
- Commits: identidad `Roberto Flores <25asab015@ujmd.edu.sv>`, sin force push.
- Diseño de `robert-flo/pj-domina-rf-git-setup`: launcher + `runtime/commands.tsv`
  + módulos en `runtime/scripts/`. `runtime/lib/{presentation,command_catalog,
  command_interface,dispatch,lifecycle}.sh` se copian byte a byte de git-setup;
  no editarlos acá (cambiarlos allá y re-copiar). Mensajes con `print_*`.
