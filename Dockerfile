# Toolbox image for running DB restores on Railway.
# Contains: postgresql-client (psql, pg_restore), awscli, bash, gzip.
#
# Deploy as a Railway service. Leave the start command as `sleep infinity`
# so the container stays up and you can shell in to run restores manually.

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      postgresql-client \
      awscli \
      ca-certificates \
      bash \
      gzip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY restore.sh      /app/restore.sh
COPY list-backups.sh /app/list-backups.sh
RUN chmod +x /app/restore.sh /app/list-backups.sh

# Keep the container alive so we can exec into it from the Railway shell.
CMD ["sleep", "infinity"]
