---
name: hinge-projects-create
description: >
  Create new Vue or React Vite projects with Hinge wired in via `hip create`.
  Use when the user asks to scaffold a new frontend app with hinge, create vue/react
  project, or integrate hinge into an existing Vite project on any framework.
  `hip` works from any directory.
---

# Hinge Projects — Create & integrate

`hip` works from any directory — it finds `project.sh` via its symlink.

## Quick create (Vue / React)

```bash
hip create list
hip create vue my-app --start
hip create react my-app --start
hip delete my-app --force
```

| Command | Result |
|---------|--------|
| `create vue <name> [--start]` | Vue 3 + TS + `hingePlugin()` + `<Hinge />` |
| `create react <name> [--start]` | React + TS + `hingePlugin()` + `mountHinge('body')` |
| `create list` | Frameworks in `scripts/create/registry.txt` |
| `delete <name> --force` | Stop dev, remove dir, drop from `pnpm-workspace.yaml` |

With `--start`: runs `hip <name> start` and prints tunnel `url=`. No need to `cd` anywhere.

## What `create` does internally

1. `pnpm create vite <name> --template vue-ts` or `react-ts`
2. `ensure_hinge_built` — `pnpm build` in `hinge/` if `dist/` missing
3. Add `"hinge": "file:../hinge"` to `package.json`
4. Apply template from `templates/vue-hinge/` or `templates/react-hinge/`
5. Append project to local `pnpm-workspace.yaml` (if file exists)
6. `pnpm install` from workspace root

## Rules

- Name: letters/digits/`_`/`-`, must start with a letter
- Reserved names: `hinge`, `skills`, `scripts`, `templates`, `node_modules`
- **Never** hand-roll `pnpm create vite` without hinge wiring — use `hip create`
- After create: `hip <name> status` → confirm `hinge_api=ok`, give user `url=`

## Agent checklist — create project

- [ ] `hip create list` — pick framework
- [ ] `hip create vue|react <name> --start`
- [ ] `hip <name> status` — report tunnel `url=`
- [ ] Do **not** use `pnpm link` — use `file:../hinge`

## Agent checklist — delete project

- [ ] Confirm project name with user
- [ ] `hip delete <name> --force`

---

## Extend: add a new framework (e.g. Svelte)

1. Add `scripts/create/create-svelte.sh` (copy `create-vue.sh` as template)
2. Add `templates/svelte-hinge/` with vite config + entry component wiring
3. Register in `scripts/create/registry.txt` (one id per line)
4. `hip create list` should show the new framework

`create.sh` dispatches to `create-<framework>.sh` and sources `_common.sh`.

### `create-<framework>.sh` contract

```bash
#!/bin/bash
set -o pipefail
source "$(dirname "$0")/_common.sh"
_create_common_init
name="$1"; shift || true
_create_validate_name "$name" || exit 1
_create_scaffold_vite "$name" "<pnpm-template>"   # e.g. vue-ts, react-ts
_create_ensure_hinge_built || exit 1
_create_add_hinge_dep "$CREATE_PROJECTS_ROOT/$name"
_create_apply_template "<framework>" "$name"      # copies templates/<framework>-hinge/
_create_patch_workspace_yaml "$name"
_create_pnpm_install "$name"
_create_optional_start "$name" "$@"
```

---

## Manual integration: any existing Vite project

Use when the framework is not in `registry.txt` or the project already exists.

### 1. Hinge package must be built

```bash
cd hinge && pnpm install && pnpm build
```

### 2. Add dependency

In `<project>/package.json`:

```json
"hinge": "file:../hinge"
```

Run `pnpm install` from workspace root (or project dir).

### 3. Vite config

```ts
import { defineConfig } from 'vite'
import hingePlugin from 'hinge/plugin'

export default defineConfig({
  plugins: [
    // your framework plugin(s) first
    hingePlugin(),
  ],
  server: {
    host: '0.0.0.0',
    allowedHosts: ['.trycloudflare.com', '.localhost'],
    // optional: hmr: false for stable tunnel sessions
  },
})
```

### 4. Mount Hinge in UI

**Vue 3** (`App.vue`):

```vue
<script setup lang="ts">
import { Hinge } from 'hinge/component'
</script>
<template>
  <Hinge />
  <!-- your app -->
</template>
```

**React** (`main.tsx`):

```tsx
import { mountHinge } from 'hinge'
import 'hinge/style.css'  // if exported; or component styles via mountHinge

mountHinge('body')
// your React root mount alongside or inside body
```

### 5. Workspace yaml (optional)

Add project name to `pnpm-workspace.yaml` packages list.

### 6. Start via hip

```bash
hip <project-name> start
hip <project-name> status   # hinge_api=ok, url=
```

### 7. Verify

- [ ] `GET /hinge-api/status` returns JSON on dev port
- [ ] Cog overlay visible in browser (tunnel URL)
- [ ] `.hinge/` created after first dev start
- [ ] Queue task creates folder in `.hinge/`

---

## Template reference

| Framework | Template dir | Key files |
|-----------|--------------|-----------|
| Vue | `templates/vue-hinge/` | `vite.config.ts`, `App.vue` |
| React | `templates/react-hinge/` | `vite.config.ts`, `main.tsx` |

Read existing templates before authoring a new one — match `allowedHosts` and plugin order.
