# hinge-projects

> One-command Hermes agent workflow — install, dev servers, tunnels, project scaffolding with [Hinge](https://github.com/tsol/hinge).

## Install (one line)

Give this URL to your Hermes agent:

```
https://raw.githubusercontent.com/tsol/hinge-projects/main/skills/hinge-projects-install.md
```

The agent will:

1. Clone `hinge-projects`
2. Clone `tsol/hinge` into `hinge/`
3. Build Hinge (`pnpm install && pnpm build`)
4. Register operational skills
5. Start Hinge dev server with a Cloudflare Tunnel
6. Print the public URL

## After install

```bash
hip                        # list projects
hip hinge status           # Hinge dev server + tunnel
hip create vue my-app --start   # new Vue 3 + TS project
hip create react my-app --start  # new React + TS project
```

## Layout

```
projects/
├── project.sh              ← lifecycle manager
├── hinge-project-install.sh ← bootstrap script
├── skills/                  ← Hermes agent skills
│   ├── hinge-projects.md         # operational: start/stop/status
│   ├── hinge-projects-create.md  # create + manual integration
│   └── hinge-projects-install.md # one-shot install (not a registered skill)
├── scripts/create/          ← scaffolding scripts
├── templates/               ← project templates (vue, react)
├── hinge/                   ← tsol/hinge (cloned by install)
└── project-name/            ← your projects (created via hip create)
```

## Commands

| Command | Description |
|---------|-------------|
| `hip` | List all projects with status |
| `hip <name> start` | Start Vite dev server + tunnel |
| `hip <name> stop` | Stop dev server + tunnel |
| `hip <name> restart` | Restart, reuse tunnel |
| `hip <name> status` | Detailed status |
| `hip create vue <name> [--start]` | Scaffold Vue 3 + Hinge |
| `hip create react <name> [--start]` | Scaffold React + Hinge |
| `hip create list` | Available frameworks |
| `hip delete <name> --force` | Remove project |

## Related

- [tsol/hinge](https://github.com/tsol/hinge) — Vite plugin + UI component for Hermes agent integration
