# Mieru — спецификация (источник истины: `hydracore`)

Реализация — `github.com/enfein/mieru/v3` `v3.33.0` (`hydracore/go.mod:19`). Регистрация: `hydracore/include/registry.go:90` (inbound), `:130` (outbound); тип — `mieru` (`hydracore/constant/proxy.go:29`).

Доступность снаружи: mieru разрешён в `safeOutbounds` remote-policy v2, но **отсутствует в `safeInbounds`** — remote-конфиг может задать только outbound (`hydracore/experimental/libbox/hydracore_validation.go:128`).

## 1. Outbound

Схема — `hydracore/option/mieru.go:5-16`, сборка — `hydracore/protocol/mieru/outbound.go:188-249`, валидация — `:251-302`.

| JSON-ключ | Тип | Смысл | Дефолт / обязательность |
|---|---|---|---|
| `server` | string | адрес сервера (`ServerOptions`, `option/outbound.go:183-186`) | обязателен |
| `server_port` | uint16 | одиночный порт | обязателен, если нет `server_ports` |
| `server_ports` | string \| []string | порты-диапазоны `"начало-конец"` (порт-хоппинг) | обязателен, если нет `server_port` |
| `transport` | string enum `TCP`,`UDP` | underlay до сервера | **обязателен, дефолта нет** |
| `username` | string | логин (≤64 байт) | обязателен |
| `password` | string | пароль (≤64 байт) | обязателен |
| `multiplexing` | string enum `MULTIPLEXING_DEFAULT`,`_OFF`,`_LOW`,`_MIDDLE`,`_HIGH` | уровень мультиплексирования | опц.; пусто → DEFAULT = factor 1 (включено), `_OFF` = 0 |
| `traffic_pattern` | string | base64(proto `TrafficPattern`) | опц.; мусор → ошибка старта |
| `mtu` | uint32 | MTU underlay | опц.; `0` → 1400, диапазон [1280,1500] |
| `handshake_mode` | string enum `HANDSHAKE_DEFAULT`,`_STANDARD`,`_NO_WAIT` | `NO_WAIT` — handshake на первой записи | опц. |
| `detour` + `AbstractDialerOptions` | — | `bind_interface`, `connect_timeout`, `tcp_fast_open`, `routing_mark`, `protect_path`, `domain_resolver`, `network_strategy`… (`option/outbound.go:80-105`) | опц. |

Ошибки валидации: `server is empty`, `either server_port or server_ports must be set`, `invalid server_ports format`, `transport must be TCP or UDP`, `username is empty`, `password is empty`, `invalid multiplexing level`, `invalid handshake mode`, `invalid traffic pattern`.

Не поддержано: `hashed_password`, `user_hint`, per-user `quotas`, несколько серверов в одном outbound.

## 2. Inbound (для полноты)

`hydracore/option/mieru.go:18-30`, сборка — `protocol/mieru/inbound.go:265-325`, валидация — `:326-353`.

| Ключ | Тип | Смысл | Дефолт / обязательность |
|---|---|---|---|
| `listen`, `listen_port` | addr, uint16 | адрес/порт (`ListenOptions`, `option/inbound.go:79-94`) | нужен `listen_port` или `listen_ports` |
| `listen_ports` | string \| []string | диапазоны `"начало-конец"` | если нет `listen_port` |
| `users` | `[{name,password}]` | пользователи | обязателен, непустые name/password |
| `transport` | enum `TCP`,`UDP` | протокол прослушивания | обязателен |
| `traffic_pattern` | string | base64(proto) | опц. |
| `user_hint_is_mandatory` | bool | `ServerAdvancedSettings.UserHintIsMandatory` | опц., `false` |
| `mtu` | uint32 | MTU сервера | опц., `0` → 1400 |
| `detour`, `udp_timeout`, `tcp_fast_open`, `reuse_addr`… | — | из `ListenOptions` | опц. |

Мультиплексирования и `handshake_mode` на сервере нет.

## 3. Форматы ссылок

**Своего парсера ссылок у HydraBox2 нет.** В Go-ядре ссылок нет (grep `mieru://` пусто), в Kotlin-парсере подписок — тоже; UI знает mieru лишь как DIAL-capable тип (`core/config/src/commonMain/kotlin/io/hydrabox/core/config/TunnelConfig.kt:501`), отдельной формы полей нет — конфиг задаётся **JSON-объектом outbound** по таблице выше.

Сам mieru умеет две схемы (`pkg/appctl/url.go`):

- `mieru://<base64 std(proto ClientConfig)>` — весь конфиг целиком (`url.go:24-42`). Поле `Dialer` этим API не поддерживается: `Store` вернёт `client profile dialer is not supported by client API` (`apis/client/client.go:67-84`), поэтому такой URL в sing-box outbound без `detour`-обхода не переносится.
- `mierus://<user>:<pass>@host?...` — «simple» ссылка (`url.go:45-100`, разбор `:133-231`).

Маппинг `mierus`-query → поля sing-box outbound:

| query-параметр | → поле | Правило |
|---|---|---|
| userinfo user/pass, host | `username`, `password`, `server` | обязательны |
| `port` (повторяемый) | `server_port` / `server_ports` | одиночное число → `server_port`; диапазон → элемент `server_ports` |
| `protocol` (повторяемый) | `transport` | значения `TCP`/`UDP` совпадают 1:1 |
| `profile` | — | у sing-box нет имени профиля (жёстко `sing-box`) |
| `mtu` | `mtu` | как есть |
| `multiplexing` | `multiplexing` | строки enum совпадают |
| `handshake-mode` | `handshake_mode` | строки `HANDSHAKE_*` совпадают |
| `traffic-pattern` | `traffic_pattern` | тот же base64 |

Число `port` и `protocol` в ссылке обязано совпадать (`url.go:210-212`), но `transport` в sing-box **один на весь outbound** — ссылку со смешанными TCP/UDP портами в один outbound не выразить.

## 4. Особенности и подводные камни

1. **`transport` не дефолтится.** Пустое значение — ошибка, хотя в схеме стоит `omitempty`.
2. **`transport` — это underlay, а не «что проксируем».** Outbound всегда объявляет `tcp+udp`: TCP идёт через stream-соединение, UDP — как UoT (`NewPacketOverStreamTunnel` + `UDPAssociateWrapper`, `outbound.go:105-131`). С `transport: UDP` проксирование TCP всё равно работает.
3. **`server_ports` обязан быть диапазоном.** Разбор — `fmt.Sscanf(portRange, "%d-%d", ...)` (`outbound.go:304-308`), поэтому одиночное `"443"` даёт `invalid server_ports format`; одиночный порт пишется в `server_port`. То же требование к inbound `listen_ports` (у mieru — регексп `^(\d+)-(\d+)$`, `pkg/appctl/appctlcommon/port_binding.go:33`).
4. **Мультиплексирование включено по умолчанию.** Не заданный `multiplexing` → `MULTIPLEXING_DEFAULT` → multiplex factor 1, то есть не выключено (`pkg/appctl/appctlcommon/client.go:158-168`). Отключать надо явно.
5. **Диапазон MTU проверяет mieru, а не sing-box.** `0` → 1400 (`pkg/common/mtu.go:19`); выход за [1280,1500] падает на `Store`/`Start` как `failed to store mieru client config` (`pkg/appctl/appctlcommon/client.go:91-93`).
6. **DOMAIN-сервер резолвится вручную** в `Start` через `dnsRouter` (`outbound.go:59-68`) — в конфиг mieru попадает уже IP; ошибка — `failed to resolve mieru server address`.
7. **Один аккаунт на outbound.** Multi-user — только inbound; name/password ≤64 байт (`appctlcommon/client.go:61-69`).
8. **`traffic_pattern` — base64 protobuf**, не читаемый JSON: вручную не собрать, только взять из `mierus`-ссылки или из вывода `mieru` CLI.
9. **Порт-хоппинг** работает за счёт списка port bindings: клиент расширяет диапазоны в список портов и выбирает endpoint на соединение (`appctlcommon/port_binding.go:36-120`).
10. **DNS в SDK отключён** (`ClientDNSConfig{BypassDialerDNS: true}`, `outbound.go:224-226`) — резолв имён делает sing-box.

**Итог:** одна строка — mieru в HydraBox2 задаётся только JSON-outbound'ом (`server`/`server_port(s)`, `transport`, `username`, `password`, опц. `multiplexing`/`mtu`/`handshake_mode`/`traffic_pattern`), ссылочного парсера ни в ядре, ни в подписках нет; при переносе `mierus://` помнить про диапазон `server_ports` и единый `transport`.
