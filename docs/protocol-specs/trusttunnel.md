# TrustTunnel — спецификация (источник: `hydracore`)

Форк sing-box. TrustTunnel пришёл из upstream-базы (`release/UPSTREAM_BASELINE`: `shtorm-7/sing-box-extended` v1.14.1-extended-2.7.2; первый коммит — `195a33379`, автор Shtorm), в ванильном `sagernet/sing-box` его нет. Тип — `trusttunnel` (`hydracore/constant/proxy.go:18`, отображение `:107-108`). Регистрация: `hydracore/include/registry.go:95` (inbound), `:136` (outbound), за тегом сборки `with_trusttunnel`; без тега — заглушка с ошибкой `TrustTunnel is not included in this build` (`include/trusttunnel_stub.go:19`). Тег входит в `release/DEFAULT_BUILD_TAGS*`.

Суть: HTTPS CONNECT-прокси поверх HTTP/2 или HTTP/3 (QUIC).

## 1. Outbound

Схема — `hydracore/option/trusttunnel.go:24-36`, сборка — `hydracore/protocol/trusttunnel/outbound.go:33-76`.

| JSON-ключ | Тип | Смысл | Дефолт / обязательность |
|---|---|---|---|
| `server` | string | адрес сервера | обязателен (`option/outbound.go:183-186`) |
| `server_port` | uint16 | порт | обязателен |
| `username` | string | логин для `Proxy-Authorization: Basic` | опц., `""` → `Basic Og==` (пустой логин/пароль), не валидируется (`transport/trusttunnel/protocol.go:24-25`) |
| `password` | string | пароль | опц., `""` |
| `network` | string/[]string (`tcp`,`udp`) | сети адаптера | опц.; пусто → `tcp+udp` (`option/types.go:42-47`) |
| `health_check` | bool | периодический CONNECT на `_check` | опц., `false`; при `true` таймер 7 с (`client.go:122-141`) |
| `quic` | bool | транспорт: `true` → HTTP/3, иначе HTTP/2 | опц., `false`; ALPN пусто → `h3` (`client.go:91`) или `h2` (`client.go:113`) |
| `congestion_controller` | enum `bbr`,`cubic`,`reno` | только при `quic` | опц., `""` → `bbr` (meta2, ProfileStandard); иное → ошибка (`common/congestion/congestion.go:17-48`) |
| `cwnd` | int | только при `quic` | опц., `0` → `32` (`congestion.go:20-22`) |
| `tls` | объект | TLS обязателен | **обязателен**: `tls == nil` или `!enabled` → `ErrTLSRequired` (`outbound.go:34-36`, `constant/err.go:5`). Поля — `option/tls.go:106-135` (`server_name`, `insecure`, `alpn`, `fragment`, `record_fragment`, `utls`, `ech`, …) |
| `multiplex` | объект | собственный блок (см. ниже) | опц. |
| + `DialerOptions` | — | `detour`, `bind_interface`, `inet4/6_bind_address`, `routing_mark`, `netns`, `connect_timeout`, `tcp_fast_open`, `tcp_multi_path`, `tcp_keep_alive*`, `udp_fragment`, `domain_resolver`, `network_strategy`, `network_type`, `fallback_*` | опц. (`option/outbound.go:80-112`) |

`multiplex` — **не** штатный `OutboundMultiplexOptions` из `option/multiplex.go`, а отдельный тип `TrustTunnelMultiplexOptions` (`option/trusttunnel.go:17-22`), работающий как пул HTTP-клиентов:

| Ключ | Тип | Смысл | Дефолт |
|---|---|---|---|
| `enabled` | bool | включить пул; `false` → один клиент | `false` (`outbound.go:60-67`) |
| `max_connections` | int | максимум параллельных клиентов | `0`; при всех трёх нулях → `8` (`client.go:249-253`) |
| `min_streams` | int | порог, ниже которого переиспользуется текущий клиент | `0`; → `5` |
| `max_streams` | int | порог переиспользования, если `max_connections == 0` | `0` (`client.go:281-292`) |

Подблока `transport` у протокола **нет** — H2/H3 зашиты в транспорт, поля `transport.*` ядро не читает (в JSON молча игнорируются).

UDP: `DialContext(udp)` открывает CONNECT на хост `_udp2`, `ListenPacket` — то же; клиент отвергает не-IP адреса (`outbound.go:80-99`, `packet.go:100-102`).

## 2. Inbound (для полноты)

`option/trusttunnel.go:3-10`, `protocol/trusttunnel/inbound.go:52-183`. Поля: `listen`, `listen_port`, `network`, `users[] {name, password}`, `congestion_controller`, `cwnd`, `tls` (обязателен, `inbound.go:53-55`). Отличия: при пустом `network` сервер слушает **только TCP** (`inbound.go:56-59`), ALPN пусто → `h2` (`:98`); QUIC-листенер — `Allow0RTT`, `MaxIncomingStreams 1<<60`, `MaxIdleTimeout 60s`.

## 3. Форматы ссылок: `tt://` и `trusttunnel://`

**Не найдено в ядре.** Ни один парсер ссылок в репозитории этих схем не знает:

- `hydracore/parser/link/parser.go:14-41` — поддерживает только `tuic`, `trojan`, `vless`, `hysteria`, `hy2`/`hysteria2`, `anytls`, `ss`, `vmess`; иное → `unsupported scheme`. Файлов `parser/link/*trusttunnel*` нет.
- `core/subscription/src/commonMain/kotlin/io/hydrabox/core/subscription/SubscriptionParser.kt:80-95` (`proxySchemes`), `:119-146` — те же протоколы плюс `socks*`, `http(s)`, `snell`, `wg`/`wireguard`, `vmess`, `ssr`; `trusttunnel`/`tt` отсутствуют, ветка `else -> error("unsupported scheme")`. Общий маппинг `ShareLink.Proxy` → outbound (`ShareLinkOutbound.kt:51-55, 96-160`) превратил бы схему в `type: <scheme>` и поля `username`/`password`, но схема до него не доходит.
- Сплошной поиск по рабочему дереву и по истории гидры (`git log --all -S"tt://"`, `-S"trusttunnel://"`) — 0 совпадений. В `hydracore/service/manager_api/.../openapi.yaml`, `service/manager/constant/dto.go:71` и `constant/proxy.go` `trusttunnel` встречается только как имя типа/значение enum, не как схема ссылки.

Итог: если в внешнем продукте и существуют `tt://` и `trusttunnel://`, в этом репозитории их разбор не реализован — маппинг «ссылка → поля outbound» придётся писать (ожидаемо в `parser/link/` и `SubscriptionParser`/`ShareLinkOutbound`).

## 4. Особенности (нестандартное относительно ванильного sing-box)

1. Единственный протокол форка, работающий как **HTTPS CONNECT-прокси**: `Method: CONNECT`, заголовки `Host` = цель и `Proxy-Authorization: Basic` (`transport/trusttunnel/client.go:174-187`), сервер проверяет метод и требование аутентификации (`service.go:83-97, 170-186`).
2. **Магические хосты** в CONNECT: `_udp2` (UDP ASSOCIATE-аналог), `_check` (health check), `_icmp` (объявлен, но в `ServeHTTP` не обрабатывается) — `protocol.go:16-18`, `service.go:99-139`.
3. **UDP-заголовок 4+16+2+16+2**, у клиентских пакетов дополнительно `uint8 len(appName)` + строка `"sing-box"`; IPv4 паддится нулями до 16 байт (`packet.go:67-77, 148-176`; `appName` жёстко `"sing-box"`, `client.go:36`).
4. `congestion_controller`/`cwnd` на уровне протокола; сервер применяет их на QUIC-соединении (`inbound.go:140-153`).
5. **Cвой `multiplex`** — пул HTTP-клиентов с выбором наименее загруженного, а не mux-протокол sing-box (`client.go:236-305`).
6. TLS обязателен с обеих сторон, `ErrTLSRequired` вместо дефолтного TLS.
7. Асимметрия дефолта `network`: клиент без `network` = `tcp+udp`, сервер без `network` = только `tcp`.
8. Multi-user: серверные пользователи управляются во время работы (`UpdateUsers`, закрытие соединений удалённого юзера — `service.go:47-53`), подключены к manager API (`service/node/inbound/trusttunnel.go`, `service/node/service.go`).
9. Проверка клиента: `test/trusttunnel_test.go` гоняет матрицу H2/H3 × mux × cc (`bbr`,`cubic`,`reno`) × network.
