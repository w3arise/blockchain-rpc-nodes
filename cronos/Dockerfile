FROM alpine:3.20

ARG CRONOS_VERSION=1.7.8
ARG TARGETARCH
# Set by ./configure.sh (your host uid/gid) so bind-mounted datadir stays writable
ARG BUILD_UID=1000
ARG BUILD_GID=1000

RUN apk add --no-cache ca-certificates curl tar \
  && case "${TARGETARCH}" in \
       amd64) CRONOS_ARCH=Linux_x86_64 ;; \
       arm64) CRONOS_ARCH=Linux_arm64 ;; \
       *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
     esac \
  && curl -fsSL \
       "https://github.com/crypto-org-chain/cronos/releases/download/v${CRONOS_VERSION}/cronos_${CRONOS_VERSION}_${CRONOS_ARCH}.tar.gz" \
       -o /tmp/cronos.tar.gz \
  && tar -xzf /tmp/cronos.tar.gz -C /tmp \
  && mv /tmp/bin/cronosd /usr/local/bin/cronosd \
  && chmod +x /usr/local/bin/cronosd \
  && rm -rf /tmp/cronos.tar.gz /tmp/bin \
  && apk del curl tar \
  && cronosd version

RUN addgroup -g "${BUILD_GID}" cronos \
  && adduser -D -u "${BUILD_UID}" -G cronos cronos \
  && chmod 1777 /tmp

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && chown cronos:cronos /entrypoint.sh

USER cronos

ENTRYPOINT ["/entrypoint.sh"]
