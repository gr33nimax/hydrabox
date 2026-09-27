# WireGuard / AmneziaWG — спецификация HydraBox2

источник истины — код `hydracore` (форк sing-box). WireGuard здесь **endpoint**, а не outbound:
регистрируется в `hydracore/protocol/wireguard/endpoint.go` (`endpoint.Register[option.WireGuardEndpointOptions]`),
опции — `hydracore/option/wireguard.go`, реализация устройства — `hydracore/transport/wireguard/`,
AmneziaWG в UAPI — `hydracore/transport/wireguard/amnezia.go`, обфускация — `hydracore/forks/wireguard-go/device/obf*.go`.
В JSON конфиге объект обязан лежать в `endpoints`, а не в `outbounds` (`core/config/.../TunnelConfig.kt:267-309`).

## 1. Endpoint: `endpoints[]`, `"type": "wireguard"`

| JSON-ключ | тип | смысл | дефолт | обяз. |
|---|---|---|---|---|
| `system` | bool | поднять системный TUN вместо userspace-стека | `false` (gVisor-стек) | нет |
| `name` | string | имя интерфейса; при `system` и для исключения из egress-pool | `CalculateInterfaceName("wg")` | нет |
| `mtu` | uint32 | MTU | `0` → **1408** (`transport/wireguard/endpoint.go:107`) | нет |
| `address` | prefix или массив | локальные адреса интерфейса | — | да (стек требует IPv4/IPv6 local, `device_stack.go:113`) |
| `private_key` | string base64 | ключ интерфейса | — | **да** (`missing private key`) |
| `listen_port` | uint16 | локальный порт | `0` → случайный | нет; **конфликт с `detour`** |
| `peers` | массив peer | см. §2 | — | нет формально, без peer туннеля нет |
| `udp_timeout` | duration | NAT-таймаут | `0` → `C.UDPTimeout` = **5m** | нет |
| `udp_mapping` / `udp_filtering` | enum | поведение NAT | — | нет |
| `udp_nat_max` | uint32 | лимит NAT-сессий | 0 | нет |
| `workers` | int | воркеры устройства | 0 (авто) | нет; **0..64** |
| `preallocated_buffers_per_pool` | uint32 | буферы пула | 0 | нет; **≤4096** |
| `disable_pauses` | bool | не вставать на паузу | false | нет |
| `amnezia` | объект | см. §3 | — | нет |
| `detour` | string | outbound для доставки UDP | — | нет |

## 2. Peer: `peers[]`

| JSON-ключ | тип | смысл | дефолт | обяз. |
|---|---|---|---|---|
| `address` | string | хост/IP пира (домен резолвится через `dnsRouter`) | — | практически да |
| `port` | uint16 | порт пира | — | практически да |
| `public_key` | string base64 | ключ пира | — | **да** |
| `pre_shared_key` | string base64 | PSK | — | нет |
| `allowed_ips` | prefix или массив | маршрутизируемые сети | — | **да, непустой** (`missing allowed ips for peer N`) |
| `persistent_keepalive_interval` | uint16, сек | keepalive | 0 | нет |

## 3. AmneziaWG: `amnezia{...}`

Базовые: `jc` (int), `jmin`, `jmax`, `s1`, `s2`, `s3`, `s4` (int) — junk-пакеты и паддинги.
Доп. 3.x: `h1`..`h4` — **число или диапазон `"a-b"`** (`badoption.Range[uint32]`); `i1`..`i5` — строки CPS
(теги `<b …>`, `<c>`, `<t>`, `<r>`, `<rc>`, `<rd>`, `<d…>`, `<ds…>`, `<dz…>` — `forks/.../device/obf.go`);
`header_protection_key` (base64, ровно 32 байта), `content_padding_addition`, `rekey_after_time`, `rekey_timeout`,
`reject_after_time`, `keepalive_timeout`, `max_handshake_attempts` (диапазоны), `random_trailers`, `disable_cookies` (bool).

Валидация при старте (`protocol/wireguard/endpoint.go:177-260`): `jc`≤128, `jmin`/`jmax`/`s1..s4`≤65535, `jmin`≤`jmax`,
`jc*jmax`≤4 MiB, диапазоны упорядочены; максимумы: padding 65535, таймеры 86400, `max_handshake_attempts` 128.
В UAPI уходят только ненулевые значения (`amnezia.go`), ключ переводится в hex.

## 4. Форматы ссылок и конфигов (клиент: `core/subscription/.../SubscriptionParser.kt`)

| вход | распознавание | маппинг |
|---|---|---|
| `[Interface]` в начале тела | `parseWireGuardConfig` (`**/OutboundCatalog.kt:310`) | wg-quick: `[Interface]` `Address`, `PrivateKey`, `MTU`, `Name`; `[Peer]` `PublicKey`, `PresharedKey`, `Endpoint` (host:port), `AllowedIPs`, `PersistentKeepalive`. Amnezia-ключи — PascalCase `Jc,Jmin,Jmax,S1..S4,H1..H4,I1..I5,HeaderProtectionKey,ContentPaddingAddition,RekeyAfterTime,RekeyTimeout,RejectAfterTime,KeepaliveTimeout,MaxHandshakeAttempts,RandomTrailers,DisableCookies` → snake_case |
| `wg://` / `wireguard://` | `parseWireGuardLink` | private key: `private_key`/`privatekey`/`secret_key` или userinfo; peer key: `public_key`/`publickey`/`peer_public_key`/`pubkey`; адрес: `local_address`/`address`/`ip` (CSV); `pre_shared_key`/`presharedkey`; `mtu`, `keepalive`, `allowed_ips`; Amnezia — те же snake_case поля в query |
| Clash YAML | `ClashDocument.wireguardEndpoint` | `private-key`, `public-key`, `pre-shared-key`, `ip`+`ipv6`, `allowed-ips`, `mtu` |

Сборка JSON endpoint — `ShareLinkOutbound.endpoint()`: `address` (дефолт `172.16.0.2/32`), `private_key`, `mtu` (только 576..9000),
`peers[0] = {address, port, public_key, pre_shared_key, allowed_ips (дефолт `0.0.0.0/0`,`::/0`), persistent_keepalive_interval}`,
`amnezia` из query; диапазоны принимаются и числом, и строкой `a-b`.

## 5. Особенности форка

- AmneziaWG встроен в форк wireguard-go (`obf*.go`, `padding_test.go`, `random_trailer_classification_test.go`),
  плюс `header_protection_key`, `random_trailers`, `disable_cookies` — сверх ванильного AWG.
- Лимиты ресурсов валидируются и в `libbox CheckConfig` (`config_wireguard_limits_test.go`), не только в рантайме.
- WARP — отдельный endpoint `"type": "warp"` (`option/warp.go`, `protocol/warp/`): `profile{id, auth_token, private_key, license_key, recreate, detour}`,
  `address`/`port`, `listen_port`, `persistent_keepalive_interval`, `udp_timeout`, `workers`, `preallocated_buffers_per_pool`,
  `disable_pauses`, урезанный `amnezia` (`jc`, `jmin`, `jmax`, `i1..i5`, диапазоны таймеров). Ключ генерируется или берётся из `profile.private_key`,
  регистрация в Cloudflare API — `protocol/warp/endpoint.go:createConfig`.
- **`reserved` в форке нет.** Легаси-поля outbound-формы (`server`, `server_port`, `peer_public_key`, `local_address`, `system_interface`)
  не принимаются: core их не регистрирует, весь конфиг отвергается целиком — используй поля из §1/§2.
