# VLESS — спецификация (HydraBox2)

Источник истины — код ядра `D:\dev\HydraBox2\hydracore` (форк sing-box, HEAD `842901466`).
Всё, что ниже, сверено построчно с указанными файлами.

## 1. Схема outbound

Регистрация: `protocol/vless/outbound.go` → `C.TypeVLESS` (`constant/proxy.go`).
Структура: `option/vless.go:VLESSOutboundOptions` (вложенные `DialerOptions`, `ServerOptions`).

| JSON-ключ | Тип | Смысл | Обяз./дефолт |
|---|---|---|---|
| `type` | string | `"vless"` | обязателен |
| `tag` | string | имя outbound | — |
| `server` | string | хост/домен | обязателен |
| `server_port` | uint16 | порт | обязателен |
| `uuid` | string | VLESS UUID (user id) | обязателен |
| `flow` | string | `xtls-rprx-vision`; при `multiplex.enabled=true` принудительно очищается (`outbound.go:88`) | пусто |
| `encryption` | string | строка пост-квантовой обфускации, см. §3; `""`/`none` = выкл (`protocol/vless/client.go:38`) | пусто |
| `network` | string\|[]string | `tcp`/`udp` (`option/types.go:NetworkList`) | — |
| `packet_encoding` | *string | `""`→xudp; `packetaddr`; `xudp` (`outbound.go:77`) | xudp |
| `transport` | object | см. таблицу ниже | нет |
| `tls` | object | см. TLS | нет |
| `multiplex` | object | см. mux | нет |
| dial-поля | — | `detour`, `bind_interface`, `inet4/6_bind_address`, `bind_address_no_port`, `protect_path`, `routing_mark`, `reuse_addr`, `netns`, `connect_timeout`, `tcp_fast_open`, `tcp_multi_path`, `disable_tcp_keep_alive`, `tcp_keep_alive`, `udp_fragment`, `domain_resolver`, `network_strategy` (`option/outbound.go:DialerOptions`) | — |

### TLS (`tls`) — `option/tls.go:OutboundTLSOptions`

| Ключ | Тип | Смысл | Дефолт |
|---|---|---|---|
| `enabled` | bool | вкл. TLS | false |
| `server_name` | string | SNI | — |
| `insecure` | bool | не проверять сертификат | false |
| `alpn` | []string | ALPN | — |
| `min_version`/`max_version` | string | `1.0..1.3` | — |
| `cipher_suites`, `curve_preferences` | []string | — | — |
| `certificate`/`certificate_path`, `certificate_public_key_sha256` | []string/string | пиннинг сервера | — |
| `client_certificate(_path)`, `client_key(_path)` | []string | mTLS | — |
| `fragment`/`record_fragment`/`fragment_fallback_delay`, `spoof`/`spoof_method` | bool/string/duration | TLS-фрагментация и спуфинг | — |
| `kernel_tx`/`kernel_rx`, `handshake_timeout`, `engine`, `disable_sni` | — | kTLS и прочее | — |
| `ech.enabled/config/config_path/query_server_name` | — | ECH (`OutboundECHOptions`) | — |
| `utls.enabled/fingerprint` | — | enum: chrome,firefox,edge,safari,360,qq,ios,android,random,randomized,chrome_psk,chrome_pq… | — |
| `reality.enabled/public_key/short_id/spider_x/support_x25519mlkem768` | — | REALITY (`OutboundRealityOptions`) | — |

### Transport (`transport`) — `option/v2ray_transport.go`

Дискриминатор `type`: `http`, `ws`, `quic`, `grpc`, `httpupgrade`, `xhttp`, `mkcp`.

| type | ключи |
|---|---|
| `http` | `host` []string, `path`, `method`, `headers`, `idle_timeout`, `ping_timeout` |
| `ws` | `path`, `headers` (в т.ч. Host), `max_early_data`, `early_data_header_name` |
| `grpc` | `service_name`, `idle_timeout`, `ping_timeout`, `permit_without_stream` |
| `httpupgrade` | `host`, `path`, `headers` |
| `quic`/`mkcp` | `mkcp`: `header_type`, `seed` (clash-путь) |
| `xhttp` | `mode`, `host`, `path`, `headers`, `domain_strategy`, `x_padding_bytes` (**обязателен, `<=0` → ошибка**; runtime-дефолт `100-1000`), `no_grpc_header`, `no_sse_header`, `sc_max_each_post_bytes` (деф. 1e6), `sc_min_posts_interval_ms` (30), `sc_max_buffered_posts` (30), `sc_stream_up_server_secs` (20-80), `server_max_header_bytes`, `trusted_x_forwarded_for`, `x_padding_obfs_mode/_key/_header/_placement/_method`, `uplink_http_method` (POST; GET только `packet-up`), `session_placement`/`_key` (path), `seq_placement`/`_key` (path), `uplink_data_placement` (`auto`; cookie/header только `packet-up`), `uplink_data_key`, `uplink_chunk_size`, `session_id_table`, `session_id_length`, `congestion_controller`, `cwnd`, `xmux`, `download{…,server,detour,tls}` |

`mode`: `auto` (деф.) / `packet-up` / `stream-up` / `stream-one`, иное → ошибка (`v2ray_transport.go:UnmarshalJSON`).
`xmux`: `max_concurrency`, `max_connections`, `c_max_reuse_times`, `h_max_request_times`, `h_max_reusable_secs`, `h_keep_alive_period`; если `xmux` не задан — `max_concurrency 1-1`, `h_max_request_times 600-900`, `h_max_reusable_secs 1800-3000`; `max_connections` и `max_concurrency` вместе запрещены.

### Multiplex (`multiplex`) — `option/multiplex.go`

`enabled`, `protocol` (`h2mux|smux|yamux`), `max_connections`, `min_streams`, `max_streams`, `padding`, `brutal{enabled,up_mbps,down_mbps}`.

### Inbound (для полноты) — `option/vless.go:VLESSInboundOptions`

`users[]{name,uuid,flow}`, `decryption`, `tls`, `transport`, `multiplex` (+ `ListenOptions`). `decryption != ""/"none"` → `parseServerDecryption` (`protocol/vless/inbound.go:269`).

## 2. Формат ссылки `vless://`

Ядро: `parser/link/vless.go` (`parseVLESSLink`), хелперы `parser/link/utils.go`, диспетчер `parser/link/parser.go`. `uuid` = userinfo, `server`/`port` = host, `tag` = fragment, `server_name` по умолчанию = host.

| query | Маппинг в outbound | Замечание |
|---|---|---|
| `type` | `transport.type` | `ws`→ws, `http`→http (host через запятую→`host[]`, path), `grpc`→grpc(`serviceName`), `xhttp`→xhttp(+принудительный `alpn=h2,http/1.1`, `host`, `path`, `mode`, `extra`); прочие значения игнорируются |
| `security` | `tls.enabled` | `tls`→enabled; `reality`→enabled+`reality.enabled`; `xtls` не обрабатывается |
| `insecure`, `skip-cert-verify` | `tls.insecure` | только `1`/`true` |
| `sni`, `peer`, `serviceName` | `tls.server_name` | проверка ключа идёт по всем трём |
| `alpn` | `tls.alpn` | split `,` |
| `fp` | `tls.utls{enabled,fingerprint}` | |
| `flow` | `flow` | берётся только `xtls-rprx-vision` |
| `pbk` | `tls.reality.public_key` | |
| `sid` | `tls.reality.short_id` | `spx`/`spider_x`, `ech` **не парсятся** |
| `tfo`, `tcp-fast-open`, `tcp_fast_open` | `tcp_fast_open` | |
| `host`, `path` | ws: Host-заголовок + path (в `path` разбирается суффикс `?ed=N` → `max_early_data`, `early_data_header_name`); http: `host[]`, `path` | |
| `extra` | xhttp-настройки | base64url-safe JSON (`common.DecodeBase64URLSafe`, `common/utils.go:59`), затем `common.ParseXHTTPRange` |

`extra` в Go-парсере читает лишь: `xmux{cMaxReuseTimes,maxConcurrency,maxConnections,hKeepAlivePeriod,hMaxRequestTimes,hMaxReusableSecs}`, `noGRPCHeader`, `xPaddingBytes`, `scMaxEachPostBytes`, `scMinPostsIntervalMs`, `scStreamUpServerSecs`. Прочие ключи молча отбрасываются.

**Приложение (Kotlin, не ядро).** `core/subscription/.../ShareLinkOutbound.kt` строит JSON сам и полнее Go-парсера: `encryption` (кроме `none`) → `encryption`; `type=xhttp|splithttp` → `mode` (деф. `auto`), `x_padding_bytes=100-1000` если нет `extra`, `extra` переводится из camelCase Xray (`xPaddingBytes`, `scStreamUpServerSecs`, `xmux`) в snake_case; `kcp|mkcp` → `header_type`+`seed`; `type=ws` — `path`, `ed`, Host; `grpc` — `service_name` (из `serviceName` или `path`); `http|h2|h3` — `host[]`, `path`, `method`; `httpupgrade` — `path`, `host`; TLS — `sni`/`host`/server, `fp`, `alpn`, `allowInsecure|insecure`, `pbk`+`sid`; `flow` (любой). `spx`, `packet_encoding`, `ech` не поддержаны и здесь.

## 3. Особенности форка

**Пакет `protocol/vless/encryption`** (post-quantum VLESS, Xray-совместимый).

Клиент (`encryption/client.go:parseEncryption`): строка вида
`mlkem768x25519plus.<xor>.<rtt>.[<padding>.]<key>[.<key>…]`
- `xor` ∈ `native|xorpub|random`;
- `rtt` ∈ `1rtt|0rtt` (0rtt = `zeroRTT`);
- padding-сегменты (до 16) идут **до** ключей, каждый — `procent-min-max` (`100-111-1119`, далее чередование длин/пауз); первый обязан быть `100-<min>-<max>`, min ≥ `minPaddingLength`. Опциональны.
- ключи: base64 RawURL, каждый 32 байта (X25519) или 1184 (ML-KEM-768); всего 1..8 штук.
Ошибка на неподдерживаемой схеме/префиксе. Задаётся полем `encryption` outbound. При включённом шифровании Vision работает поверх аутентифицированного record-слоя, splicing отключён (`protocol/vless/client.go`).

Сервер: `decryption` с тем же префиксом `mlkem768x25519plus.<native|xorpub|random>.<from[-to]s>.<padding>.<key>…` (`protocol/vless/inbound.go:parseServerDecryption`).

**xhttp-специфика форка**: `mode=packet-up` — единственный, где разрешены `uplink_http_method=GET`, `uplink_data_placement=cookie|header`; `sc_max_each_post_bytes>0` не требуется только для `stream-one`/`stream-up`; `x_padding_bytes` обязателен всегда.

Пропущено: `hydracore` не парсит из ссылки `encryption`, `spx`, `ech`, `packet_encoding`, `kcp` — эти параметры работают только при задании их в JSON напрямую (или через Kotlin-маппер для `encryption`/`kcp`).
