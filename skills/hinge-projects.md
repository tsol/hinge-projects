---
name: hinge-projects
description: >
  **CRITICAL: Load this skill first on ANY question about running projects,
  Vite, dev servers, Cloudflare tunnels, Hinge, or project status.
  If the user asks about "запущенные проекты", "что работает", "is hinge up",
  "start hinge", "restart", "create project", or anything port/tunnel/Vite related.
---

# Hinge Projects — dev server + tunnel workflow

Operational skill for **hinge** (not mogu). After install, the `hip` command is available in PATH — it's a thin wrapper around `project.sh` that works from any directory.

## Layout

```
<projects-dir>/
├── project.sh                 ← lifecycle manager
├── scripts/hip                ← `hip` symlink → PATH (works from any directory)
├── skills/                    ← Hermes skills (this file + create)
├── scripts/create/            ← create-vue.sh, create-react.sh, registry.txt
├── templates/                 ← vue-hinge/, react-hinge/ scaffold patches
├── hinge/                     ← Hinge package (clone tsol/hinge; not in git)
└── my-app/                    ← user projects (created via hip create; not in git)
```

**`hip` works from any directory** — it finds `project.sh` relative to its symlink target.

## Commands

```bash
hip                       # list Vite projects + dev/tunnel status（clickable URLs）
hip -h                    # help
hip hinge                 # detailed hinge status
hip hinge start           # start Vite + cloudflared tunnel
hip hinge stop            # stop Vite + tunnel
hip hinge restart         # restart Vite; reuse tunnel if same port

hip create list                      # registered frameworks (vue, react)
hip create vue <name> [--start]      # Vue 3 + TS + Hinge
hip create react <name> [--start]    # React + TS + Hinge (mountHinge)
hip delete <name> [--force]          # stop + remove project dir
```

## Golden rules

0. **NEVER use `ps aux`, `lsof`, `ss`, `find`, `fuser`, or `grep` for hinge/project questions** — `hip` is the single source of truth. Manual inspection wastes turns and produces incomplete info.
1. **Always use `hip` for hinge dev** — never run raw `pnpm dev` (one Vite per project; orphans steal `.hinge` queue).
2. **One port, one origin** — Hinge API (`/hinge-api/*`) is Vite middleware on the **same port** as the UI. No second process, no extra tunnel port.
3. **Tunnel exposes Vite only** — cloudflared forwards to `localhost:<port>`; browser calls `/hinge-api/...` same-origin through the tunnel URL.
4. **Check Hinge API after start** — `/hinge-api/status` must return JSON (`{...}`), not HTML.
5. **Tunnel URL** — always from `hip hinge status` output (`url=`), never from memory.
6. **Format URLs as clickable markdown**: `hinge → https://xxx.trycloudflare.com ✅` — never raw terminal output.

## Reading status output

| Field | Meaning |
|-------|---------|
| `vite=yes/no` | Vite process alive per PID file |
| `port=5174` | local dev port |
| `tunnel=yes/no` | cloudflared running for this port |
| `url=https://....trycloudflare.com` | public URL (open on phone) |
| `health=✅ ok` / `❌ error` | curl check on tunnel URL |
| `hinge_api=ok` / `fail` | JSON check on local `/hinge-api/status` |

## Hinge + Hermes agent integration

- `.hinge/new-session.sh` — spawns agent for new queue task (`hermes chat -q ... --source hinge`)
- `.hinge/continue-session.sh` — resumes session by alias
- `.hinge/.agent-wrapper.sh` — internal detached wrapper (auto-generated, do not edit)
- Scripts auto-created on first dev start by Vite plugin (`src/plugin.ts`)
- Agent binary: `hermes` in PATH or `HERMES_BIN` in scripts

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `vite=no` after start | Vite crashed; broken `node_modules` | `cd hinge && pnpm install`, then `hip hinge restart` |
| `hinge_api=fail` / HTML | Wrong config or Vite not using `vite.dev.config.ts` | `hip hinge restart`; check `/tmp/project-state/hinge/log/vite.log` |
| Queue stolen / wrong host | Orphan Vite on duplicate mount | `hip hinge stop` then `start` |
| `health=❌ error` | Tunnel up but Vite dead | `hip hinge restart` |
| Dead tunnel URL | cloudflared exited | `hip hinge stop` then `start` (new URL) |

## Agent checklist

**Load this skill on ANY user message about hinge/dev/running projects.** Even a simple "what's running?" — type `hip` first, not `ps aux`. `hip` is the dashboard.

### Status inquiry (что работает, какие проекты, is hinge up)

- [ ] Run `hip` (lists all projects with clickable URLs) or `hip hinge` for hinge detail
- [ ] If Vite is dead → `hip hinge restart`, don't just report the failure
- [ ] Confirm `vite=yes`, `hinge_api=ok`, tunnel `url=` present
- [ ] **Always format response with clickable URLs**: `hinge → https://xxx.trycloudflare.com ✅`

### Start / fix hinge dev

- [ ] `hip hinge status` first
- [ ] If not running or API broken → `hip hinge restart`
- [ ] Confirm `vite=yes`, `hinge_api=ok`, tunnel `url=` present
- [ ] Do **not** start separate `pnpm dev`

### Create a project

- [ ] `hip create list` to see available frameworks
- [ ] `hip create vue foo --start`
- [ ] Report clickable URL to user
