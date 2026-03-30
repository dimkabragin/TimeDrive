# Release Guidelines

## Версионирование

- Формат версии приложения (`CFBundleShortVersionString` / `MARKETING_VERSION`): `X.Y.Z`.
- Формат git-тега релиза: `vX.Y.Z`.
- Для release pipeline версия в теге и в приложении должна совпадать (или явно использовать `FORCE=1`).

## Обязательные инструменты и артефакты

Ключевые скрипты:

- `scripts/release_local.sh` — основной release pipeline.
- `scripts/release_ci.sh` — CI-обертка с fail-fast проверками.
- `.github/workflows/release.yml` — GitHub Actions workflow по тегу `v*.*.*`.

Результат release pipeline в `dist/`:

- `TimeDrive.app`
- `TimeDrive.zip`
- `TimeDrive.dmg`
- `SHA256SUMS.txt`
- `appcast.xml` (если `APPCAST_GENERATE=1`)
- `update-metadata.json` (если `APPCAST_GENERATE=1`)

`TimeDrive.dmg` содержит `TimeDrive.app` и ссылку `Applications` для установки drag-and-drop.

## Параметры `release_local.sh`

### Общие

- `VERSION` — релизный тег (`v1.2.3`).
- `PUBLISH` — `0/1`, публикация в GitHub Release.
- `NON_INTERACTIVE` — `1` отключает интерактивное подтверждение.
- `FORCE` — `1` разрешает mismatch версии тега и Info.plist.
- `SCHEME` — по умолчанию `TimeDrive`.
- `CONFIGURATION` — по умолчанию `Release`.

### Автообновление / appcast

- `APPCAST_GENERATE` — `0/1`, генерация `appcast.xml` и `update-metadata.json`.
- `APPCAST_URL` — публичный URL appcast.
- `SPARKLE_APPCAST_URL` — URL, который инжектится в `Info.plist` как `SUFeedURL` (если пусто, берется из `APPCAST_URL`).
- `APPCAST_BASE_DOWNLOAD_URL` — базовый URL release-артефактов (HTTPS).
- `APPCAST_CHANNEL` — канал обновлений (`stable` по умолчанию).
- `RELEASE_NOTES_URL` — URL release notes (HTTPS).

### Sparkle-подпись (production)

- `SPARKLE_SIGN_UPDATE` — `0/1`, требовать подпись в `appcast.xml`.
- `SPARKLE_PUBLIC_ED_KEY` — публичный Sparkle Ed25519 ключ (инжектится в `Info.plist` как `SUPublicEDKey`).
- `SPARKLE_EDDSA_SIGNATURE` — готовая подпись (legacy/manual fallback).
- `SPARKLE_PRIVATE_KEY` — приватный Sparkle Ed25519 ключ (многострочный secret, рекомендовано для CI).
- `SPARKLE_PRIVATE_KEY_B64` — тот же ключ в base64 (fallback).
- `SPARKLE_PRIVATE_KEY_FILE` — путь к файлу ключа (fallback).
- `SPARKLE_SIGN_UPDATE_TOOL` — явный путь к `sign_update` (если не в `PATH`).

Поведение fail-fast:

- для production (`PUBLISH=1` или `RELEASE_ENV=production`) обязательны:
  - `SPARKLE_APPCAST_URL`/`APPCAST_URL` (HTTPS),
  - `SPARKLE_PUBLIC_ED_KEY`,
  - `APPCAST_GENERATE=1`,
  - `SPARKLE_SIGN_UPDATE=1`;
- в production сборка валидируется постфактум: в собранном `TimeDrive.app/Contents/Info.plist` обязаны быть `SUFeedURL` и `SUPublicEDKey`;
- если `SPARKLE_SIGN_UPDATE=1`, но нет ни подписи, ни ключа — скрипт завершится с ошибкой;
- если `SPARKLE_SIGN_UPDATE=1` и `SPARKLE_EDDSA_SIGNATURE` пустая, подпись вычисляется автоматически через `sign_update`;
- если `sign_update` недоступен, скрипт завершится с инструкцией задать `SPARKLE_SIGN_UPDATE_TOOL`.
- в production `dist/appcast.xml` обязан содержать `sparkle:edSignature` (иначе релиз прерывается).

## GitHub Actions: обязательные Variables / Secrets

### Repository Variables

- `APPCAST_GENERATE` = `1` (рекомендуется)
- `APPCAST_CHANNEL` = `stable`
- `APPCAST_URL` = `https://<owner>.github.io/<repo>/appcast.xml`
- `SPARKLE_APPCAST_URL` = `https://<owner>.github.io/<repo>/appcast.xml` (или другой публичный URL)
- `APPCAST_PUBLISH_MODE`:
  - `pages` — публиковать appcast в `gh-pages` (**production default**)
  - `artifact` — только для непубличных/dev сценариев (для production запрещен)
- `SPARKLE_SIGN_UPDATE` = `1` (production режим по умолчанию)
- `SPARKLE_SIGN_UPDATE_TOOL` (опционально) = абсолютный путь к `sign_update`
- `SPARKLE_PRIVATE_KEY_FILE` (опционально) = путь к key-файлу на runner
- `SPARKLE_PUBLIC_ED_KEY` = публичный Sparkle ключ для инъекции в `Info.plist`

### Repository Secrets

- `SPARKLE_PRIVATE_KEY` (рекомендуется) — приватный Sparkle ключ в исходном виде
- `SPARKLE_PRIVATE_KEY_B64` (опционально) — приватный ключ в base64
- `SPARKLE_EDDSA_SIGNATURE` (опционально) — заранее рассчитанная подпись

Примечание: для production достаточно `SPARKLE_PRIVATE_KEY` + `SPARKLE_SIGN_UPDATE=1`.

## Генерация и ротация Sparkle-ключей

1. Сгенерировать ключи утилитой Sparkle (обычно `generate_keys`, из Sparkle tooling).
2. Публичный ключ хранится в конфигурации приложения (уже интегрировано на app-side).
3. Приватный ключ хранить только в GitHub Secrets (`SPARKLE_PRIVATE_KEY`), без коммитов в репозиторий.
4. При ротации:
   - сгенерировать новую пару;
   - обновить публичный ключ в приложении (в отдельной задаче/релизе приложения);
   - обновить `SPARKLE_PRIVATE_KEY` в Secrets;
   - выпустить новую версию и проверить успешное обновление.

## Runbook релиза (production, с автообновлением)

1. Подготовить тег `vX.Y.Z` и убедиться, что версия приложения = `X.Y.Z`.
2. Проверить настройки Variables/Secrets из раздела выше.
3. Запушить тег:

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

4. Workflow `release.yml` выполняет:
   - сборку и упаковку артефактов;
   - обязательную инъекцию `SUFeedURL`/`SUPublicEDKey` в release build через env-параметры;
   - вычисление Sparkle-подписи из secrets (если не передана вручную);
   - генерацию `appcast.xml` и `update-metadata.json`;
   - публикацию release-артефактов;
   - upload appcast-метаданных как artifact;
   - публикацию appcast в `gh-pages` (production default, `APPCAST_PUBLISH_MODE=pages`);
   - проверку доступности публичного `SPARKLE_APPCAST_URL` и наличия `sparkle:edSignature`.

## Локальные команды (в том числе dry-run)

```bash
# Локальный dry-run без publish
VERSION=v1.2.3 PUBLISH=0 ./scripts/release_local.sh

# Локальный run c appcast и подписью из ключа
VERSION=v1.2.3 \
PUBLISH=0 \
SPARKLE_APPCAST_URL='https://example.com/appcast.xml' \
SPARKLE_PUBLIC_ED_KEY='***PUBLIC_ED25519_KEY***' \
SPARKLE_SIGN_UPDATE=1 \
SPARKLE_PRIVATE_KEY='***PRIVATE_KEY***' \
APPCAST_BASE_DOWNLOAD_URL='https://github.com/<owner>/<repo>/releases/download/v1.2.3' \
RELEASE_NOTES_URL='https://github.com/<owner>/<repo>/releases/tag/v1.2.3' \
./scripts/release_local.sh
```

## Checklist валидации после релиза

1. GitHub Release содержит `TimeDrive.zip`, `TimeDrive.dmg`, `SHA256SUMS.txt`.
2. `dist/update-metadata.json` содержит корректные `version`, `artifact_url`, `sha256`, `release_notes_url`.
3. `appcast.xml` содержит актуальную версию и валидный `enclosure url`.
4. При `SPARKLE_SIGN_UPDATE=1` в `appcast.xml` присутствует `sparkle:edSignature`.
5. В release app `Info.plist` содержит `SUFeedURL` и `SUPublicEDKey` (пост-валидация скриптом).
6. При `APPCAST_PUBLISH_MODE=pages` файл доступен по `SPARKLE_APPCAST_URL` и отдается по HTTPS.

## Ограничения локальной проверки

- Полноценный e2e Sparkle update-flow в локальной среде CI-поведения не гарантируется.
- Минимально обязательны:
  - синтаксическая проверка bash-скриптов (`bash -n`);
  - dry-run генерации `appcast.xml`/`update-metadata.json`.
- Проверка фактической установки обновления выполняется в отдельном интеграционном прогоне на собранном приложении.
