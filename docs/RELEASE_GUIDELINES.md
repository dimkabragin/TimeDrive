# Release Guidelines

## Версионирование

- Обычные коммиты не должны менять релизную версию приложения.
- Формат версии приложения (CFBundleShortVersionString / MARKETING_VERSION): строго `X.Y.Z` (SemVer), например `1.0.2`.
- Формат git-тега релиза: строго `vX.Y.Z`, например `v1.0.2`.
- Изменения классифицируются по release-impact:
  - `none` — не влияет на релизную версию.
  - `patch` — исправления и совместимые мелкие улучшения (`X.Y.Z -> X.Y.(Z+1)`).
  - `minor` — обратносуместимый функционал (`X.Y.Z -> X.(Y+1).0`).
  - `major` — несовместимые изменения (`X.Y.Z -> (X+1).0.0`).
- Финальная версия для релиза подбивается отдельно на этапе релизной подготовки.

## Локальный релизный pipeline

Основной скрипт: `scripts/release_local.sh`.

### Что делает скрипт

1. Preflight-проверки инструментов (`xcodebuild`, `ditto`, `hdiutil`, `shasum`, и `gh` при `PUBLISH=1`).
2. Сборка `TimeDrive.app` через `xcodebuild` для `TimeDrive.xcodeproj`/`TimeDrive`.
3. Формирование артефактов в `dist/`:
   - `TimeDrive.app`
   - `TimeDrive.zip`
   - `TimeDrive.dmg`
   - `SHA256SUMS.txt`
4. Guardrail версии: сверка `VERSION` и `CFBundleShortVersionString`.
   - При несовпадении скрипт останавливается.
   - Исключение: `FORCE=1`.
5. Печатает summary перед публикацией.
6. При `PUBLISH=1` создает/обновляет GitHub Release и загружает артефакты.

### Параметры

- `VERSION` — релизный тег, например `v1.2.3`. Если не передан, берется из git tag.
- `PUBLISH` — `0`/`1`, публикация в GitHub Releases.
- `FORCE` — `0`/`1`, игнорировать mismatch версии.
- `SCHEME` — по умолчанию `TimeDrive`.
- `CONFIGURATION` — по умолчанию `Release`.
- `NON_INTERACTIVE` — `1` отключает подтверждение перед publish.

### Примеры запуска

```bash
# Локальная сборка артефактов без публикации
VERSION=v1.2.3 PUBLISH=0 ./scripts/release_local.sh

# Локальная сборка и публикация
VERSION=v1.2.3 PUBLISH=1 ./scripts/release_local.sh

# Принудительный обход guardrail версии
VERSION=v1.2.3 FORCE=1 PUBLISH=0 ./scripts/release_local.sh
```

## CI автопубликация

- CI-обертка: `scripts/release_ci.sh`.
- Всегда запускает `release_local.sh` с `PUBLISH=1` и `NON_INTERACTIVE=1`.
- Требует `GITHUB_TOKEN`.

Workflow: `.github/workflows/release.yml`

- Триггер: push тега `v*.*.*`.
- Runner: `macos-latest`.
- Шаги: checkout + запуск `./scripts/release_ci.sh`.
- Для публикации используется `secrets.GITHUB_TOKEN`.
