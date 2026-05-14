FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai

RUN apt-get update -y && apt-get install -y --no-install-recommends \
        bash coreutils procps psmisc \
        curl wget ca-certificates \
        tar gzip xz-utils unzip \
        rsync file jq \
        python3 python3-yaml \
        iproute2 net-tools netcat-openbsd \
        sudo \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash -u 10001 fnostest && \
    mkdir -p /vol1 /var/apps /var/log/apps /usr/trim/apps && \
    chown -R fnostest:fnostest /vol1 /var/apps /var/log/apps /usr/trim/apps

COPY entrypoint.sh /usr/local/bin/fpk-runner
RUN chmod +x /usr/local/bin/fpk-runner

WORKDIR /work
ENTRYPOINT ["/usr/local/bin/fpk-runner"]
CMD ["help"]
