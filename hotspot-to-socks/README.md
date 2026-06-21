# hotspot-to-socks

Turn a spare WiFi adapter into an access point and tunnel **every connected
client's traffic through a proxy running on your host machine** — all from a
single container.

```
 ┌──────────┐  WiFi   ┌──────────────── container (host netns) ────────────────┐
 │ phone /  │ ──────► │ hostapd (AP) + dnsmasq (DHCP)                           │
 │ laptop / │         │        │  src=192.168.50.0/24                           │
 │ TV ...   │ ◄────── │        ▼  (policy route, table 100)                     │
 └──────────┘         │     tun0 ──► tun2proxy ──► PROXY (e.g. socks5://host)   │
                      └────────────────────────────│───────────────────────────┘
                                                    ▼
                                        proxy on the host (127.0.0.1:1080)
```

* **hostapd** broadcasts the WPA2 network.
* **dnsmasq** hands out DHCP leases (DNS only — it is *not* used as resolver).
* **tun2proxy** ([tun2proxy/tun2proxy](https://github.com/tun2proxy/tun2proxy))
  reads the tun device and forwards connections to a SOCKS5/SOCKS4/HTTP proxy.
* **Source-based policy routing** sends *only* the hotspot subnet through the
  tunnel. Your host's own connectivity is left untouched.

## Requirements

* A wireless adapter that supports **AP mode**
  (`iw list | grep -A10 'Supported interface modes'` should list `AP`).
* A proxy listening on the host (any SOCKS5/SOCKS4/HTTP proxy: an SSH dynamic
  tunnel `ssh -D 1080`, a VPN client's local SOCKS port, etc.).
* `docker` + `docker compose`, and a kernel with `tun` and `nl80211`.

## Setup

1. **Free the wireless interface on the host** so hostapd can own it:

   ```bash
   sudo nmcli device set wlan0 managed no    # if you use NetworkManager
   sudo rfkill unblock wifi
   ```

   (Use the interface you intend to broadcast on; it must not be your only
   uplink unless you have a second adapter for internet/proxy access.)

2. **Configure** the hotspot:

   ```bash
   cp .env.example .env
   $EDITOR .env          # set WIFI_INTERFACE, WIFI_PASSWORD, PROXY, ...
   ```

3. **Run**:

   ```bash
   docker compose up --build
   ```

Connect a device to the SSID — all of its traffic now exits through `PROXY`.
Verify on the client with e.g. `curl https://ifconfig.me` (should show the
proxy's egress IP).

## Configuration

All settings are environment variables (see [`.env.example`](.env.example)).
The important ones:

| Variable          | Default                  | Description                                   |
| ----------------- | ------------------------ | --------------------------------------------- |
| `WIFI_INTERFACE`  | *(required)*             | Wireless device to use as the AP, e.g. `wlan0`|
| `WIFI_PASSWORD`   | *(required)*             | WPA2 passphrase (≥ 8 chars)                   |
| `PROXY`           | `socks5://127.0.0.1:1080`| Host proxy URL (`socks5`/`socks4`/`http`)     |
| `SSID`            | `Hotspot`                | Network name                                  |
| `WIFI_CHANNEL`    | `6`                      | Channel (`g`=2.4GHz, `a`=5GHz via `WIFI_HW_MODE`) |
| `COUNTRY_CODE`    | `US`                     | Regulatory domain                             |
| `HOTSPOT_SUBNET`  | `192.168.50.0/24`        | Client subnet that gets tunneled              |
| `DNS_STRATEGY`    | `virtual`                | `virtual` tunnels DNS over the proxy as TCP   |

The proxy URL supports auth, e.g. `socks5://user:pass@127.0.0.1:1080`
(percent-encode special characters in the password).

## How it works

The container runs in the host network namespace (mandatory for WiFi
hardware). To avoid hijacking the host's routing, traffic is split by **source
address** instead of using tun2proxy's `--setup`:

```
ip rule  add  from 192.168.50.0/24 lookup 100
ip route add  192.168.50.0/24 dev wlan0 table 100   # keep LAN traffic local
ip route add  default          dev tun0  table 100   # tunnel everything else
```

Packets from clients are forwarded into `tun0`; tun2proxy terminates them in
userspace and re-establishes each connection through the proxy. The host's
default route (table `main`) is never modified, and tun2proxy's own connection
to the proxy uses the host's normal routing, so there is no loop. All changes
are reverted on container stop.

## Troubleshooting

* **`Interface 'wlan0' not found` / hostapd fails immediately** — the interface
  is still managed by NetworkManager/wpa_supplicant. See step 1.
* **Permission errors on hostapd/iptables/sysctl** — swap `cap_add` for
  `privileged: true` in `docker-compose.yml`.
* **Clients connect but have no internet** — confirm the proxy actually works
  from the host (`curl --proxy socks5h://127.0.0.1:1080 https://ifconfig.me`)
  and that `PROXY` points at it.
* **DNS not resolving** — keep `DNS_STRATEGY=virtual`; this routes DNS through
  the proxy over TCP and avoids relying on the proxy's UDP support.
* **Some UDP apps (QUIC, games) fail** — many SOCKS proxies don't support UDP;
  browsers fall back to TCP automatically. Use a proxy with UDP/`udpgw` support
  if you need it.
