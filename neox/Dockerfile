FROM alpine:3.19

ARG GETH_VERSION=v0.6.1
ARG TARGETARCH

RUN apk add --no-cache ca-certificates curl \
  && case "${TARGETARCH}" in \
       amd64) GETH_ARCH=linux-amd64 ;; \
       arm64) GETH_ARCH=linux-arm64 ;; \
       *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
     esac \
  && curl -fsSL \
       "https://github.com/bane-labs/go-ethereum/releases/download/${GETH_VERSION}/geth-${GETH_ARCH}" \
       -o /usr/local/bin/geth \
  && chmod +x /usr/local/bin/geth \
  && apk del curl \
  && geth version

ENTRYPOINT ["geth"]
