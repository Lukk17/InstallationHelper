# Stage 1: Adding additional packages (curl) to Build Stage
FROM registry.access.redhat.com/ubi9:9.6@sha256:dec374e05cc13ebbc0975c9f521f3db6942d27f8ccdf06b180160490eef8bdbc AS ubi-micro-build
RUN mkdir -p /mnt/rootfs
RUN dnf install --installroot /mnt/rootfs curl --releasever 9 --setopt install_weak_deps=false --nodocs -y && \
    dnf --installroot /mnt/rootfs clean all && \
    rpm --root /mnt/rootfs -e --nodeps setup

# Stage 2: Build Stage
FROM quay.io/keycloak/keycloak:26.5@sha256:45ae20191531eb608ddb0b775d012b40d3e4f942697f3214694887dd7c108d13 AS builder

# Environment variables for build to optimized Keycloak
ENV KC_DB=postgres
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true

WORKDIR /opt/keycloak

# Build Keycloak, including optimazation for selected DB
RUN /opt/keycloak/bin/kc.sh build

# Stage 3: Runtime Stage
FROM quay.io/keycloak/keycloak:26.5@sha256:45ae20191531eb608ddb0b775d012b40d3e4f942697f3214694887dd7c108d13

# Environment variables for database connection
ENV KC_DB=postgres

COPY --from=ubi-micro-build /mnt/rootfs /
COPY --from=builder /opt/keycloak/ /opt/keycloak/

COPY ./certificates/localhost/localhost.crt /etc/x509/https/localhost.crt
COPY ./certificates/localhost/localhost.key /etc/x509/https/localhostCert.key

COPY ./Keycloak/export/config/local-realm-export.json /opt/keycloak/data/import/local-realm-export.json

# HTTPS port
EXPOSE 9443
# Management port
EXPOSE 9000

ENTRYPOINT ["/opt/keycloak/bin/kc.sh", "start", "--optimized", "--import-realm"]
