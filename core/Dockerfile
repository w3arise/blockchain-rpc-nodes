FROM alpine:3.19

ARG GETH_VERSION=v1.0.22
ARG TARGETARCH

RUN apk add --no-cache ca-certificates curl \
  && case "${TARGETARCH}" in \
       amd64) GETH_ASSET=geth_linux ;; \
       arm64) GETH_ASSET=geth-linux-arm64 ;; \
       *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
     esac \
  && curl -fsSL \
       "https://github.com/coredao-org/core-chain/releases/download/${GETH_VERSION}/${GETH_ASSET}" \
       -o /usr/local/bin/geth \
  && chmod +x /usr/local/bin/geth \
  && apk del curl \
  && geth version

ENTRYPOINT ["geth"]
