# TimeDrive: архитектурный проект

## 1. Цели и границы системы

TimeDrive - macOS-приложение (SwiftUI) для фокус-работы по технике Pomodoro c учетом реальных рабочих сценариев:

- рабочий и отдых-периоды с непрерывным учетом времени;
- настройка длительности работы и отдыха;
- учет **extra-time** после завершения периода (таймер не останавливается);
- задачи и проекты, где задача может быть как внутри проекта, так и отдельно;
- привязка текущей сессии к задаче, быстрый переход на другую задачу или отдых;
- полноценная работа офлайн + синхронизация при появлении сети;
- Python backend для мульти-девайс синхронизации и резервного хранения.

## 2. Ключевые продуктовые принципы

1. **Offline-first:** локальное состояние - источник истины для UI.
2. **Event-driven time tracking:** хранение событий старта/переключений/завершений, а не только "текущего значения секунд".
3. **Непрерывный счетчик:** после plan duration переходим в overrun (extra-time), не создавая разрывов.
4. **Гибкая связь Task/Project:** `task.projectId` опционален.
5. **Конфликт-устойчивая синхронизация:** локальная очередь операций + idempotent API.

## 3. Высокоуровневая архитектура

### 3.1 Клиент (macOS SwiftUI)

- **Presentation layer (SwiftUI)**
  - экраны: Timer, Tasks, Projects, Settings, Sync Status.
  - реактивное обновление состояния через `Observable`/`@StateObject`.
- **Application layer**
  - use-cases: startWork, startBreak, switchTask, completeTask, skipToBreak, updateDurations, syncNow.
- **Domain layer**
  - сущности: TimerSession, TimerState, Task, Project, Settings, SyncOperation.
- **Data layer**
  - локальное хранилище (SwiftData или Core Data);
  - репозитории;
  - sync engine (очередь + отправка + reconciliation).
- **System integration**
  - локальные уведомления;
  - menu bar integration (опционально как v1.1);
  - восстановление состояния после restart приложения.

### 3.2 Backend (Python)

- **REST API** (FastAPI рекомендован):
  - CRUD для tasks/projects/settings;
  - bulk upload событий/операций;
  - endpoint для получения deltas с последнего sync token.
- **PostgreSQL**:
  - пользователи, проекты, задачи, таймер-сессии, события, sync cursors.
- **Sync orchestration**:
  - idempotency keys;
  - версия объектов (`updatedAt`, `version`);
  - soft conflict policy с приоритетом последнего изменения + специализированные правила.

## 4. Доменная модель

## 4.1 Основные сущности

- **Project**
  - `id: UUID`
  - `name: String`
  - `color: String?`
  - `isArchived: Bool`
  - `createdAt, updatedAt, deletedAt?`
- **Task**
  - `id: UUID`
  - `projectId: UUID?` (опционально)
  - `title: String`
  - `notes: String?`
  - `status: enum {todo, inProgress, done}`
  - `estimateMinutes: Int?`
  - `createdAt, updatedAt, completedAt?, deletedAt?`
- **TimerSettings**
  - `workDurationSec: Int`
  - `breakDurationSec: Int`
  - `autoStartNext: Bool` (по умолчанию false)
  - `updatedAt`
- **TimerSession**
  - `id: UUID`
  - `mode: enum {work, break}`
  - `taskId: UUID?` (обычно для work)
  - `plannedDurationSec: Int`
  - `startedAt: DateTime`
  - `endedAt: DateTime?` (закрывается только при явном завершении/переключении)
  - `endedReason: enum {manualStop, switchedMode, switchedTask, appTerminationRecovery}`
  - `createdAt, updatedAt`
- **TimerState (singleton)**
  - `isRunning: Bool`
  - `activeSessionId: UUID?`
  - `activeMode: work|break?`
  - `activeTaskId: UUID?`
  - `startedAt: DateTime?`
  - `plannedDurationSec: Int?`
  - `lastTickAt: DateTime?`
- **TimeEvent** (для аудита и аналитики)
  - `id: UUID`
  - `sessionId: UUID`
  - `type: enum {sessionStarted, thresholdReached, modeSwitched, taskSwitched, sessionEnded}`
  - `payloadJson`
  - `occurredAt`
- **SyncOperation**
  - `id: UUID`
  - `entityType: project|task|session|event|settings`
  - `entityId: UUID`
  - `opType: create|update|delete`
  - `payloadJson`
  - `clientTimestamp`
  - `status: pending|sent|acked|failed`
  - `retryCount`

## 4.2 Вычисляемые поля таймера

На UI таймер вычисляется из `now - startedAt`, а не хранится как mutable счетчик:

- `elapsedSec = now - startedAt`
- `remainingSec = plannedDurationSec - elapsedSec`
- если `remainingSec >= 0`: обычный режим;
- если `remainingSec < 0`: `extraSec = abs(remainingSec)` и отображение `+MM:SS`.

Это обеспечивает корректность после сна системы, перезапуска приложения и лагов рендера.

## 5. Ключевые сценарии

## 5.1 Старт рабочего периода

1. Пользователь выбирает задачу (или запускает без задачи).
2. Создается `TimerSession(mode=work, plannedDurationSec=settings.workDurationSec, startedAt=now)`.
3. Обновляется `TimerState`.
4. Пишется `TimeEvent(sessionStarted)`.
5. В очередь sync добавляются операции create.

## 5.2 Достижение порога времени (конец planned, старт extra-time)

1. Когда `elapsedSec == plannedDurationSec`, UI переключается на индикацию extra-time.
2. Сессия НЕ закрывается.
3. Один раз записывается `TimeEvent(thresholdReached)`.
4. Пользователь сам решает: продолжить, переключиться на break, переключиться на другую задачу.

## 5.3 Переключение задачи "на лету"

1. Текущая work-сессия закрывается `endedReason=switchedTask`.
2. Немедленно открывается новая work-сессия с новой `taskId`.
3. История остается непрерывной и аналитически корректной.

## 5.4 Переход на отдых после extra-time

1. Закрывается текущая work-сессия.
2. Создается break-сессия с `plannedDurationSec=settings.breakDurationSec`.
3. Для break действует тот же принцип extra-time.

## 5.5 Офлайн и восстановление сети

1. Любые изменения фиксируются локально и попадают в `SyncOperation`.
2. При отсутствии сети операции остаются pending.
3. При восстановлении сети `SyncEngine` отправляет batch-ами.
4. После ack обновляется статус и получаются server deltas.
5. Локальная БД обновляется в транзакции.

## 6. Локальное хранение и репозитории

## 6.1 Технология

- **Рекомендация для v1:** SwiftData (нативная интеграция и быстрое прототипирование).
- **Альтернатива:** Core Data при необходимости более тонкого контроля миграций.

## 6.2 Репозитории

- `TaskRepository`
- `ProjectRepository`
- `TimerRepository`
- `SettingsRepository`
- `SyncRepository`

Каждый репозиторий:
- отдает `async` API;
- пишет изменения в локальную БД;
- публикует событие в sync queue.

## 7. Синхронизация (offline-first)

## 7.1 Подход

- **Outbox pattern** на клиенте: все локальные мутации -> outbox.
- **Pull deltas** с сервера: изменения после `lastSyncToken`.
- **Idempotent writes** через `operationId`/`idempotencyKey`.

## 7.2 Разрешение конфликтов

Базовые правила:

1. Для `Task.title/notes/status` - last-write-wins по `updatedAt` (server normalized UTC).
2. Для `Task.completedAt` - если одна сторона поставила done, состояние done не откатывать.
3. Для `TimerSession` - immutable после закрытия (кроме тех.полей sync), чтобы не ломать историю.
4. Soft-delete через `deletedAt`, физическое удаление - серверным GC job.

## 7.3 Sync цикл

1. `pushPendingOperations(limit=100)`
2. `pullDeltas(sinceToken)`
3. `applyDeltasTransactionally()`
4. `updateToken()`
5. Повтор с exponential backoff при ошибках.

## 8. Backend API (черновой контракт)

## 8.1 Auth

- Для MVP: email + password + JWT.
- Для dev-режима: single-user token (feature flag).

## 8.2 Endpoints

- `POST /v1/sync/push`
  - вход: массив операций;
  - выход: ack по каждой операции + server timestamp.
- `GET /v1/sync/pull?since=<token>`
  - выход: изменения + next token.
- `GET/POST/PATCH/DELETE /v1/projects`
- `GET/POST/PATCH/DELETE /v1/tasks`
- `GET/POST/PATCH /v1/settings`
- `GET /v1/reports/daily` (опционально для аналитики)

## 8.3 Python стек

- FastAPI + Pydantic + SQLAlchemy 2.0
- PostgreSQL
- Alembic миграции
- Uvicorn/Gunicorn
- Redis (опционально: rate-limit, background jobs)

## 9. UI/UX структура macOS клиента (SwiftUI)

- `TimerView`
  - крупный таймер, режим (Work/Break), extra-time индикация;
  - текущая задача;
  - кнопки: Start/Pause/Stop, Switch Task, Break Now.
- `TasksView`
  - список задач, фильтры (all/todo/inProgress/done), быстрый старт таймера по задаче.
- `ProjectsView`
  - список проектов, просмотр задач проекта.
- `SettingsView`
  - длительность Work/Break;
  - поведение по окончании периода;
  - sync account + status.
- `SyncStatusView` (или секция в Settings)
  - online/offline, pending operations, last sync.

## 10. Модульная структура клиента

- `App/` (`TimeDriveApp.swift`, DI container)
- `Domain/` (entities, enums, protocols)
- `UseCases/`
- `Data/`
  - `Persistence/`
  - `Repositories/`
  - `Sync/`
  - `Networking/`
- `Features/`
  - `Timer/`
  - `Tasks/`
  - `Projects/`
  - `Settings/`
- `Shared/` (design system, utils, date/time formatters)

## 11. Надежность и edge cases

- Сон MacBook / wake-up: таймер пересчитывается через wall-clock (`Date.now`).
- Краш приложения: на старте проверять `TimerState`, восстанавливать активную сессию.
- Смена timezone: все timestamps хранить в UTC.
- Дубли операций при ретраях: idempotency key на backend.
- Очень длинные extra-сессии: ограничений нет, UI форматирует часы/минуты/секунды.

## 12. Безопасность и приватность

- JWT хранить в Keychain.
- Локальную БД хранить в app container.
- TLS-only для API.
- Логирование без чувствительных пользовательских данных.

## 13. Тестовая стратегия

- **Unit tests**
  - вычисление elapsed/remaining/extra;
  - use-case переходов между режимами;
  - conflict resolution rules.
- **Integration tests**
  - локальная БД + sync queue;
  - push/pull cycle;
  - восстановление после offline.
- **UI tests**
  - запуск work, переход в extra-time, switch task, break.

## 14. Roadmap реализации

## Этап 1 (MVP, локально)

- Таймер Work/Break + extra-time;
- Projects/Tasks CRUD;
- привязка текущей работы к задаче;
- локальная история сессий.

## Этап 2 (Sync)

- Python backend + auth;
- outbox + pull deltas;
- sync status UI.

## Этап 3 (Улучшения)

- аналитика (time per task/project/day);
- menu bar controls;
- локальные smart notifications;
- экспорт отчетов.

## 15. Критерии готовности MVP

- Таймер стабильно работает через сон/пробуждение macOS.
- Extra-time отображается и сохраняется в истории.
- Можно вести задачи с/без проекта.
- Можно в процессе работы сменить задачу или уйти на отдых.
- Приложение полностью функционально без сети.
- После восстановления сети данные синхронизируются без потерь.
