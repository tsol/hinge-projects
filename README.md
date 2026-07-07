# hinge-projects 🛝

> [🇷🇺 Русский](README.ru.md) • [🇺🇦 Українська](README.ua.md)

yo, here's a recipe. the most cheapest and fun way to vibecode in free time i've found is:

**[Hermes](https://hermes-agent.nousresearch.com)** + **[DeepSeek](https://platform.deepseek.com)** + **[Hinge](https://github.com/tsol/hinge)**

[![Hinge Demo](https://img.youtube.com/vi/xMvQxht2xuI/maxresdefault.jpg)](https://youtube.com/shorts/xMvQxht2xuI)

---

## what's the deal

you know that feeling when an idea pops and you just wanna quickly build it on your phone while lying on a couch? yeah.

**HINGE** is a tiny Vite plugin that injects a helper overlay into your frontend project. you click a cog, type what you want changed, and your AI agent edits the code — HMR makes it appear right in the browser. no IDE, no terminal, no desk required.

you run a **cloudflared tunnel** to your local dev server, get a public URL, open it on your phone, and start vibecoding from anywhere.

the setup takes one command. and i mean **one**:

```
https://raw.githubusercontent.com/tsol/hinge-projects/main/skills/hinge-projects-install.md
```

give that to your agent. done.

---

## what you get

- a dev server with Hinge panel on any machine you own
- a public URL accessible from your phone, tablet, anywhere
- ability to **create new Vue/React projects** with Hinge pre-wired — one command
- your agent knows the project structure, reads/writes files, live updates in browser
- you can even share the tunnel with a non-technical friend — they can leave tasks in the queue

---

## how to use from Telegram (or any chat)

once it's running, just talk to your agent:

| You say | Agent answers |
|---------|---------------|
| `what's running?` | `hinge → https://xxx.trycloudflare.com ✅` + project list |
| `what's the url for krollo?` | `https://plasma-sun-jon-motors.trycloudflare.com` |
| `create vue project test-app` | `✅ Created test-app … url=https://...` |
| `create react blog test-blog` | `✅ Created blog … url=https://...` |
| `delete test-app` | `✅ Removed test-app` |
| `restart krollo` | `✅ Restarted, tunnel: https://...` |

the agent runs `hip` under the hood — same as typing in terminal:

```bash
hip                          # list all projects + status + URLs
hip hinge status             # detailed hinge status
hip krollo start             # start dev + tunnel
hip krollo restart           # restart, keeps tunnel alive
hip create vue test-app --start
hip create react blog --start
hip delete test-app --force
```

---

## commands

| Command | What it does |
|---------|-------------|
| `hip` | List all projects with status + clickable URLs |
| `hip <name> start` | Start dev server + cloudflare tunnel |
| `hip <name> stop` | Kill dev server + tunnel |
| `hip <name> restart` | Restart; reuses tunnel if same port |
| `hip <name> status` | Detailed: vite, tunnel, health, hinge_api |
| `hip create vue <name> [--start]` | Scaffold Vue 3 + TS + Hinge |
| `hip create react <name> [--start]` | Scaffold React + TS + Hinge |
| `hip create list` | Show available frameworks |
| `hip delete <name> --force` | Stop + wipe project |

---

## ⚠️ dude, seriously

**hinge-projects creates public Cloudflare tunnels straight into your local dev server.**

- anyone with the URL can open your app and the Hinge panel
- there is **zero auth** — no login, password, token, nothing
- this is strictly for **personal prototyping and vibecoding**
- do **not** point this at production, databases, crypto wallets, or your grandma's secret cookie recipe

you've been warned. use at your own risk.

---

## related

- [Hermes Agent](https://hermes-agent.nousresearch.com) — the agent runtime this was built for
- [Hinge](https://github.com/tsol/hinge) — the Vite plugin + UI overlay
