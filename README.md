# Protonomk для Android/Termux

Установщик [OpenCode v2 для Termux](https://github.com/astreele/opencode-android) с брендингом **Protonomk**: TUI-логотип заменяется на `PROTONOMK`, появляется команда `protonomk`, а провайдер Protonomk настраивается автоматически.

Скрипт ставит нативный Android/aarch64 OpenCode (`opencode2`, ссылка `opencode` → `opencode2`) как источник бинарника, затем создаёт брендированную копию:

- `$PREFIX/bin/protonomk` — лаунчер;
- `$PREFIX/libexec/protonomk/protonomk.bin` — бинарник с патченным логотипом.

Провайдер Protonomk:

| Параметр | Значение |
| --- | --- |
| Base URL | `https://api.protonomk.ru/api/v1` |
| Чат | `POST https://api.protonomk.ru/api/v1/chat/completions` |
| Список моделей | `GET https://api.protonomk.ru/api/v1/models` (справочно) |
| Формат | OpenAI-compatible |
| Пакет OpenCode | `@opencode/ai/providers/openai-compatible` |
| Модель по умолчанию | `protonomk/claude-sonnet-5-5` |

Каталог моделей **вшит в установщик**: установка не обращается к API и не требует ключа. Ключ нужен только для запросов в рантайме.

Бесплатные модели встроены в OpenCode и видны как `opencode/*`; платные модели Protonomk — как `protonomk/*`.

## Установка

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Zibin2004/opencode-Androd-Termux-Protonomk/main/install.sh)
```

Ключ можно передать сразу (иначе провайдер будет читать `PROTONOMK_API_KEY`):

```bash
# переменной окружения
PROTONOMK_API_KEY=sk-... bash <(curl -fsSL https://raw.githubusercontent.com/Zibin2004/opencode-Androd-Termux-Protonomk/main/install.sh)

# или флагом
bash <(curl -fsSL https://raw.githubusercontent.com/Zibin2004/opencode-Androd-Termux-Protonomk/main/install.sh) --protonomk-key sk-...
```

Если ключ не передан, добавь его позже:

```bash
export PROTONOMK_API_KEY=sk-...     # можно прописать в ~/.bashrc
protonomk reload
```

Затем:

```bash
protonomk models --standalone   # 12 бесплатных opencode/* + 27 платных protonomk/*
protonomk                       # TUI, выбор модели через /models
```

## Каталог моделей

Цены — USD за 1M токенов: **кэш (чтение) · вход · выход**. Запись в кэш в тарифах не указана, поэтому в конфиге стоит `0`.

| Модель | Кэш | Вход | Выход |
| --- | ---: | ---: | ---: |
| `claude-fable-5` | 0.525 | 5.25 | 26.25 |
| `claude-fable-5-1` | 0.131 | 5.25 | 26.25 |
| `claude-fable-5-1-amazon` | 0.000 | 2.73 | 13.23 |
| `claude-fable-5-2` | 0.000 | 4.20 | 21.00 |
| `claude-haiku-5-5` | 0.005 | 0.05 | 0.26 |
| `claude-opus-4-6` | 0.262 | 2.62 | 13.12 |
| `claude-opus-5-5` | 0.105 | 2.10 | 10.50 |
| `claude-opus-5-5-amazon` | 0.000 | 1.05 | 5.25 |
| `claude-sonnet-5-5` | 0.052 | 1.05 | 5.25 |
| `claude-sonnet-5-5-amazon` | 0.000 | 0.52 | 2.73 |
| `deepseek-v4.1-flash-1017` | 0.007 | 1.13 | 10.50 |
| `deepseek-v4.1-flash-1017-uncensored-special` | 0.000 | 1.45 | 6.09 |
| `deepseek-v4.1-flash-uncensored` | 0.000 | 0.84 | 3.32 |
| `gemini-3.8-flash` | 0.036 | 0.36 | 1.78 |
| `gemini-4-argon` | 0.046 | 0.94 | 4.62 |
| `glm-5.3-flash` | 0.032 | 0.16 | 0.52 |
| `glm-5.3-flash-uncensored` | 0.420 | 1.05 | 4.20 |
| `gpt-6-astra` | 0.420 | 3.15 | 15.75 |
| `gpt-6-luna` | 0.004 | 0.03 | 0.16 |
| `gpt-6-sol` | 0.084 | 0.63 | 3.15 |
| `gpt-6.1-sol` | 0.042 | 0.63 | 3.15 |
| `gpt-6.1-terra` | 0.000 | 0.32 | 1.58 |
| `kimi-k3.1-pro` | 0.252 | 2.52 | 13.23 |
| `mimo-v26-flash-abl` | 0.000 | 2.00 | 6.09 |
| `mimo-v26-flash-unc` | 0.000 | 1.85 | 6.09 |
| `minimax-m3.1-flash` | 0.000 | 0.16 | 0.63 |
| `qwen38-uncensored-ultraspeed` | 0.000 | 3.36 | 10.50 |

Модели `gpt-image-2.5-*` / `gpt-image-2.6-*` (отмечены ⏳) не включены: это генерация изображений, а не чат.

Лимиты контекста в каталоге не указаны, поэтому OpenCode использует значения по умолчанию (`200000` / `32000`). Если нужны точные — добавь `limit` в `~/.config/opencode/opencode.json`.

## Что делает установщик

1. Ставит OpenCode v2 из подписанного APT-репозитория `astreele/opencode-android` (или из release-zip с проверкой `SHA256SUMS` при `--zip`).
2. Копирует бинарник в `$PREFIX/libexec/protonomk/protonomk.bin` и патчит встроенный TUI-логотип `opencode` → `PROTONOMK`. Патч работает по UTF-16LE-строкам байткода Bun, длина строк не меняется, поэтому оффсеты не сдвигаются. Если upstream изменит логотип, патч аккуратно пропускается.
3. Создаёт лаунчер `$PREFIX/bin/protonomk` (тот же `LD_LIBRARY_PATH` и `OPENCODE_DISABLE_FFF=1`, что и у штатного `opencode2`), а также брендирует вывод `protonomk --help` / `--version`.
4. Создаёт/дополняет `~/.config/opencode/opencode.json`: провайдер `protonomk`, 27 моделей с ценами, `model` по умолчанию — `protonomk/claude-sonnet-5-5`.
5. Сохраняет существующий конфиг: слияние через `jq`, бэкап `opencode.json.bak`, остальные настройки не затрагиваются. JSONC с комментариями не перезаписывается — скрипт печатает готовый блок для ручной вставки.
6. Если передан ключ, конфиг получает права `600`. Без ключа используется `PROTONOMK_API_KEY` из окружения.

Пример итогового блока:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "providers": {
    "protonomk": {
      "name": "Protonomk",
      "env": ["PROTONOMK_API_KEY"],
      "package": "@opencode/ai/providers/openai-compatible",
      "settings": { "baseURL": "https://api.protonomk.ru/api/v1" },
      "models": {
        "claude-sonnet-5-5": {
          "name": "claude-sonnet-5-5",
          "family": "claude",
          "cost": { "input": 1.05, "output": 5.25, "cache": { "read": 0.052, "write": 0 } },
          "capabilities": { "tools": true, "input": ["text"], "output": ["text"] }
        }
        // ... остальные 26 моделей
      }
    }
  },
  "model": "protonomk/claude-sonnet-5-5"
}
```

## Опции установщика

| Опция | Действие |
| --- | --- |
| `--protonomk-key KEY` | API-ключ Protonomk (также `PROTONOMK_API_KEY`). |
| `--no-protonomk` | Поставить OpenCode без настройки провайдера. |
| `--no-logo` | Не патчить TUI-логотип (оставить upstream `opencode`). |
| `--cmd opencode` | Установить upstream-команду `opencode` (zip-путь, без `opencode2`). |
| `--cmd opencode2` | По умолчанию: upstream `opencode2` + ссылка `opencode` → `opencode2`. |
| `--no-link` | Не трогать существующий `$PREFIX/bin/opencode` (zip-путь). |
| `--force` | Заменить чужой `opencode` (например, v1). |
| `--apt` | Ставить upstream через пакетный менеджер (по умолчанию). |
| `--zip` | Скачать release-zip напрямую и проверить по `SHA256SUMS`. |
| `--no-verify` | (zip) Пропустить проверку контрольной суммы — только в крайнем случае. |

`protonomk` создаётся всегда (кроме случая, когда upstream-бинарник не найден).

Переменные окружения: `OPENCODE_CMD`, `OPENCODE_FORCE=1`, `PROTONOMK_API_KEY`, `PROTONOMK_BASE_URL` (по умолчанию `https://api.protonomk.ru/api/v1`).

## Проверка API вручную

```bash
KEY=sk-...

# список моделей
curl -s https://api.protonomk.ru/api/v1/models \
  -H "Authorization: Bearer $KEY"

# чат
curl -s https://api.protonomk.ru/api/v1/chat/completions \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"claude-sonnet-5-5","messages":[{"role":"user","content":"ping"}]}'
```

## Обновление

```bash
pkg upgrade                  # обновляет upstream OpenCode
```

После `pkg upgrade` перезапусти `install.sh`, чтобы обновить и заново пропатчить брендированную копию в `$PREFIX/libexec/protonomk/protonomk.bin`. Повторный запуск также перезаписывает блок `providers.protonomk` (каталог моделей и цены), сохраняя остальной конфиг.

Чтобы изменить каталог/цены — правь `PROTONOMK_MODELS` в `install.sh` или блок `providers.protonomk` в `~/.config/opencode/opencode.json`.

## Удаление

```bash
# брендированный лаунчер и его копия бинарника
rm -f  "$PREFIX/bin/protonomk"
rm -rf "$PREFIX/libexec/protonomk"

# upstream-пакет (если он больше не нужен)
pkg uninstall opencode2
```

Провайдер из конфига удаляется вручную из `~/.config/opencode/opencode.json`.

## Примечания

- Это форк установщика [astreele/opencode-android](https://github.com/astreele/opencode-android) (MIT). Исходный бинарник берётся из оригинального APT-репозитория/релизов; для `protonomk` создаётся копия, в которой патчится только встроенный TUI-логотип. Пересборка OpenCode не требуется.
- Патчится именно UTF-16LE-строка в байткоде Bun, а не `\uXXXX`-копия в исходнике: TUI исполняет байткод, поэтому правка исходных строк не видна. Длина каждой строки сохраняется (19 code units), так что оффсеты и остальные строки не страдают.
- Полностью ребрендится логотип и команда (`protonomk`, `--help`, `--version`). Служебные строки вроде заголовка терминала и статус-бара всё ещё могут показывать `OpenCode`: они используют общие строки байткода, и их замена требует более глубокого форка.
- Нужен нативный Termux (не proot), Android 10+, `aarch64`, ~700 МБ свободно: upstream-бинарник и его брендированная копия лежат отдельно.
- Требуется сетевой доступ к `api.protonomk.ru` во время работы и к репозиторию установщика во время установки.
- Ключ, переданный установщику, хранится в `~/.config/opencode/opencode.json` (права `600`). Если это нежелательно — не передавайте ключ, а экспортируйте `PROTONOMK_API_KEY` в окружении.

## Публикация (для мейнтейнера)

В репозитории лежит `publish.sh` — загрузка файлов через GitHub REST API:

```bash
GITHUB_TOKEN=github_pat_... ./publish.sh          # install.sh README.md LICENSE
```

Токен должен быть fine-grained PAT с правом **Contents: Read and write** на этот репозиторий.

## Лицензия

MIT — см. [LICENSE](LICENSE). Оригинальный установщик: © 2026 astreele.
