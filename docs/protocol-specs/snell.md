# Snell — спецификация (источник: `hydracore`)

Форк sing-box. Реализация — `github.com/sagernet/sing-snell` `v0.0.0-20260829071736-20f2eaec77c3`.
Регистрация: `hydracore/include/registry.go:83` (inbound), `:122` (outbound); тип — `snell` (`hydracore/constant/proxy.go:15`).

## 1. Outbound

Схема: `hydracore/option/snell.go:82-93` (`_SnellOutboundOptions` + `AbstractSnellOutboundOptions`), сборка — `hydracore/protocol/snell/outbound.go:52-96`.

Общие поля (обязательны для обеих версий):

| JSON-ключ | Тип | Смысл | Дефолт / обязательность |
|---|---|---|---|
| `server` | string | адрес сервера | обязателен (`option/outbound.go:183-186`) |
| `server_port` | uint16 | порт | обязателен |
| `psk` | string | pre-shared key; пустой → `ErrMissingPSK` | обязателен |
| `version` | int enum `4,6` | поколение клиента | обязателен: `0` → `snell: missing version`, иное → `snell: unsupported version` |
| `userkey` | string | ключ multi-user | опц., ≤255 байт (`snellv4/client.go:46`, `snellv6/client.go:42`) |
| `reuse` | bool | пул/переиспользование сессий | опц., `false` |
| `network` | string/[]string (`tcp`,`udp`) | разрешённые сети | опц.; пусто → `tcp+udp` (`option/types.go:42-47`) |
| `detour` | string | ссылка на другой outbound | опц. (`option/outbound.go:80-81`) |
| + `AbstractDialerOptions` | — | `bind_interface`, `routing_mark`, `connect_timeout`, `tcp_fast_open`, `domain_resolver`, `network_strategy` и др. | опц. |

Только `version: 4` — `SnellObfsClientOptions` (`option/snell.go:135-138`):

| Ключ | Тип | Смысл | Дефолт |
|---|---|---|---|
| `obfs_mode` | enum `none,http,tls` | обфускация | `""` → `none` (`obfs.go:67-77`) |
| `obfs_host` | string | Host для http/tls-обфускации | пусто → `bing.com` (http), `cloudfront.net` (tls) (`obfs.go:31-33,203,333`) |

Только `version: 6` — `SnellV6Options` (`option/snell.go:140-142`):

| Ключ | Тип | Смысл | Дефолт |
|---|---|---|---|
| `mode` | enum `default,unshaped,unsafe-raw` | режим трафика v6 | `""` → `default`; при `default` строится `Profile(psk)` (`snellv6/client.go:56`) |

UDP: `DialContext`/`ListenPacket` всегда поднимают TCP до сервера и навешивают packet-conn (`outbound.go:98-138`).

## 2. Inbound (для полноты)

`option/snell.go:11-24`, `protocol/snell/inbound.go:40-101`. Поля: `listen`, `listen_port`, `psk`, `version` enum **`5,6`**, `users[] {name, userkey}` (опц., multi-user), `obfs_mode` (v5), `mode` (v6). Сервер v5 принимает `none/http/tls`; сервер v6 требует PSK **12..255 байт** (`snellv6/server.go:36-38`).

## 3. Формат ссылки `snell://`

Парсер: `core/subscription/src/commonMain/kotlin/io/hydrabox/core/subscription/SubscriptionParser.kt:70-97,397-433`; рендер в outbound — `ShareLinkOutbound.kt:131-158`. Алиасов нет — только схема `snell` (отдельной записи в `proxySchemes`, `SubscriptionParser.kt:97`).

```
snell://<PSK>@host:port?version=4&obfs=http&obfs-host=cdn.example&udp-relay=true#name
```

userinfo = PSK (URL-decode), разделитель `:` не используется иначе как `username:password` → сырое `:` в PSK обязано быть percent-encoded.

| query-параметр | → поле outbound | Правило |
|---|---|---|
| `version` | `version` | только `4` или `6`; отсутствует/иное → `4` (в т.ч. `version=5` → `4`) |
| `obfs`, `obfs-mode` | `obfs_mode` | оба ключа равнозначны, пустое отбрасывается |
| `obfs-host` | `obfs_host` | пустое отбрасывается |
| `mode` | `mode` | пустое отбрасывается |
| `userkey` | `userkey` | пустое отбрасывается |
| `udp-relay=true` | `network:["tcp","udp"]` | иначе `network` не пишется |
| `type/path/serviceName/host`, `sni/fp/alpn/allowInsecure/insecure/pbk` | `transport` / `tls` | генерируются общей веткой `ShareLinkOutbound.kt:249-330` |

## 4. Особенности и подводные камни

1. **Это не Surge-Snell v1/v2/v3.** Клиент знает только `4` и `6`, сервер — `5` и `6`. Пара поколений: сервер v5 ↔ клиент v4; клиента v5 нет (`option/snell_test.go`).
2. `obfs_mode`/`obfs_host` валидны только при `version:4`, `mode` — только при `version:6`. Вложенный объект `obfs:{...}` отвергается (`json.UnmarshalDisallowUnknownFields` в тесте).
3. `reuse` (мультиплексирование) в ссылке не выражается — его нельзя вытащить из `snell://`.
4. `udp-relay` фактически no-op: `false`/отсутствие даёт тот же `tcp+udp` по дефолту `NetworkList.Build()` (`option/types.go:42-47`); UDP в ссылке не отключается.
5. `transport`/`tls` из ссылки попадают в JSON outbound, но схема snell их не объявляет; базовый `json.Unmarshal` (`option/snell.go:96-114`) игнорирует неизвестные ключи молча — `security=tls` в ссылке не даёт TLS и не даёт ошибки.
6. UI-дескриптор расходится с ядром: `ConfigFieldDescriptors.kt:182` предлагает для `mode` значения `""`, `tcp`, `udp` вместо `default/unshaped/unsafe-raw`.
7. Сервер v6 отклоняет PSK короче 12 байт; клиент — только пустой PSK.
