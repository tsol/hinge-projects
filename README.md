# hinge-projects

**HINGE** — into a Vite project we inject a small helper, which allows you to pinpoint the part of the website you need the agent to alter. It works as a Vite plugin alongside HMR — so changes automagically appear on the site while you're on it, surfing and looking for the next problem to solve.

[![Hinge Demo](https://img.youtube.com/vi/xMvQxht2xuI/maxresdefault.jpg)](https://youtube.com/shorts/xMvQxht2xuI)

And it works right from your phone. Use it with Hermes and **hinge-projects** (`project.sh` + Cloudflare dev tunnels) — so you get access to your frontend project running with Hinge injected.

While Hermes is running in Docker on your laptop, piloted by DeepSeek (or any LLM), you manage your projects using Hinge and tunnels — when you have a free minute you take your phone, find a thing to change on your site and just point your agent to fix that.

You can even share the access with a non-tech friend who works on the same site — they can leave their messages in the queue or immediately run a task.

---

## Install

Give your agent this link:

```
https://raw.githubusercontent.com/tsol/hinge-projects/main/skills/hinge-projects-install.md
```

The agent will:

1. Clone `hinge-projects` and `tsol/hinge`
2. Build Hinge
3. Register operational skills
4. Start Hinge dev server with a Cloudflare Tunnel
5. Give you a public URL

---

## Usage from Telegram (or any chat)

Once installed, talk to your agent in natural language:

| You say | Agent replies |
|---------|---------------|
| `какие проекты запущены?` | `hinge → https://xxx.trycloudflare.com ✅` + список всех проектов |
| `запусти hinge` | `vite=yes port=5176 tunnel=yes url=https://... ✅` |
| `какой url у krollo?` | `https://plasma-sun-jon-motors.trycloudflare.com` |
| `создай vue проект test-app --start` | `✅ Created test-app (Vue 3 + Hinge) … url=https://...` |
| `создай react blog --start` | `✅ Created blog (React + Hinge) … url=https://...` |
| `удали test-app` | `✅ Removed test-app` |
| `перезапусти krollo` | `✅ Restarted, tunnel: https://...` |

The agent automatically runs `hip` commands under the hood:

```bash
hip                          # list all projects + status + URLs
hip hinge status             # detailed Hinge status
hip krollo start             # start dev + tunnel
hip krollo restart           # restart, reuse tunnel
hip create vue test-app --start
hip create react blog --start
hip delete test-app --force
```

---

## After install

```bash
hip                        # list projects
hip hinge status           # Hinge dev server + tunnel
hip create vue my-app --start   # new Vue 3 + TS project
hip create react my-app --start  # new React + TS project
```

---

## Commands

| Command | Description |
|---------|-------------|
| `hip` | List all projects with status + clickable URLs |
| `hip <name> start` | Start Vite dev server + cloudflared tunnel |
| `hip <name> stop` | Stop dev server + tunnel |
| `hip <name> restart` | Restart Vite; reuse tunnel if same port |
| `hip <name> status` | Detailed status (vite, tunnel, health, hinge_api) |
| `hip create vue <name> [--start]` | Scaffold Vue 3 + TypeScript + Hinge |
| `hip create react <name> [--start]` | Scaffold React + TypeScript + Hinge |
| `hip create list` | Available frameworks |
| `hip delete <name> --force` | Stop + remove project directory |

---

## ⚠️ Security warning

**hinge-projects creates public Cloudflare tunnels to your local dev server.**

- Anyone with the tunnel URL can access your app and the Hinge panel
- There is **no authentication** — no login, no password, no API key
- The project is designed for **personal development and prototyping**
- Do **not** use on projects with sensitive data, production systems, or anything that requires access control

Use at your own risk.

---

## Related

- [tsol/hinge](https://github.com/tsol/hinge) — Vite plugin + UI component for Hermes agent integration
