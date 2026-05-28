# Docker-Warp-Socks (fork) — Cloudflare WARP -> SOCKS5/HTTP proxy via sing-box.
#
# Hardened vs. upstream:
#   * No runtime `curl bit.ly/... | sh`. Registration is vendored & local.
#   * No referral-farming hook.
#   * sing-box pinned to a specific version for reproducible builds.
#
# Build:  docker build -t warp-socks .
# Run:    docker run --restart=always -itd --name warp_socks -p 9091:9091 warp-socks
# Check:  curl -x socks5h://127.0.0.1:9091 -fsSL https://www.cloudflare.com/cdn-cgi/trace   # warp=on

FROM alpine:3.22

LABEL org.opencontainers.image.title="docker-warp-socks" \
      org.opencontainers.image.description="Cloudflare WARP -> SOCKS5/HTTP proxy via sing-box (hardened fork)." \
      org.opencontainers.image.licenses="GPL-3.0"

# Pinned sing-box. Config uses the >=1.12 schema, so do not pin below 1.12.
ARG SINGBOX_VERSION=1.13.12

RUN apk add --no-cache curl openssl ca-certificates tar gcompat \
    && rm -rf /var/cache/apk/*

RUN set -eu; \
    cd /tmp; \
    case "$(arch)" in \
        x86_64)  ARCH='amd64' ;; \
        aarch64) ARCH='arm64' ;; \
        armv7l)  ARCH='armv7' ;; \
        armv6l)  ARCH='armv6' ;; \
        ppc64le) ARCH='ppc64le' ;; \
        s390x)   ARCH='s390x' ;; \
        riscv64) ARCH='riscv64' ;; \
        *) echo "Unsupported architecture: $(arch)" >&2; exit 1 ;; \
    esac; \
    PKG="sing-box-${SINGBOX_VERSION}-linux-${ARCH}"; \
    URL="https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSION}/${PKG}.tar.gz"; \
    echo "Downloading ${URL}"; \
    curl -fsSL "$URL" -o singbox.tar.gz; \
    tar -xzf singbox.tar.gz; \
    install -m 0755 "${PKG}/sing-box" /usr/bin/sing-box; \
    mkdir -p /etc/sing-box; \
    rm -rf /tmp/*; \
    sing-box version

COPY create-cloudflare-warp.sh /usr/local/bin/create-cloudflare-warp
COPY entrypoint.sh             /run/entrypoint.sh
RUN chmod +x /usr/local/bin/create-cloudflare-warp /run/entrypoint.sh

EXPOSE 9091

ENTRYPOINT ["/run/entrypoint.sh"]
CMD ["rws-cli"]
