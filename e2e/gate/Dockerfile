# The gate container. Every e2e tier runs inside it and nowhere else: e2e/run.sh builds this image
# and starts it by itself, so no check, test or probe ever runs on the machine that starts the
# harness. Build context is the repository root, narrowed by Dockerfile.dockerignore beside this file.
#
# Every tool version and download is pinned in setup/pinned_values/pinned_values.toml and installed
# by provision.sh, which refuses any download whose SHA-256 does not match. The two base images are
# pinned by digest here.
FROM docker:29.9.0-cli@sha256:1a4c7cb63513f349bdad01fcc6e0f3f2f67d37b9da86f14dc0d4a0942eecda00 AS docker-cli

FROM debian:trixie-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        coreutils \
        curl \
        diffutils \
        file \
        findutils \
        gawk \
        gh \
        git \
        grep \
        gzip \
        jq \
        less \
        libgssapi-krb5-2 \
        libicu76 \
        libssl3t64 \
        nodejs \
        procps \
        python3 \
        python3-venv \
        sed \
        sudo \
        tar \
        unzip \
        util-linux \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker-cli /usr/local/libexec/docker/cli-plugins/ /usr/local/libexec/docker/cli-plugins/

ENV LANG=C.UTF-8 \
    PATH=/opt/gate-python/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    PYTHONDONTWRITEBYTECODE=1 \
    POWERSHELL_TELEMETRY_OPTOUT=1 \
    POWERSHELL_UPDATECHECK=Off \
    DOTNET_CLI_TELEMETRY_OPTOUT=1

WORKDIR /build
COPY setup/pinned_values/pinned_values.toml setup/pinned_values/pinned_values.py setup/pinned_values/pinned_values.sh setup/pinned_values/
COPY e2e/lib/host.sh e2e/lib/common.sh e2e/lib/
COPY e2e/gate/provision.sh e2e/gate/
RUN bash e2e/gate/provision.sh tools

COPY setup/ansible/requirements.yaml setup/ansible/
RUN bash e2e/gate/provision.sh collections

COPY setup/setup.sh setup/
RUN bash e2e/gate/provision.sh ansible-range

ARG GATE_UID=1000
ARG GATE_GID=1000
RUN bash e2e/gate/provision.sh user "${GATE_UID}" "${GATE_GID}"

COPY e2e/lib/host.sh e2e/gate/entrypoint.sh /usr/local/lib/installationhelper-e2e-gate/
WORKDIR /repo
ENTRYPOINT ["bash", "/usr/local/lib/installationhelper-e2e-gate/entrypoint.sh"]
