# Stage 1: Adding additional packages (curl) to Build Stage
FROM registry.access.redhat.com/ubi9:9.6 AS ubi-micro-build
RUN mkdir -p /mnt/rootfs
RUN dnf install --installroot /mnt/rootfs curl --releasever 9 --setopt install_weak_deps=false --nodocs -y && \
    dnf --installroot /mnt/rootfs clean all && \
    rpm --root /mnt/rootfs -e --nodeps setup

# Stage 2: Build Stage
FROM quay.io/keycloak/keycloak:26.5 AS builder

# Environment variables for build to optimized Keycloak
ENV KC_DB=postgres
ENV KC_HEALTH_ENABLED=true
ENV KC_METRICS_ENABLED=true

WORKDIR /opt/keycloak

# Build Keycloak, including optimazation for selected DB
RUN /opt/keycloak/bin/kc.sh build

# Stage 3: Runtime Stage
FROM quay.io/keycloak/keycloak:26.5

# Environment variables for database connection
ENV KC_DB=postgres

COPY --from=ubi-micro-build /mnt/rootfs /
COPY --from=builder /opt/keycloak/ /opt/keycloak/

COPY ./certificates/localhost/localhostDomain.crt /etc/x509/https/localhost.crt
COPY ./certificates/localhost/localhostDomain.key /etc/x509/https/localhostCert.key

# HTTPS port
EXPOSE 9443
# Management port
EXPOSE 9000

ENTRYPOINT ["/opt/keycloak/bin/kc.sh", "start", "--optimized"]
