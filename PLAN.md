# hinge-projects — план реализации

Цель: публичный репозиторий `tsol/hinge-projects` = bootstrap + lifecycle для Hermes + Hinge.
Корень репо = текущая папка `projects/`. В git только distributable-файлы; `hinge/`, `mogu-v0/` и прочие локальные проекты — вне git.

Связанные репозитории:

| Репо | Роль |
|------|------|
| `tsol/hinge` | npm-пакет: Vite plugin, component, dev playground |
| `tsol/hinge-projects` | `project.sh`, install, skills, templates, create-скрипты |

---

## Модель: рабочая папка vs git

```
projects/                          ← корень hinge-projects repo
├── .gitignore                     ✅ whitelist
├── README.md                      ⬜
├── PLAN.md                        ✅ этот файл
├── project.sh                     ✅ lifecycle + create/delete
├── hinge-project-install.sh       ✅ bootstrap с нуля
├── pnpm-workspace.yaml.example    ✅ шаблон для пользователей
│
├── skills/                        ✅ в git (единственный источник skills)
│   ├── hinge-projects-install.md  # one-shot: ссылка в чат, НЕ hermes skills install
│   ├── hinge-projects.md          # operational: start/stop/status
│   └── hinge-projects-create.md   # create + интеграция любого фреймворка
│
├── scripts/create/                ✅ в git
│   ├── _common.sh
│   ├── create.sh
│   ├── create-vue.sh
│   ├── create-react.sh
│   └── registry.txt
│
├── templates/                     ✅ в git
│   ├── vue-hinge/
│   └── react-hinge/
│
├── hinge/                         ❌ git clone tsol/hinge
├── mogu-v0/                       ❌ локальный проект
├── pnpm-workspace.yaml            ❌ локальный (из example + дописки)
├── pnpm-lock.yaml                 ❌ генерится локально
└── node_modules/                  ❌
```

`project.sh` сканирует vite-проекты в `projects/` — локально mogu виден в списке, у пользователя после install его нет.

---

## Skills: финальная схема (без stub / canonical / symlink / external_dirs)

### Три файла — три роли

| Файл | Роль | Устанавливается в Hermes? |
|------|------|---------------------------|
| `skills/hinge-projects-install.md` | One-shot bootstrap | **Нет** — пользователь кидает raw URL в чат |
| `skills/hinge-projects.md` | Operational lifecycle | **Да** — `hermes skills install` из install.sh |
| `skills/hinge-projects-create.md` | Create + manual integrate | **Да** — то же `hermes skills install` |

### Поток для конечного клиента

```
1. Пользователь в чате:
   «Вот ссылка — установи hinge projects»
   https://raw.githubusercontent.com/tsol/hinge-projects/main/skills/hinge-projects-install.md

2. Агент читает install.md → выполняет:
   curl -fsSL .../hinge-project-install.sh | bash

3. install.sh:
   - clone hinge-projects + hinge
   - pnpm build hinge
   - patch HERMES_BIN в .hinge/*.sh
   - hermes skills install <workspace>/skills/hinge-projects.md  ← установка operational skill
   - ./project.sh hinge start → URL

4. Дальше агент находит hinge-projects.md и hinge-projects-create.md
   как обычные Hermes skills (skill_view)
```

### После install

```bash
hermes skills list  # показывает hinge-projects
```

**Не используем:**
- `external_dirs` в config.yaml
- symlink в `~/.hermes/skills/`
- stub в `workspace/skills/` + canonical копия
- `/reset` — навыки подхватываются при следующей сессии

### Локальная dev-среда (наша)

- `workspace/skills/hinge-projects.md` — **удалён**
- `external_dirs` — **удалён** из config
- `hinge-projects-skill/` — **удалён**
- Будем использовать `hermes skills install` локально

---

## .gitignore (whitelist)

```gitignore
/*
!/skills/
!/skills/**
!/templates/
!/templates/**
!/scripts/
!/scripts/**
!/.gitignore
!/README.md
!/PLAN.md
!/project.sh
!/hinge-project-install.sh
!/pnpm-workspace.yaml.example
```

---

## hinge-project-install.sh

Порядок (idempotent):

| # | Шаг | Проверка |
|---|------|----------|
| 1 | `PROJECT_WORKSPACE` default: `$HOME/hermes/workspace/projects` | dir exists |
| 2 | `git clone/pull` hinge-projects | `project.sh` на месте |
| 3 | `git clone/pull` hinge (pin по tag) | `package.json` |
| 4 | `cp pnpm-workspace.yaml.example → pnpm-workspace.yaml` (если нет) | только `hinge` |
| 5 | `cd hinge && pnpm install && pnpm build` | `dist/plugin.js` |
| 6 | Detect `HERMES_BIN` → patch `.hinge/new-session.sh`, `continue-session.sh` | `hermes --version` |
| 7 | Install operational skill: `hermes skills install <workspace>/skills/hinge-projects.md` | `hermes skills list` shows it |
| 8 | `./project.sh hinge start` | `hinge_api=ok`, tunnel URL |
| 9 | Вывести status | `url=` |

**Флаги:** `--skip-start`, `--hinge-tag v0.1.2`, `--workspace /path`, `--skip-hermes-config`

---

## pnpm-workspace.yaml

**В репо** (`pnpm-workspace.yaml.example`):
```yaml
packages:
  - 'hinge'
```

**Локально у нас** (не коммитится):
```yaml
packages:
  - 'hinge'
  - 'mogu-v0'
```

---

## project.sh create (расширяемый) — ✅ сделано

```bash
./project.sh create vue my-app [--start]
./project.sh create react my-app [--start]
./project.sh create list
./project.sh delete my-app --force
```

Расширение: `create-<id>.sh` + `templates/<id>-hinge/` + строка в `registry.txt`.
Документация: `skills/hinge-projects-create.md`.

---

## Порядок реализации (обновлён)

```
✅ 1.  .gitignore + pnpm-workspace.yaml.example
✅ 2.  skills/ (install + operational + create) — без stub/canonical
✅ 3.  hinge-project-install.sh (hermes skills install, не external_dirs с PyYAML)
✅ 4.  scripts/create/* + templates/*
✅ 5.  project.sh create/delete
✅ 6.  Миграция: удалить hinge-projects-skill/, workspace/skills/hinge-projects.md
✅ 7.  external_dirs в Hermes config (локально)
⬜ 8.  README hinge-projects
⬜ 9.  git init/push → tsol/hinge-projects
⬜ 10. Fresh install test (чистая машина)
```

---

## Тесты

### Локальный smoke

```bash
./project.sh hinge restart
./project.sh hinge status   # vite=yes, hinge_api=ok, url=

./project.sh create vue test-vue-$(date +%s) --start
./project.sh create react test-react-$(date +%s) --start

curl -s http://localhost:<port>/hinge-api/status   # JSON

git status   # только whitelist файлы в staged
```

### Fresh install (чистая машина)

Пользователь даёт агенту ссылку:
```
https://raw.githubusercontent.com/tsol/hinge-projects/main/skills/hinge-projects-install.md
```

Чеклист:
- [ ] `projects/hinge/` cloned
- [ ] `hermes skills list` показывает `hinge-projects`
- [ ] **нет** `~/.hermes/skills/hinge-projects.md` symlink
- [ ] **нет** `external_dirs` в config.yaml (используем `hermes skills install`)
- [ ] `./project.sh hinge status` → URL
- [ ] агент видит `hinge-projects` skill (skill_view)
- [ ] «создай vue проект foo» → `./project.sh create vue foo --start` → URL

---

## README hinge-projects (секции)

1. **Install for users** — одна ссылка на raw `skills/hinge-projects-install.md` + фраза «скажи агенту выполнить»
2. Layout после install
3. Commands: start/stop/create
5. Skills: install.md (one-shot) vs operational (`hermes skills install`)
5. Как добавить свой framework → `hinge-projects-create.md`
6. Troubleshooting
7. Связь с `tsol/hinge`

---

## Риски

| Риск | Митигация |
|------|-----------|
| `hinge` не собран | `ensure_hinge_built` + install build |
| Случайный `git add hinge/` | whitelist gitignore |
| Старый tunnel URL | skill: URL только из status |
| `hermes skills install` требует CLI | install.sh fallback с warn |
| Агент не видит skill | `hermes skills list`, следующая сессия подхватит |

---

## Статус

| Компонент | Статус |
|-----------|--------|
| `project.sh` (lifecycle) | ✅ |
| `project.sh create/delete` | ✅ |
| `scripts/create/*` + templates | ✅ |
| `skills/` (3 файла) | ✅ |
| `.gitignore` whitelist | ✅ |
| `pnpm-workspace.yaml.example` | ✅ |
| `hinge-project-install.sh` | ✅ |
| Миграция stub/canonical | ✅ |
| `hermes skills install` (operational) | ✅ |
| README | ⬜ |
| Push `tsol/hinge-projects` | ⬜ |
| Fresh install test | ⬜ |
