# --- Stage 1: The Builder ---
FROM postgres:17.11@sha256:67f41722b7a8cbdb868a44a4995c846eddfdc2973bccb291ce937dce88ad5675 AS builder

# Set the initial password required for the setup process.
ENV POSTGRES_PASSWORD=temporary_password_for_build

COPY ./postgresql/init.sh /docker-entrypoint-initdb.d/

# Start a temporary PostgreSQL instance, entrypoint script automatically runs init.sh
# The result is a fully configured database in the /var/lib/postgresql/data directory.
RUN /usr/local/bin/docker-entrypoint.sh postgres & \
    for i in $(seq 1 30); do \
      su - postgres -c "/usr/lib/postgresql/17/bin/pg_isready -U postgres -h 127.0.0.1 -p 5432" && break; \
      sleep 1; \
    done && \
    su - postgres -c "/usr/lib/postgresql/17/bin/pg_ctl -D \"$PGDATA\" -m fast -w stop"


# --- Stage 2: The Final Image ---
FROM postgres:17.11@sha256:67f41722b7a8cbdb868a44a4995c846eddfdc2973bccb291ce937dce88ad5675

COPY --from=builder /var/lib/postgresql/data /var/lib/postgresql/data

EXPOSE 5432

CMD ["postgres"]
