FROM debian:bookworm-slim

ARG TUN2PROXY_VERSION=v0.8.2
# Provided automatically by buildkit/buildx; falls back to the build host arch.
ARG TARGETARCH

RUN apt-get update && apt-get install -y --no-install-recommends \
    hostapd \
    dnsmasq \
    iproute2 \
    iptables \
    iw \
    rfkill \
    procps \
    ca-certificates \
    curl \
    unzip \
    && ARCH="${TARGETARCH:-$(dpkg --print-architecture)}" \
    && case "${ARCH}" in \
         amd64) T2P_ARCH="x86_64-unknown-linux-gnu" ;; \
         arm64) T2P_ARCH="aarch64-unknown-linux-gnu" ;; \
         *) echo "Unsupported architecture: ${ARCH}" >&2; exit 1 ;; \
       esac \
    && curl -fsSL -o /tmp/tun2proxy.zip \
       "https://github.com/tun2proxy/tun2proxy/releases/download/${TUN2PROXY_VERSION}/tun2proxy-${T2P_ARCH}.zip" \
    && unzip -j /tmp/tun2proxy.zip tun2proxy-bin -d /usr/local/bin \
    && chmod +x /usr/local/bin/tun2proxy-bin \
    && rm -f /tmp/tun2proxy.zip \
    && apt-get purge -y --auto-remove curl unzip \
    && rm -rf /var/lib/apt/lists/*

COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
