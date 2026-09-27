# HYSTERIA v1 / v2 — спецификация (источник истины: `hydracore`)

Ядро: форк sing-box-extended 1.14.1 (`gr33nimax/hydracore`). Схема — `hydracore/option/hysteria.go`, `option/hysteria2.go`; сборка outbound — `protocol/hysteria/outbound.go`, `protocol/hysteria2/outbound.go`; общие QUIC-поля — `option/http.go:14-26`; TLS — `option/tls.go:107`.
QUIC-путь существует только при сборке с `-tags with_quic` (`include/quic.go`, `RegisterOutbound` в обоих пакетах). Без тега тип не зарегистрирован → `unknown outbound type`.

## 1. Outbound `hysteria` (v1)

`option.HysteriaOutboundOptions` (`option/hysteria.go:36-62`).

| JSON-ключ | Тип | Смысл | Дефолт | Обяз. |
|---|---|---|---|---|
| `server` | string | хост/IP (`ServerOptions`, `option/outbound.go:183`) | — | да |
| `server_port` | uint16 | порт | — | да (0 = невалидно) |
| `server_ports` | []string | список портов, напр. `"20000:30000"` — port hopping | — | нет |
| `hop_interval` | duration | период смены порта; действует только с `server_ports` | 30s (`sing-quic/hysteria/hop.go:20`) | нет |
| `up` / `down` | string (byteformat) | скорость в байтах/с, напр. `"100 Mbps"` | 0 | нет |
| `up_mbps` / `down_mbps` | int | то же в Mbps; **проигрывает** `up`/`down`, если те заданы (`outbound.go:63-73`) | 0 | нет |
| `auth` | base64 []byte | пароль v1 | — | одно из `auth`/`auth_str` |
| `auth_str` | string | пароль строка; имеет приоритет над `auth` (`outbound.go:58-62`) | — | одно из |
| `obfs` | string | obfs-пароль (XPlus / `obfsParam`) | `""` | нет |
| `recv_window_conn` | uint64 | **deprecated** → `connection_receive_window` (`quic.go:33-40`) | 0 | нет |
| `recv_window` | uint64 | **deprecated** → `stream_receive_window` (`quic.go:41-43`) | 0 | нет |
| `disable_mtu_discovery` | bool | **deprecated** → `disable_path_mtu_discovery` (`quic.go:44-46`) | false | нет |
| `network` | string/[]string | `tcp`, `udp` | оба (`option/types.go:42-47`); UDP выключается флагом `UDPDisabled` | нет |
| `tls` | object | обязателен: без `enabled:true` — `ErrTLSRequired` (`outbound.go:42-44`) | — | да |

Brutal: включается не флагом, а `up_mbps`/`down_mbps` (BDP-контроль). Отдельного `brutal` в v1 нет.

## 2. Outbound `hysteria2` (v2)

`option.Hysteria2OutboundOptions` (`option/hysteria2.go:210-226`).

| JSON-ключ | Тип | Смысл | Дефолт | Обяз. |
|---|---|---|---|---|
| `server` | string | хост/IP | — | да, кроме `realm` |
| `server_port` | uint16 | порт | — | да, кроме `realm` |
| `server_ports` | []string | hopping-порты | — | нет |
| `hop_interval` | duration | период смены порта | 30s | нет |
| `hop_interval_max` | duration | верхняя граница рандомизации интервала (форк-новелла upstream 1.14) | = `hop_interval` | нет |
| `up_mbps` / `down_mbps` | int | Brutal up/down, Mbps (`MbpsToBps`) | 0 (fallback BBR) | нет |
| `password` | string | пароль Hy2 | `""` | да по смыслу |
| `obfs` | object | `type`: `salamander`\|`gecko`, `password` (обязателен: иначе `missing obfs password`, `outbound.go:62-64`); у `gecko` — `min_packet_size`/`max_packet_size` (дефолты 512 / 1200, cap 2048 — `sing-quic@v0.7.0/hysteria2/gecko.go:21-23`) | нет obfs | нет |
| `network` | string/[]string | `tcp`, `udp` | оба; `UDPDisabled` при отсутствии `udp` | нет |
| `bbr_profile` | enum | `standard`\|`conservative`\|`aggressive` | `""` = дефолт BBR | нет |
| `brutal_debug` | bool | debug-логи Brutal | false | нет |
| `disable_chrome_parrot` | bool | выключить Chrome-parrot (маскировка под Chrome QUIC) | false, т.е. **parrot включён** (`outbound.go:167`) | нет |
| `realm` | object | Hy2 Realm: `server_url`, `token`, `realm_id`, `stun_servers`, `ip_version` (0/4/6), `port_mapping{enabled,timeout,lifetime}`, `http_client`; конфликтует с `server`/`server_port`/`server_ports` (`outbound.go:180-183`), SNI берётся из `server_url` | — | нет |
| `tls` | object | обязателен, как в v1 | — | да |

Общие QUIC-поля v1/v2 (`QUICOptions` = `HTTP2Options` + 3 поля, `option/http.go:14-26`): `idle_timeout`, `keep_alive_period`, `stream_receive_window`, `connection_receive_window`, `max_concurrent_streams`, `initial_packet_size`, `disable_path_mtu_discovery`.

TLS-подблок (`OutboundTLSOptions`, `option/tls.go:107-136`), у обоих типов: `enabled`, `server_name` (дефолт = `server`), `insecure`, `alpn`, `min_version`/`max_version`, `cipher_suites`, `certificate`/`certificate_path`/`certificate_public_key_sha256`, `client_certificate*`/`client_key*`, `fragment*`, `spoof*`, `kernel_tx`/`kernel_rx`, `engine`, `handshake_timeout`, `ech`, `utls`, `reality`. `certificate_path` = ссылочный `ca`, `certificate` = `ca_str`.

## 3. Ссылки `hysteria://` (v1)

`parser/link/hysteria.go`; схема `hysteria` (`parser/link/parser.go:27`). Формат: `hysteria://host:port?params#tag`. Portal по умолчанию нет (host/port из URL). `TLSOptions.Enabled=true`; SNI = hostname.
Query: `auth` → `auth_str`; `peer`/`sni` → `server_name`; `alpn` (через запятую); `ca` → `certificate_path`; `ca_str` (строки через `\n`) → `certificate`; `up`/`down` → byteformat; `up_mbps`/`down_mbps`; `obfs`/`obfsParam` → `obfs`; `insecure`/`skip-cert-verify` (`1`/`true`); `tfo`/`tcp-fast-open`/`tcp_fast_open` → `tcp_fast_open`. `#fragment` → `tag`. Неизвестные параметры игнорируются молча.

## 4. Ссылки `hy2://`, `hysteria2://` (v2)

`parser/link/hysteria2.go`; схемы `hy2`, `hysteria2` (`parser.go:29`). **`hy://` не поддерживается** — любая иная схема падает в `unsupported scheme` (v1/v2-ссылки, в отличие от ss/vmess, не проходят base64-декод).
Формат: `hy2://password@host:port/?params#tag`. Пароль — только `URL.User.Username()` (без `:`-части). Порт по умолчанию **443**, если в URL не указан.
Query: `up`/`down` → `up_mbps`/`down_mbps` (int); `obfs` → `obfs.type`, но только при значении `salamander` или `gecko`; `obfs-password` → `obfs.password` (без валидного `obfs` теряется — `options.Obfs` не выставляется); `insecure`/`skip-cert-verify`. `sni`/`alpn`/`ca` в v2-парсере **не читаются** — SNI всегда равен hostname. `#fragment` → `tag`.

## 5. Особенности форка

- Hysteria-опции hydracore совпадают с upstream sing-box-extended 1.14.1: Hydra-специфичных полей нет (проверено grep по `option/`).
- Есть сервис `hysteria-realm` (`constant/proxy.go:66`, `HysteriaRealmServiceOptions`).
- `github.com/sagernet/sing` заменён на `shtorm-7/sing …-extended` (`go.mod:290`) — отсюда расширенные TLS-поля (`fragment`, `spoof`, `kernel_tx`/`kernel_rx`) и byteformat-скорости в `up`/`down`.
- У обоих outbound принудительно `options.UDPFragmentDefault = true` (`protocol/hysteria/outbound.go:41`, `hysteria2/outbound.go:53`).
- Clash-совместимые парсеры (`parser/clash/hysteria.go`, `hysteria2.go`) читают `ports`, `up-speed`/`down-speed` (Stash), `hop-interval`; из них `hop_interval_max`, `bbr_profile`, `realm` не выставляются.
