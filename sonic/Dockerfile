FROM ubuntu:24.04

WORKDIR /app

ARG SONIC_VERSION=2.0.0
ENV SONIC_VERSION=${SONIC_VERSION}

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

RUN curl -L -o sonicd https://github.com/0xsoniclabs/sonic/releases/download/v${SONIC_VERSION}/sonicd \
 && curl -L -o sonictool https://github.com/0xsoniclabs/sonic/releases/download/v${SONIC_VERSION}/sonictool \
 && chmod +x sonicd sonictool

ENTRYPOINT ["./sonicd"]