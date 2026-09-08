# =============================================================================
# Stage: toolbox-base -- OS-level deps + ci/ scripts only. No scanning
#                         tools installed here.
# =============================================================================
# Digest-pinned: the tag alone can be re-pointed upstream at any time. Renovate
# bumps the digest (dockerfile manager, pinDigests) after the 7-day release age.
FROM ubuntu:26.04@sha256:2260313b31c8c011cd2eebe728008efac1b3982be73eb71348ea2648d2c0e09b AS toolbox-base

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git sudo python3 python3-pip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY ci/setup-tools.sh /app/ci/setup-tools.sh
RUN chmod +x /app/ci/setup-tools.sh


# =============================================================================
# Stage: toolbox-installer -- installs Trivy/OSV-Scanner/Hadolint/OpenGrep
#                              + semgrep-rules AND downloads the Trivy DB.
# =============================================================================
FROM toolbox-base AS toolbox-installer

RUN bash /app/ci/setup-tools.sh --install-tool \
        trivy,osv-scanner,hadolint,opengrep,semgrep-rules

ENV TRIVY_CACHE_DIR=/app/trivy-db-cache
RUN trivy image --download-db-only --cache-dir "${TRIVY_CACHE_DIR}" \
 && trivy image --download-java-db-only --cache-dir "${TRIVY_CACHE_DIR}"


# =============================================================================
# Stage: sast-toolbox -- OpenGrep + semgrep-rules only
# =============================================================================
FROM toolbox-base AS sast-toolbox

COPY --from=toolbox-installer /usr/local/bin/opengrep /usr/local/bin/opengrep
COPY --from=toolbox-installer /app/semgrep-rules /app/semgrep-rules

COPY ci/ /app/ci/
RUN chmod +x /app/ci/setup-tools.sh /app/ci/docker/entrypoints/*.sh

WORKDIR /workspace
ENTRYPOINT ["python3", "/app/ci/sast_scan.py"]


# =============================================================================
# Stage: sca-toolbox -- Trivy + OSV-Scanner + Trivy DB + build toolchains
#                       for the SBOM step (Maven, Go). Node/npm is not installed.
# =============================================================================
FROM toolbox-base AS sca-toolbox

# Build toolchains needed by `setup-tools.sh --sbom-ecosystem <maven|golang>`.
# cyclonedx-gomod is built at run time by `go install` (version pinned, verified
# against the Go checksum database), so the Go toolchain must be present here.
RUN apt-get update && apt-get install -y --no-install-recommends \
      maven npm golang-go \
    && rm -rf /var/lib/apt/lists/*

# Ubuntu's Go package defaults to GOTOOLCHAIN=local. `auto` lets Go fetch the
# newer toolchain a project's go.mod demands, so projects on a newer Go than the
# distro's still produce an SBOM.
ENV GOTOOLCHAIN=auto

COPY --from=toolbox-installer /usr/local/bin/trivy /usr/local/bin/trivy
COPY --from=toolbox-installer /usr/local/bin/osv-scanner /usr/local/bin/osv-scanner
ENV TRIVY_CACHE_DIR=/app/trivy-db-cache
COPY --from=toolbox-installer /app/trivy-db-cache /app/trivy-db-cache

COPY ci/ /app/ci/
RUN chmod +x /app/ci/setup-tools.sh /app/ci/docker/entrypoints/*.sh

WORKDIR /workspace
ENTRYPOINT ["/app/ci/docker/entrypoints/sca-entrypoint.sh"]


# =============================================================================
# Stage: container-scan-toolbox -- Trivy + OSV-Scanner + OpenGrep + Hadolint
#                                    + Trivy DB + Docker CLI
# =============================================================================
FROM toolbox-base AS container-scan-toolbox

RUN apt-get update && apt-get install -y --no-install-recommends docker.io \
    && rm -rf /var/lib/apt/lists/*

COPY --from=toolbox-installer /usr/local/bin/trivy /usr/local/bin/trivy
COPY --from=toolbox-installer /usr/local/bin/osv-scanner /usr/local/bin/osv-scanner
COPY --from=toolbox-installer /usr/local/bin/opengrep /usr/local/bin/opengrep
COPY --from=toolbox-installer /usr/local/bin/hadolint /usr/local/bin/hadolint
COPY --from=toolbox-installer /app/semgrep-rules /app/semgrep-rules
ENV TRIVY_CACHE_DIR=/app/trivy-db-cache
COPY --from=toolbox-installer /app/trivy-db-cache /app/trivy-db-cache

COPY ci/ /app/ci/
RUN chmod +x /app/ci/setup-tools.sh /app/ci/docker/entrypoints/*.sh

WORKDIR /workspace
ENTRYPOINT ["python3", "/app/ci/container_scan.py"]
