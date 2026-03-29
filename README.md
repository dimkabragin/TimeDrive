# TimeDrive

macOS SwiftUI приложение для трекинга задач и времени.

## Release

- Локальный pipeline: `scripts/release_local.sh`
- CI-обертка: `scripts/release_ci.sh`
- GitHub Actions workflow: `.github/workflows/release.yml`
- Полные правила релиза: `docs/RELEASE_GUIDELINES.md`

### Быстрый запуск локального релиза

```bash
VERSION=v1.2.3 PUBLISH=0 ./scripts/release_local.sh
```

Скрипт формирует артефакты в `dist/`:

- `TimeDrive.app`
- `TimeDrive.zip`
- `TimeDrive.dmg`
- `SHA256SUMS.txt`

Автопубликация выполняется в CI при push тега формата `v*.*.*`.
