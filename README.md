# TimeDrive

TimeDrive - это pomodoro-timer, который позволяет работать по принципу фокус-сессий (например: 25 минут работаешь, 5 отдыхаешь), вести список задач и проектов, а также отслеживать количество времени, которое вы потратили в рамках проекта. 

## Для кого и какие задачи решает

TimeDrive подойдёт тем, кому хочется структурировать свои задачи и контролировать время, которое на них уходит. Для этого в рамках проекта реализованы:

- Таймер для фокус-сессий и учёта времени по текущей задаче.
- Управление задачами: создание, редактирование и актуализация списка дел.
- Организация задач по проектам.
- Логирование затраченного времени в рамках проекта.

## Как установить приложение

1. Откройте раздел [Releases](https://github.com/dimkabragin/TimeDrive/releases) репозитория.
2. Скачайте актуальный установщик `TimeDrive.dmg` (или `TimeDrive.zip`).
3. Откройте файл и перенесите `TimeDrive.app` в `Applications`.
4. Запустите приложение из Launchpad или папки `Applications`.

## Техническая информация для разработчика

### Release

- Локальный pipeline: `scripts/release_local.sh`
- CI-обертка: `scripts/release_ci.sh`
- GitHub Actions workflow: `.github/workflows/release.yml`
- Полные правила релиза: `docs/RELEASE_GUIDELINES.md`

### Быстрый запуск локального релиза

```bash
VERSION=v1.2.3 PUBLISH=0 ./scripts/release_local.sh
```

### Auto-update (Sparkle) для production

- В CI подпись обновления рассчитывается автоматически из `SPARKLE_PRIVATE_KEY` (GitHub Secret) при `SPARKLE_SIGN_UPDATE=1`.
- Appcast/metadata генерируются скриптом `scripts/release_local.sh` и публикуются workflow `release.yml`.
- Режим публикации appcast:
  - `APPCAST_PUBLISH_MODE=artifact` (по умолчанию) — только как workflow artifact
  - `APPCAST_PUBLISH_MODE=pages` — публикация в ветку `gh-pages`
- Подробный runbook, список обязательных variables/secrets и процедура ротации ключей: `docs/RELEASE_GUIDELINES.md`.

Скрипт формирует артефакты в `dist/`:

- `TimeDrive.app`
- `TimeDrive.zip`
- `TimeDrive.dmg`
- `SHA256SUMS.txt`

Автопубликация выполняется в CI при push тега формата `v*.*.*`.
