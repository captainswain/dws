#!/bin/sh
#
# Cloudflare WARP registration (single free account).
#
# Differences from the upstream Mon-ius scripts:
#   * No `referrer` field. There is deliberately no hook for crediting a
#     referral bonus to any account — this image does not farm WARP+.
#   * Optional bring-your-own license: if WARP_LICENSE is set to a key you
#     already own, it is attached to the freshly-registered account (Cloudflare's
#     "share WARP+ across up to 5 devices" model). Empty by default.
#   * Keys are generated locally with openssl; the private key never leaves
#     the container.
#   * Busybox-safe: /bin/sh shebang, no `date %N`.
#
# Output: a single JSON object on stdout that entrypoint.sh parses.

set -e

CF_API="https://api.cloudflareclient.com/v0a2025/reg"

# busybox `date` (Alpine) has no %N/%3N; fixed .000 ms keeps it valid ISO-8601.
TOS=$(date -u +"%Y-%m-%dT%H:%M:%S.000-02:00")

SECRET_KEY=$(openssl genpkey -algorithm X25519)
private_key=$(echo "$SECRET_KEY" | openssl pkey -outform DER | tail -c 32 | base64)
public_key=$(echo "$SECRET_KEY" | openssl pkey -pubout -outform DER | tail -c 32 | base64)

# --- register a new free account (no referrer) ---
REG_PAYLOAD=$(printf '{"tos":"%s","key":"%s"}' "$TOS" "$public_key")

RESPONSE=$(curl -fsSL -X POST "$CF_API" \
    -H "Content-Type: application/json" \
    -H "User-Agent: okhttp/4.12.1" \
    -d "$REG_PAYLOAD")

CF_ACCOUNT_ID=$(echo "$RESPONSE"  | grep -o '"id":"[^"]*'         | cut -d'"' -f4 | head -n 1)
CF_TOKEN_ID=$(echo "$RESPONSE"    | grep -o '"token":"[^"]*'      | cut -d'"' -f4 | head -n 1)
CF_LICENSE=$(echo "$RESPONSE"     | grep -o '"license":"[^"]*'    | cut -d'"' -f4 | head -n 1)
CF_CLIENT_ID=$(echo "$RESPONSE"   | grep -o '"client_id":"[^"]*'  | cut -d'"' -f4 | head -n 1)
CF_PUBLIC_KEY=$(echo "$RESPONSE"  | grep -o '"public_key":"[^"]*' | cut -d'"' -f4 | head -n 1)
CF_ADDR_V4=$(echo "$RESPONSE"     | grep -o '"v4":"[^"]*'         | cut -d'"' -f4 | tail -n 1)
CF_ADDR_V6=$(echo "$RESPONSE"     | grep -o '"v6":"[^"]*'         | cut -d'"' -f4 | tail -n 1)

# --- optional: attach a license key you already own ---
# Only runs if WARP_LICENSE is set. This binds the new account to your existing
# WARP+ subscription; it does not generate or farm one.
if [ -n "${WARP_LICENSE:-}" ] && [ -n "$CF_ACCOUNT_ID" ] && [ -n "$CF_TOKEN_ID" ]; then
    LIC_PAYLOAD=$(printf '{"license":"%s"}' "$WARP_LICENSE")
    curl -fsSL -X PUT "$CF_API/$CF_ACCOUNT_ID" \
        -H "Content-Type: application/json" \
        -H "User-Agent: okhttp/4.12.1" \
        -H "Authorization: Bearer $CF_TOKEN_ID" \
        -d "$LIC_PAYLOAD" >/dev/null 2>&1 || \
        echo "warn: license attach failed (key invalid or API changed); continuing free" >&2
fi

# --- emit the credentials the entrypoint consumes ---
printf '{"account":"%s","token":"%s","license":"%s","client":"%s","v4":"%s","v6":"%s","key":"%s","secret":"%s"}\n' \
    "$CF_ACCOUNT_ID" "$CF_TOKEN_ID" "$CF_LICENSE" "$CF_CLIENT_ID" \
    "$CF_ADDR_V4" "$CF_ADDR_V6" "$CF_PUBLIC_KEY" "$private_key"
