# ANYTLS — спецификация (источник истины: `hydracore`)

Ядро: форк sing-box-extended (`hydracore`, baseline 1.14.1). Reference: `github.com/anytls/sing-anytls v0.0.11`.

## 1. Outbound

Схема опций — `hydracore/option/anytls.go` (`AnyTLSOutboundOptions`), сборка — `hydracore/protocol/anytls/outbound.go` (`NewOutbound`).

| JSON-ключ | Тип | Смысл | Дефолт | Обяз. |
|---|---|---|---|---|
| `type` | string | `"anytls"` (`constant/proxy.go:30`) | — | да |
| `tag` | string | имя outbound | — | нет |
| `server` | string | хост/IP (`ServerOptions`, `option/outbound.go:183`) | — | да |
| `server_port` | uint16 | порт | — | да |
| `password` | string | пароль AnyTLS; из него SHA-256 в `anytls.NewClient` | — | да по смыслу: схема не валидирует (`omitempty`), но без пароля handshake не пройдёт |
| `idle_session_check_interval` | duration (`"30s"`) | период проверки простаивающих сессий | 30s | нет |
| `idle_session_timeout` | duration | таймаут простоя сессии | 30s | нет |
| `min_idle_session` | int | минимум держимых idle-сессий | 0 | нет |
| `disable_reuse` | bool | заявлено как отключение переиспользования | false | нет — **мёртвое поле**, см. §4 |
| `client_metadata` | string | подмена строки `client=` в settings-кадре AnyTLS | `""` (кадр не переписывается) | нет |
| `tls` | object | подблок TLS (обязателен: без `enabled:true` — ошибка `ErrTLSRequired`) | — | да |

Дефолты 30s живут в библиотеке, не в опциях: `session.NewClient` поднимает значение до `30s`, если оно `<= 5s` (`sing-anytls@v0.0.11/session/client.go:52-57`), поэтому 0 и любое `<=5s` дают 30s.

### TLS-подблок

`OutboundTLSOptionsContainer` → `option/tls.go:107` (`OutboundTLSOptions`), читается `tls.NewClient` с `options.Server`.

| Ключ | Тип | Смысл / дефолт |
|---|---|---|
| `enabled` | bool | обязателен `true`; иначе outbound не создаётся |
| `server_name` | string | SNI; по умолчанию — `server` |
| `disable_sni` | bool | не отправлять SNI, дефолт false |
| `insecure` | bool | не проверять сертификат, дефолт false |
| `alpn` | []string | пример: `["h2","http/1.1"]` |
| `min_version`/`max_version` | string | `1.0…1.3` |
| `cipher_suites`, `curve_preferences` | []string | P256/P384/P521/X25519/X25519MLKEM768 |
| `certificate`, `certificate_path`, `certificate_public_key_sha256` | list/string | pinning |
| `client_certificate(_path)`, `client_key(_path)` | list/string | mTLS |
| `fragment`, `fragment_fallback_delay`, `record_fragment` | bool/duration | фрагментация ClientHello |
| `spoof`, `spoof_method`, `kernel_tx`, `kernel_rx`, `engine`, `handshake_timeout` | — | см. `option/tls.go` |
| `ech` | object | `enabled`, `config`, `config_path`, `query_server_name` |
| `utls` | object | `enabled`, `fingerprint` (`chrome`, `firefox`, `random`, `randomized`, …) |
| `reality` | object | `enabled`, `public_key`, `short_id`, `spider_x`, `support_x25519mlkem768` |

Диалект-опции (`AbstractDialerOptions`, `option/outbound.go:85`): `detour`, `bind_interface`, `inet4/6_bind_address`, `bind_address_no_port`, `protect_path`, `routing_mark`, `reuse_addr`, `netns`, `connect_timeout`, `tcp_fast_open`, `tcp_multi_path`, `disable_tcp_keep_alive`, `tcp_keep_alive(_interval)`, `udp_fragment`, `domain_resolver`, `network_strategy`, `network_type`, `fallback_network_type`, `fallback_delay`. `tcp_fast_open: true` **отвергается** для anytls (см. §4).

Clash-диалект: `hydracore/parser/clash/anytls.go` — `password`, `udp`, `idle-session-check-interval`, `idle-session-timeout`, `min-idle-session` (int, секунды) + inline `DialerOptions`/`ServerOptions`/`TLSOptions`.

## 2. Формат ссылки `anytls://`

Схема зарегистрирована в `hydracore/parser/link/parser.go:31` → `parseAnyTLSLink` (`hydracore/parser/link/anytls.go`).

`anytls://<password>@<host>:<port>?<query>#<tag>`

| Элемент ссылки | Поле outbound |
|---|---|
| userinfo (username) | `password`; пустой/отсутствующий → ошибка `missing password` |
| host | `server` и (по умолчанию) `tls.server_name` |
| port | `server_port` через `StringToType[uint16]`; при отсутствии порта → `0` |
| fragment | `tag` |
| `sni` | `tls.server_name` |
| `insecure` | `tls.insecure`; только `"1"` или `"true"` |
| `alpn` | `tls.alpn` (split по `,`, без trim) |
| `fp` | `tls.utls.enabled=true`, `tls.utls.fingerprint` |
| `tfo` / `tcp-fast-open` / `tcp_fast_open` | `tcp_fast_open`; только `"1"`/`"true"` — но валидного outbound не даст: ядро его отвергнет |

Всё остальное в query молча игнорируется. TLS-подблок всегда создаётся с `enabled:true`, `ech/utls/reality` — пустыми структурами. Обратной сериализации ссылок в ядре нет.

Приложение (`core/subscription/src/commonMain/kotlin/io/hydrabox/core/subscription/ShareLinkOutbound.kt:249`) строит `tls` из `sni`/`host`, `fp`, `alpn` (с trim), `insecure`/`allowInsecure`, `pbk`+`sid`; пароль для `anytls` берётся из `password ?: username` (строка 127).

## 3. Inbound (для полноты)

`option/anytls.go` → `AnyTLSInboundOptions`: inline `ListenOptions` + `InboundTLSOptionsContainer`, `users[] {name, password}`, `padding_scheme[]` (склейка через `\n`, дефолт — `padding.DefaultPaddingScheme` из библиотеки), реализация `hydracore/protocol/anytls/inbound.go`.

## 4. Особенности форка

- `client_metadata` (не в upstream sing-box): `hydracore/protocol/anytls/client_metadata.go` через `unsafe` + `reflect` по именам полей `anytls.Client.sessionClient`, `session.Stream.sess`, `session.Session.connLock/buffer` переписывает строку `client=` в кадре `commandSettings` (4). Приватные поля — любое переименование в библиотеке тихо ломает фичу (`FieldByName` не найден → offset 0 → порча памяти).
- `disable_reuse` добавлен вместе с апгрейдом `sing-anytls` до v0.0.13 (`ba3e2d132`), но `go.mod:11` держит **v0.0.11**, где такого поля в `ClientConfig` нет, и код outbound его не читает. JSON принимается, эффекта нет.
- `tcp_fast_open: true` для anytls — жёсткая ошибка `NewOutbound`: TFO создаёт lazy-соединение до первого write, а anytls-хендшейк читает remote address и падал бы nil-деref. App-сторона дополнительно исключает anytls из `fastOpenCapableTypes` (`core/config/.../TunnelConfig.kt:532`), чтобы отказ одного сервера не валил документ.
- Remote policy v2 (`hydracore/experimental/libbox/hydracore_validation.go:129`): `anytls` в allowlist `safeOutbounds`; локальные поля (`detour`, `bind_interface`, `netns` и т.п.) в удалённой конфигурации отвергаются.
- UDP — только UoT (`uotClient`); `ListenPacket` через UoT, TCP — `session.CreateStream` + Socksaddr.
