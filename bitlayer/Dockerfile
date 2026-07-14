FROM golang:1.21-alpine AS builder

ARG GETH_VERSION=v1.1.10

RUN apk add --no-cache gcc musl-dev linux-headers git

WORKDIR /src
RUN git clone --depth 1 --branch "${GETH_VERSION}" https://github.com/bitlayer-org/bitlayer-l2.git . \
  && go run build/ci.go install -static ./cmd/geth

FROM alpine:3.19

RUN apk add --no-cache ca-certificates

COPY --from=builder /src/build/bin/geth /usr/local/bin/geth
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ARG GETH_VERSION=v1.1.10
LABEL version="${GETH_VERSION}"

ENTRYPOINT ["/entrypoint.sh"]
