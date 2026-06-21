#!/usr/bin/env bash
#
# Bring up a WiFi access point with hostapd + dnsmasq and tunnel every
# connected client through a proxy (running on the host) via tun2proxy.
#
# Only traffic originating from the hotspot subnet is policy-routed into the
# tunnel, so the host's own networking is left completely untouched.
#
set -euo pipefail

log() { printf '[hotspot] %s\n' "$*" >&2; }
die() { printf '[hotspot] ERROR: %s\n' "$*" >&2; exit 1; }

# --- Configuration (override via environment / .env) ------------------------
WIFI_INTERFACE="${WIFI_INTERFACE:?Set WIFI_INTERFACE to your wireless device, e.g. wlan0}"
WIFI_PASSWORD="${WIFI_PASSWORD:?Set WIFI_PASSWORD (min 8 characters, WPA2)}"
SSID="${SSID:-Hotspot}"
WIFI_CHANNEL="${WIFI_CHANNEL:-6}"
WIFI_HW_MODE="${WIFI_HW_MODE:-g}"
COUNTRY_CODE="${COUNTRY_CODE:-US}"

HOTSPOT_ADDR="${HOTSPOT_ADDR:-192.168.50.1}"
HOTSPOT_PREFIX="${HOTSPOT_PREFIX:-24}"
HOTSPOT_SUBNET="${HOTSPOT_SUBNET:-192.168.50.0/24}"
DHCP_START="${DHCP_START:-192.168.50.10}"
DHCP_END="${DHCP_END:-192.168.50.200}"
DHCP_NETMASK="${DHCP_NETMASK:-255.255.255.0}"
DHCP_LEASE="${DHCP_LEASE:-12h}"

PROXY="${PROXY:-socks5://127.0.0.1:1080}"
TUN_NAME="${TUN_NAME:-tun0}"
TUN_MTU="${TUN_MTU:-1500}"
DNS_STRATEGY="${DNS_STRATEGY:-virtual}"
CLIENT_DNS="${CLIENT_DNS:-198.18.0.1}"
RT_TABLE="${RT_TABLE:-100}"
LOG_LEVEL="${LOG_LEVEL:-info}"

[ "${#WIFI_PASSWORD}" -ge 8 ] || die "WIFI_PASSWORD must be at least 8 characters (WPA2 requirement)"

HOSTAPD_CONF="$(mktemp /tmp/hostapd.XXXXXX.conf)"
DNSMASQ_CONF="$(mktemp /tmp/dnsmasq.XXXXXX.conf)"
PIDS=()

cleanup() {
  log "Shutting down, reverting network changes ..."
  for pid in "${PIDS[@]:-}"; do
    [ -n "${pid:-}" ] && kill "$pid" 2>/dev/null || true
  done
  iptables -D FORWARD -i "$WIFI_INTERFACE" -o "$TUN_NAME" -s "$HOTSPOT_SUBNET" -j ACCEPT 2>/dev/null || true
  iptables -D FORWARD -i "$TUN_NAME" -o "$WIFI_INTERFACE" -d "$HOTSPOT_SUBNET" -j ACCEPT 2>/dev/null || true
  ip rule del from "$HOTSPOT_SUBNET" lookup "$RT_TABLE" 2>/dev/null || true
  ip route flush table "$RT_TABLE" 2>/dev/null || true
  ip link del "$TUN_NAME" 2>/dev/null || true
  ip addr flush dev "$WIFI_INTERFACE" 2>/dev/null || true
  rm -f "$HOSTAPD_CONF" "$DNSMASQ_CONF"
  log "Cleanup done."
}
trap cleanup EXIT INT TERM

# --- Sanity checks ----------------------------------------------------------
[ -e /dev/net/tun ] || die "/dev/net/tun missing. Mount it into the container (see docker-compose.yml)."
ip link show "$WIFI_INTERFACE" >/dev/null 2>&1 \
  || die "Interface '$WIFI_INTERFACE' not found. It must exist and be free (not managed by NetworkManager/wpa_supplicant)."

# Unblock the radio if rfkill + /dev/rfkill are available (best effort).
command -v rfkill >/dev/null 2>&1 && rfkill unblock wifi 2>/dev/null || true

# --- Prepare the AP interface ----------------------------------------------
log "Configuring $WIFI_INTERFACE -> $HOTSPOT_ADDR/$HOTSPOT_PREFIX"
ip link set "$WIFI_INTERFACE" down 2>/dev/null || true
ip addr flush dev "$WIFI_INTERFACE" 2>/dev/null || true
ip addr add "$HOTSPOT_ADDR/$HOTSPOT_PREFIX" dev "$WIFI_INTERFACE"
ip link set "$WIFI_INTERFACE" up

# --- Create the tun device tun2proxy attaches to ----------------------------
log "Creating tun device $TUN_NAME (mtu $TUN_MTU)"
ip tuntap add name "$TUN_NAME" mode tun 2>/dev/null || true
ip link set "$TUN_NAME" mtu "$TUN_MTU" up

# --- Forwarding + source-based policy routing (hotspot clients only) --------
# Host traffic is unaffected: only packets whose source is the hotspot subnet
# consult table $RT_TABLE, where the default route points at the tunnel.
sysctl -wq net.ipv4.ip_forward=1
ip rule add from "$HOTSPOT_SUBNET" lookup "$RT_TABLE" 2>/dev/null || true
# Keep intra-subnet traffic (gateway, other clients) local; tunnel the rest.
ip route replace "$HOTSPOT_SUBNET" dev "$WIFI_INTERFACE" table "$RT_TABLE"
ip route replace default dev "$TUN_NAME" table "$RT_TABLE"

iptables -A FORWARD -i "$WIFI_INTERFACE" -o "$TUN_NAME" -s "$HOTSPOT_SUBNET" -j ACCEPT
iptables -A FORWARD -i "$TUN_NAME" -o "$WIFI_INTERFACE" -d "$HOTSPOT_SUBNET" -j ACCEPT

# --- tun2proxy: forwards everything arriving on the tun to the proxy --------
log "Starting tun2proxy -> $PROXY (dns: $DNS_STRATEGY)"
tun2proxy-bin --tun "$TUN_NAME" --proxy "$PROXY" --dns "$DNS_STRATEGY" --verbosity "$LOG_LEVEL" &
PIDS+=("$!")

# --- dnsmasq: DHCP only (DNS is handled inside the tunnel by tun2proxy) ------
cat > "$DNSMASQ_CONF" <<EOF
interface=$WIFI_INTERFACE
bind-interfaces
port=0
dhcp-authoritative
dhcp-range=$DHCP_START,$DHCP_END,$DHCP_NETMASK,$DHCP_LEASE
dhcp-option=3,$HOTSPOT_ADDR
dhcp-option=6,$CLIENT_DNS
EOF
log "Starting dnsmasq (DHCP $DHCP_START-$DHCP_END, gw $HOTSPOT_ADDR, dns $CLIENT_DNS)"
dnsmasq --conf-file="$DNSMASQ_CONF" --no-daemon &
PIDS+=("$!")

# --- hostapd: the actual access point --------------------------------------
cat > "$HOSTAPD_CONF" <<EOF
interface=$WIFI_INTERFACE
driver=nl80211
ssid=$SSID
country_code=$COUNTRY_CODE
hw_mode=$WIFI_HW_MODE
channel=$WIFI_CHANNEL
ieee80211d=1
wmm_enabled=1
auth_algs=1
wpa=2
wpa_key_mgmt=WPA-PSK
wpa_pairwise=CCMP
rsn_pairwise=CCMP
wpa_passphrase=$WIFI_PASSWORD
macaddr_acl=0
ignore_broadcast_ssid=0
EOF
log "Starting hostapd: SSID='$SSID' channel=$WIFI_CHANNEL band=$WIFI_HW_MODE country=$COUNTRY_CODE"
hostapd "$HOSTAPD_CONF" &
PIDS+=("$!")

log "Hotspot is up. Connect to '$SSID' — all client traffic is tunneled through $PROXY."

# Exit (and trigger cleanup) as soon as any core service dies.
wait -n
die "A core service exited unexpectedly; tearing down."
