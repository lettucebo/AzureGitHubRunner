# ============================================================================
# ACA GitHub Actions Runner Image
#
# 刻意不安裝 Docker daemon：ACA 不支援容器內執行 Docker，
# 需要 Docker 的 job 一律直接在 workflow 指定 GitHub-hosted runner。
# ============================================================================
FROM ubuntu:24.04

ARG RUNNER_VERSION
ARG RUNNER_SHA256
ARG DEBIAN_FRONTEND=noninteractive

# 強制要求版本 pin
RUN test -n "${RUNNER_VERSION}" && test -n "${RUNNER_SHA256}"

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl jq git openssh-client \
      tar gzip unzip zip sudo \
      libicu74 liblttng-ust1 libkrb5-3 zlib1g \
      python3 python3-pip build-essential \
 && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --shell /bin/bash runner

WORKDIR /home/runner/actions-runner

RUN curl -fsSL -o runner.tar.gz \
      "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" \
 && echo "${RUNNER_SHA256}  runner.tar.gz" | sha256sum -c - \
 && tar xzf runner.tar.gz \
 && rm runner.tar.gz \
 && ./bin/installdependencies.sh

COPY entrypoint.sh /home/runner/entrypoint.sh

RUN chmod +x /home/runner/entrypoint.sh \
 && chown -R runner:runner /home/runner

ENV RUNNER_ALLOW_RUNASROOT=0 \
    RUNNER_MANUALLY_TRAP_SIG=1

USER runner
ENTRYPOINT ["/home/runner/entrypoint.sh"]
