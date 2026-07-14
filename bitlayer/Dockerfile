FROM golang:1.21-bookworm AS builder

ARG GETH_VERSION=v1.1.10

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc g++ make git ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone --depth 1 --branch "${GETH_VERSION}" https://github.com/bitlayer-org/bitlayer-l2.git . \
  && go run build/ci.go install -static ./cmd/geth

FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
  && rm -rf /var/lib/apt/lists/*

COPY --from=builder /src/build/bin/geth /usr/local/bin/geth
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ARG GETH_VERSION=v1.1.10
LABEL version="${GETH_VERSION}"

ENTRYPOINT ["/entrypoint.sh"]
