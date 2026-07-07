---
name: hinge-projects-install
description: >
  One-shot bootstrap for hinge-projects + hinge dev environment.
  Use ONLY when the user asks to install hinge projects from scratch.
  Do NOT install this file into ~/.hermes/skills/ — read it once and execute.
---

# Hinge Projects — Install (one-shot)

**This is a one-time instruction sheet, not a permanent Hermes skill.**

The user shares this file (or its raw GitHub URL) in chat. Read it, execute the steps, report the tunnel URL. After install, the operational skill `hinge-projects` is installed in Hermes via `hermes skills install`.

## Prerequisites

- Linux with `git`, `curl`, `bash`
- `pnpm` (install script bootstraps via corepack if missing)
- `cloudflared` (install script bootstraps if missing)
- Hermes agent CLI (`hermes` in PATH or known path like `/opt/hermes/.venv/bin/hermes`)

## Install

```bash
# Default workspace: $HOME/hermes/workspace/projects (override with PROJECT_WORKSPACE)
curl -fsSL https://raw.githubusercontent.com/tsol/hinge-projects/main/hinge-project-install.sh | bash
```

Or with options:

```bash
curl -fsSL https://raw.githubusercontent.com/tsol/hinge-projects/main/hinge-project-install.sh -o /tmp/hinge-project-install.sh
bash /tmp/hinge-project-install.sh --workspace "$HOME/hermes/workspace/projects"
```

## What the install script does

1. Clone or update `tsol/hinge-projects` → `$PROJECT_WORKSPACE`
2. Clone or update `tsol/hinge` → `$PROJECT_WORKSPACE/hinge`
3. Copy `pnpm-workspace.yaml.example` → `pnpm-workspace.yaml` (if missing)
4. `pnpm install` + `pnpm build` in `hinge/`
5. Detect `HERMES_BIN` and patch `hinge/.hinge/new-session.sh` + `continue-session.sh`
6. Install operational skill: `hermes skills install $PROJECT_WORKSPACE/skills/hinge-projects.md`
7. Install `hip` command: symlink `scripts/hip` → `/usr/local/bin/hip` (or `~/.local/bin/hip`)
8. `./project.sh hinge start`
9. Print tunnel URL from `./project.sh hinge status`

## After install — report to user

After install script completes, **load the operational skill and use it to report status**:

```bash
skill_view('hinge-projects')
hip          # shows all projects with ports and tunnel URLs
hip hinge    # detailed hinge status
```

### Final response to user must include:

1. **Clickable URLs** for every running project — format:
   ```
   hinge → https://xxx.trycloudflare.com ✅
   ```
2. `hinge_api=ok` confirmation
3. Tell user: «для новых проектов — попроси «создай vue/react проект»» (агент выполнит `hip create vue foo --start`)
**CRITICAL:** Do NOT return raw terminal output — extract `url=` values and format them as clickable markdown links. If tunnel health check fails but hinge_api=ok, still show the URL (tunnel may take a moment).

## Re-run / update

Safe to re-run — idempotent clone/pull, skips existing `pnpm-workspace.yaml` customizations.

```bash
cd "$PROJECT_WORKSPACE" && git pull
cd hinge && git pull && pnpm install && pnpm build
./project.sh hinge restart
```

## Do NOT

- `hermes skills install` this file — it is not an operational skill
- Run `pnpm dev` manually — always `./project.sh hinge start`

## Flags (install script)

| Flag | Effect |
|------|--------|
| `--workspace /path` | Target projects directory |
| `--hinge-tag v0.1.0` | Pin hinge clone to tag/branch |
| `--skip-start` | Skip `./project.sh hinge start` |
| `--skip-hip` | Skip installing `hip` command to PATH |
