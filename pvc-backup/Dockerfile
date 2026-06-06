FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    rclone \
    tar \
    gzip \
    && rm -rf /var/lib/apt/lists/*

COPY scripts/*.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh

ENTRYPOINT ["bash", "-c"]
CMD ["backup-to-s3.sh; remove-old-backups.sh"]
