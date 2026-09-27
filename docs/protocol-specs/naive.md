# Naive — спецификация (источник истины: `hydracore`)

Ядро: форк sing-box-extended (`hydracore`, baseline 1.14.1). Outbound компилируется только с тегом `with_naive_outbound` (`hydracore/include/naive_outbound.go`), без него — заглушка `include/naive_outbound_stub.go`. Клиент — не Go, а cronet/NaiveProxy (`github.com/sagernet/cronet-go`, `naive_client.go`).

## 1. Outbound

Опции — `hydracore/option/naive.go:17` (`NaiveOutboundOptions`), сборка — `hydracore/protocol/naive/outbound.go:44` (`NewOutbound`). Тип: `"naive"` (`constant/proxy.go:19`).

| JSON-ключ | Тип | Смысл | Дефолт | Обяз. |
|---|---|---|---|---|
| `type` | string | `"naive"` | — | да |
| `tag` | string | имя outbound | — | нет |
| `server` | string | хост/IP (`ServerOptions`, `option/outbound.go:183`) | — | да |
| `server_port` | uint16 | порт | — | да |
| `username` | string | логин; с `password` даёт заголовок `Authorization: Basic` | `""` — заголовка нет | да по смыслу (схема не валидирует) |
| `password` | string | пароль для того же заголовка | `""` | да по смыслу |
| `insecure_concurrency` | int | N>1: N независимых cronet-движков, round-robin + заголовок `-network-isolation-key: https://pool-i:443`; сервер должен иметь то же значение | <1 → 1 (`naive_client.go:131`) | нет |
| `extra_headers` | object | доп. HTTP-заголовки (берётся первое значение ключа) | пусто | нет |
| `stream_receive_window` | MemoryBytes | окно потока h2 (при `quic:false`) или потока QUIC | 128 MiB, 4 MiB на iOS; при `quic:true` — 6 MiB (`naive_client.go:396`) | нет |
| `quic` | bool | `true` — HTTP/3 (QUIC), `false` — HTTP/2 | false | нет |
| `quic_congestion_control` | string | `bbr\|bbr2\|cubic\|reno` | `""` → default cronet | нет |
| `quic_session_receive_window` | MemoryBytes | окно QUIC-сессии | 15 MiB | нет |
| `udp_over_tcp` | bool\|object | `enabled`,`version` (`1\|2`) — единственный путь UDP | disabled | нет |
| `tls` | object | подблок TLS; без `enabled:true` — `ErrTLSRequired` | — | да |
| `detour`, `bind_interface`, `inet4/6_bind_address`, `routing_mark`, `netns`, `connect_timeout`, `tcp_fast_open`, `tcp_multi_path`, `tcp_keep_alive*`, `udp_fragment`, `domain_resolver`, `domain_strategy`… | — | `DialerOptions` (`option/outbound.go:80`) | — | нет |

Поля `network` у outbound **нет** (оно есть только у inbound, `option/naive.go:9`): HTTP/2 или QUIC выбирает булев `quic`.

### TLS-подблок

`OutboundTLSOptionsContainer` → `option/tls.go:107`. Эффективны толькo: `enabled`, `server_name` (пусто → строка адреса сервера, `outbound.go:81`), `certificate`/`certificate_path` → `TrustedRootCertificates`, `ech.{enabled,config,config_path,query_server_name}`.

`NewOutbound` (`outbound.go:45-80`) **отвергает с ошибкой**: `disable_sni`, `insecure`, `alpn`, `min_version`, `max_version`, `cipher_suites`, `curve_preferences`, `client_certificate(_path)`, `client_key(_path)`, `fragment`, `record_fragment`, `kernel_tx/rx`, `utls.enabled`, `reality.enabled`. Молча игнорируются: `engine`, `spoof`, `handshake_timeout`, `certificate_public_key_sha256`. ALPN задаёт сам cronet (h2 / h3).

## 2. UDP

Без `udp_over_tcp.enabled` outbound объявляет только `tcp`, а UDP-запрос даёт `UDP is not supported unless UDP over TCP is enabled` (`outbound.go:236`). При включении добавляется `udp` и клиент UoT.

## 3. Форматы ссылок

Схемы: `naive+https://`, `naive+quic://`. Разбор — клиентский, в ядре парсера нет (`hydracore/parser/link/*` naive не знает).

Разбор: `core/subscription/src/commonMain/kotlin/io/hydrabox/core/subscription/SubscriptionParser.kt:93,416` — userinfo режется по `:` на username/password, `type = "naive"`. Сборка outbound: `ShareLinkOutbound.kt` (ветка `else` для типа `naive`).

| Элемент ссылки | Поле outbound |
|---|---|
| `user:pass@` | `username`, `password` |
| `#фрагмент` | `tag`/label |
| `sni`, `host` | `tls.server_name` (иначе домен ссылки) |
| `security=tls`, `tls=1` | `tls.enabled` (для `naive+https` уже включено) |
| `allowInsecure=1`, `insecure=1` | `tls.insecure` — **ядро отвергает** |
| `alpn` | `tls.alpn` — **ядро отвергает** |
| `fp` | `tls.utls` — **ядро отвергает** |
| `pbk`, `sid` | `tls.reality` — **ядро отвергает** |
| `type=ws/googlegrpc/http/h3/xhttp/quic…` | `transport` — **поля нет у naive**, а JSON разбирается строго → ошибка конфига |
| `quic_congestion_control`, `stream_receive_window`, `extra_headers`, `udp_over_tcp` | нет маппинга — только руками |

## 4. Особенности

- `naive+quic` **не** ставит `quic:true` и не включает TLS (схема не в списке «secured», `SubscriptionParser.kt:428`): получится h2-outbound без `tls`, и ядро ответит `TLS required`. Для QUIC нужны `?security=tls` **и** ручной `quic: true`.
- `tls` в ссылке выводится из схемы только для `naive+https`; `naive+quic` без query остаётся без TLS.
- Генератор конфига (`core/config/.../TunnelConfig.kt:495`) применяет к naive `tcp_fast_open`/`tcp_multi_path`; фрагментация TLS — нет (naive не в `tlsFragmentCapableTypes`, а ядро её и отвергает).
- Валидатор удалённых конфигов (policy v2) разрешает тип `naive` (`experimental/libbox/hydracore_validation.go:128`).
- UI-схема помечает `username`/`password` обязательными (`ui/app/.../ConfigFieldDescriptors.kt:186`).
- Тесты: ядро — `hydracore/test/naive_test.go` (docker NaiveProxy+nginx), приложение — `SubscriptionTest.kt:38`.
