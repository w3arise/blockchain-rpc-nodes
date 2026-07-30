FROM alpine:3.20

ARG TACCHAIN_VERSION=1.6.0
ARG TARGETARCH
# Set by ./configure.sh (your host uid/gid) so bind-mounted datadir stays writable
ARG BUILD_UID=1000
ARG BUILD_GID=1000

RUN apk add --no-cache ca-certificates curl tar \
  && case "${TARGETARCH}" in \
       amd64) TAC_ARCH=amd64 ;; \
       arm64) TAC_ARCH=arm64 ;; \
       *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
     esac \
  && curl -fsSL \
       "https://github.com/TacBuild/tacchain/releases/download/v${TACCHAIN_VERSION}/tacchaind-linux-${TAC_ARCH}.tar.gz" \
       -o /tmp/tacchaind.tar.gz \
  && tar -xzf /tmp/tacchaind.tar.gz -C /tmp \
  && mv /tmp/bin/tacchaind /usr/local/bin/tacchaind \
  && chmod +x /usr/local/bin/tacchaind \
  && rm -rf /tmp/tacchaind.tar.gz /tmp/bin \
  && apk del curl tar \
  && tacchaind version

RUN addgroup -g "${BUILD_GID}" tac \
  && adduser -D -u "${BUILD_UID}" -G tac tac \
  && chmod 1777 /tmp

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && chown tac:tac /entrypoint.sh

USER tac

ENTRYPOINT ["/entrypoint.sh"]
