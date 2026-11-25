#!/bin/sh

#removed wack curls to bit.ly etc.

set -e

sleep 3

_WARP_SERVER=engage.cloudflareclient.com
_WARP_PORT=2408
_NET_PORT=9091

WARP_SERVER="${WARP_SERVER:-$_WARP_SERVER}"
WARP_PORT="${WARP_PORT:-$_WARP_PORT}"
NET_PORT="${NET_PORT:-$_NET_PORT}"
# Tunnel MTU. Cloudflare's own WARP client uses 1280. 1408 only fits where the host path carries
# 1468-byte UDP datagrams (1408 + 60 of WireGuard/UDP/IPv4): on a pod network with MTU 1420 the
# large incoming datagrams arrive as IP fragments, and where fragments are dropped every
# connection that receives a full-size packet (any TLS handshake) stalls ~3 s until TCP shrinks
# its segments. 1280 + 80 (IPv6 endpoint) = 1360 fits a 1420 path without fragmenting.
WARP_MTU="${WARP_MTU:-1280}"
case "$WARP_MTU" in ''|*[!0-9]*) echo "Error: WARP_MTU must be a number" >&2; exit 1 ;; esac

# Local, vendored registrar — no runtime curl|sh, no opaque shortlink.
RESPONSE=$(/usr/local/bin/create-cloudflare-warp)
CF_CLIENT_ID=$(echo "$RESPONSE" | grep -o '"client":"[^"]*' | cut -d'"' -f4 | head -n 1)
CF_ADDR_V4=$(echo "$RESPONSE" | grep -o '"v4":"[^"]*' | cut -d'"' -f4 | tail -n 1)
CF_ADDR_V6=$(echo "$RESPONSE" | grep -o '"v6":"[^"]*' | cut -d'"' -f4 | tail -n 1)
CF_PUBLIC_KEY=$(echo "$RESPONSE" | grep -o '"key":"[^"]*' | cut -d'"' -f4 | head -n 1)
CF_PRIVATE_KEY=$(echo "$RESPONSE" | grep -o '"secret":"[^"]*' | cut -d'"' -f4 | head -n 1)

if [ -z "$CF_CLIENT_ID" ] || [ -z "$CF_PUBLIC_KEY" ] || [ -z "$CF_PRIVATE_KEY" ]; then
    echo "Error: failed to parse WARP credentials" >&2
    exit 1
fi

reserved=$(echo "$CF_CLIENT_ID" | base64 -d | od -An -t u1 | awk '{print "["$1", "$2", "$3"]"}' | head -n 1)

if [ -n "$SOCK_USER" ] && [ -n "$SOCK_PWD" ]; then
AUTH_PART='
    "users": [
        {
            "username": "'"$SOCK_USER"'",
            "password": "'"$SOCK_PWD"'"
        }
    ],
'
else
    AUTH_PART=""
fi

DNS_PART='
        "servers": [
            {
                "tag": "remote",
                "type": "tls",
                "server": "dns.quad9.net",
                "domain_resolver": "local",
                "detour": "WARP"
            },
            {
                "tag": "local",
                "type": "udp",
                "server": "1.1.1.1",
                "detour": "direct-out"
            }
        ],
        "final": "remote",
        "reverse_mapping": true
'

ROUTE_PART='
        "default_domain_resolver": {
            "server": "local",
            "rewrite_ttl": 60
        },
        "rules": [
            {
                "inbound": "mixed-in",
                "action": "sniff"
            },
            {
                "protocol": "dns",
                "action": "hijack-dns"
            },
            {
                "ip_is_private": true,
                "outbound": "direct-out"
            }
        ],
        "auto_detect_interface": true,
        "final": "WARP"
'

PROXY_PART='    
    "endpoints": [
        {
            "tag": "WARP",
            "type": "wireguard",
            "address": [
                "'"${CF_ADDR_V4}"'/32",
                "'"${CF_ADDR_V6}"'/128"
            ],
            "private_key": "'"$CF_PRIVATE_KEY"'",
            "peers": [
                {
                    "address": "'"$WARP_SERVER"'",
                    "port": '"$WARP_PORT"',
                    "public_key": "'"$CF_PUBLIC_KEY"'",
                    "allowed_ips": [
                        "0.0.0.0/0"
                    ],
                    "persistent_keepalive_interval": 30,
                    "reserved": '"$reserved"'
                }
            ],
            "mtu": '"$WARP_MTU"',
            "udp_fragment": true
        }
    ],
'

cat <<EOF | tee /etc/sing-box/config.json
{
    "dns": {
$DNS_PART
    },
    "route": {
$ROUTE_PART
    },
    "inbounds": [
        {
            "type": "mixed",
            "tag": "mixed-in",
            "listen": "::",
$AUTH_PART
            "listen_port": $NET_PORT
        }
    ],
$PROXY_PART
    "outbounds": [
        {
            "tag": "direct-out",
            "type": "direct",
            "udp_fragment": true
        }
    ]
}
EOF

if [ ! -e "/usr/bin/rws-cli" ]; then
    printf '#!/bin/sh\nexec sing-box -c /etc/sing-box/config.json run\n' > /usr/bin/rws-cli && chmod +x /usr/bin/rws-cli
fi

exec "$@"
