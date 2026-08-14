FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates \
       curl \
       iproute2 \
    && rm -rf /var/lib/apt/lists/*

COPY ddns.sh /usr/local/bin/ddns.sh
RUN chmod +x /usr/local/bin/ddns.sh

ENTRYPOINT ["/usr/local/bin/ddns.sh"]