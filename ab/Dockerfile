FROM ubuntu:24.04

ARG GETH_VERSION=v1.13.15-abcore-1.2

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /tmp
RUN curl -fsSL \
      "https://github.com/ABFoundationGlobal/abcore/releases/download/${GETH_VERSION}/geth-${GETH_VERSION}" \
      -o geth && \
    curl -fsSL \
      "https://github.com/ABFoundationGlobal/abcore/releases/download/${GETH_VERSION}/geth-${GETH_VERSION}.sha256" \
      -o geth.sha256 && \
    expected_sha="$(awk '{print $1}' geth.sha256)" && \
    actual_sha="$(sha256sum geth | awk '{print $1}')" && \
    test "${expected_sha}" = "${actual_sha}" && \
    install -m 0755 geth /usr/local/bin/geth && \
    rm -f geth geth.sha256 && \
    geth version

ARG GETH_VERSION
LABEL version="${GETH_VERSION}"

ENTRYPOINT ["geth"]
