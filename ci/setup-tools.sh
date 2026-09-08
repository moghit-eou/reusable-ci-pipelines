#!/bin/bash
set -e          # stop the pipeline if any command fails
set -o pipefail # Prevents silent pipeline successes if the curl download drops
set -u          # treat unset variables as an error

trap 'echo "[setup-tools] ERROR: command failed (exit $?) at line $LINENO: $BASH_COMMAND" >&2' ERR

# Tool versions and the SHA256 of the release asset we download.
# The "# renovate:" markers let Renovate bump version and checksum together
# (see renovate.json). When overriding a *_VERSION via env, the matching
# *_SHA256 must be overridden as well or verification will fail.

# renovate: datasource=github-release-attachments depName=aquasecurity/trivy
TRIVY_VERSION="${TRIVY_VERSION:-v0.74.0}"
TRIVY_SHA256="${TRIVY_SHA256:-2ae6fe3ee734b7fdf11335663e18c75ea12dccc76062f09f164a3b0f8be4371a}"

# renovate: datasource=github-release-attachments depName=google/osv-scanner
OSV_SCANNER_VERSION="${OSV_SCANNER_VERSION:-v2.5.1}"
OSV_SCANNER_SHA256="${OSV_SCANNER_SHA256:-f9f25499a2c8cc367b3af45df2ea7eeca7fbccceab9c35079968f4b3652194be}"

# renovate: datasource=github-release-attachments depName=opengrep/opengrep
OPENGREP_VERSION="${OPENGREP_VERSION:-v1.29.0}"
OPENGREP_SHA256="${OPENGREP_SHA256:-3365ef49d04893e01338d85d9bbd49b2bd5261ad4c9c0df0a6a0f8d44232ae13}"

# renovate: datasource=git-refs depName=https://github.com/semgrep/semgrep-rules
SEMGREP_RULES_REF="${SEMGREP_RULES_REF:-40b8c63f75dc7c22c8a77482d73bfb864b146f7e}"
SEMGREP_RULES_DIR="semgrep-rules"

# renovate: datasource=github-release-attachments depName=hadolint/hadolint
HADOLINT_VERSION="${HADOLINT_VERSION:-v2.14.0}"
HADOLINT_SHA256="${HADOLINT_SHA256:-6bf226944684f56c84dd014e8b979d27425c0148f61b3bd99bcc6f39e9dc5a47}"

# renovate: datasource=maven depName=org.cyclonedx:cyclonedx-maven-plugin
CYCLONEDX_MAVEN_VERSION="${CYCLONEDX_MAVEN_VERSION:-2.9.3}"

# @cyclonedx/cyclonedx-npm is pinned, with its whole dependency tree, by the
# sha512 integrity fields in sbom-npm/package-lock.json next to this script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# renovate: datasource=github-release-attachments depName=CycloneDX/cyclonedx-gomod
CYCLONEDX_GOMOD_VERSION="${CYCLONEDX_GOMOD_VERSION:-v1.12.0}"
CYCLONEDX_GOMOD_SHA256="${CYCLONEDX_GOMOD_SHA256:-004b9f5cc595b797fb5423e2ae4c97bcf0f18c712ed2faee1640b09e5efd6d15}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

# --- Flag parsing -----------------------------------------------------
INSTALL_TOOL="none"
SBOM_ECOSYSTEM="none"
SCAN_PATH="."

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-tool)
      [[ $# -ge 2 ]] || { echo "[setup-tools] --install-tool requires a value (e.g. trivy,osv-scanner|all)" >&2; exit 1; }
      INSTALL_TOOL="$2"
      shift 2
      ;;
    --sbom-ecosystem)
      [[ $# -ge 2 ]] || { echo "[setup-tools] --sbom-ecosystem requires a value (e.g. maven|npm|none)" >&2; exit 1; }
      SBOM_ECOSYSTEM="$2"
      shift 2
      ;;
    --scan-path)
      [[ $# -ge 2 ]] || { echo "[setup-tools] --scan-path requires a value (e.g. .|src)" >&2; exit 1; }
      SCAN_PATH="$2"
      shift 2
      ;;
    *)
      echo "[setup-tools] Unknown flag: $1" >&2
      exit 1
      ;;
  esac
done

should_install() {
  [[ "$INSTALL_TOOL" == "all" || ",$INSTALL_TOOL," == *",$1,"* ]]
}

# Download a file and refuse to proceed unless its SHA256 matches the pinned one
download_and_verify() {
  local url="$1" dest="$2" sha256="$3"
  curl -fsSL --retry 3 "${url}" -o "${dest}"
  echo "${sha256}  ${dest}" | sha256sum -c -
}

# --- Trivy --------------------------------------------------------------
if should_install "trivy"; then
  echo "[setup-tools] Installing Trivy ${TRIVY_VERSION}"
  TRIVY_TARBALL="trivy_${TRIVY_VERSION#v}_Linux-64bit.tar.gz"
  download_and_verify \
    "https://github.com/aquasecurity/trivy/releases/download/${TRIVY_VERSION}/${TRIVY_TARBALL}" \
    "${TMP_DIR}/${TRIVY_TARBALL}" \
    "${TRIVY_SHA256}"
  sudo tar -xzf "${TMP_DIR}/${TRIVY_TARBALL}" -C /usr/local/bin trivy
  trivy --version
  echo "Trivy installed OK"
fi

# --- OSV Scanner ----------------------------------------------------------
if should_install "osv-scanner"; then
  echo "[setup-tools] Installing OSV Scanner ${OSV_SCANNER_VERSION}"
  download_and_verify \
    "https://github.com/google/osv-scanner/releases/download/${OSV_SCANNER_VERSION}/osv-scanner_linux_amd64" \
    "${TMP_DIR}/osv-scanner" \
    "${OSV_SCANNER_SHA256}"
  sudo install -m 0755 "${TMP_DIR}/osv-scanner" /usr/local/bin/osv-scanner
  osv-scanner --version
  echo "OSV Scanner installed OK"
fi

# --- OpenGrep -------------------------------------------------------------
if should_install "opengrep"; then
  echo "[setup-tools] Installing OpenGrep ${OPENGREP_VERSION}"
  download_and_verify \
    "https://github.com/opengrep/opengrep/releases/download/${OPENGREP_VERSION}/opengrep_manylinux_x86" \
    "${TMP_DIR}/opengrep" \
    "${OPENGREP_SHA256}"
  sudo install -m 0755 "${TMP_DIR}/opengrep" /usr/local/bin/opengrep
  opengrep --version
  echo "OpenGrep installed OK"
fi

# --- Semgrep community ruleset (cloned, not registry) ---------
if should_install "semgrep-rules"; then
  echo "[setup-tools] Cloning semgrep-rules @ ${SEMGREP_RULES_REF}"
  rm -rf "${SEMGREP_RULES_DIR}"
  git clone --quiet https://github.com/semgrep/semgrep-rules.git "${SEMGREP_RULES_DIR}"
  git -C "${SEMGREP_RULES_DIR}" checkout --quiet "${SEMGREP_RULES_REF}"
  echo "semgrep-rules ready at ${SEMGREP_RULES_DIR} (ref: ${SEMGREP_RULES_REF})"
fi

# --- Hadolint ---------------------------------------------------------
if should_install "hadolint"; then
  echo "[setup-tools] Installing Hadolint ${HADOLINT_VERSION}"
  download_and_verify \
    "https://github.com/hadolint/hadolint/releases/download/${HADOLINT_VERSION}/hadolint-linux-x86_64" \
    "${TMP_DIR}/hadolint" \
    "${HADOLINT_SHA256}"
  sudo install -m 0755 "${TMP_DIR}/hadolint" /usr/local/bin/hadolint
  hadolint --version
  echo "Hadolint installed OK"
fi

# --- SBOM generation ----------------------------------------------------
case "$SBOM_ECOSYSTEM" in
  maven)
    echo "Generating SBOM for Maven project ... this may take a while"
    # -C (--strict-checksums): fail on any artifact whose published checksum does
    # not match instead of warning. Maven has no lockfile, so this plus exact
    # versions in the pom is the strongest pin available.
    mvn -B -ntp -C dependency:resolve -q
    mvn -B -ntp -C "org.cyclonedx:cyclonedx-maven-plugin:${CYCLONEDX_MAVEN_VERSION}:makeAggregateBom" -q
    ;;
  npm)
    echo "Generating SBOM for NPM project ... this may take a while"
    # cyclonedx-npm reads the installed dependency tree, so resolve first, the
    # mirror image of `mvn dependency:resolve` above. --ignore-scripts: the SBOM
    # step must never execute lifecycle scripts of the scanned dependencies.
    npm ci --ignore-scripts --no-audit --no-fund --loglevel=error
    # The SBOM tool itself comes from ci/sbom-npm/package-lock.json, so every
    # byte it runs is sha512-pinned, unlike `npx <pkg>@<version>` which resolves
    # the tool's own dependencies fresh on every run.
    npm ci --ignore-scripts --no-audit --no-fund --loglevel=error --prefix "${SCRIPT_DIR}/sbom-npm"
    mkdir -p target
    "${SCRIPT_DIR}/sbom-npm/node_modules/.bin/cyclonedx-npm" --output-file target/bom.json
    ;;
  golang|go)
    echo "Generating SBOM for Go project ... this may take a while"
    mkdir -p target
    # Prebuilt release binary, SHA256 pinned like the scanners above. Still needs
    # the Go toolchain at runtime: cyclonedx-gomod shells out to `go` to resolve modules.
    GOMOD_TARBALL="cyclonedx-gomod_${CYCLONEDX_GOMOD_VERSION#v}_linux_amd64.tar.gz"
    download_and_verify \
      "https://github.com/CycloneDX/cyclonedx-gomod/releases/download/${CYCLONEDX_GOMOD_VERSION}/${GOMOD_TARBALL}" \
      "${TMP_DIR}/${GOMOD_TARBALL}" \
      "${CYCLONEDX_GOMOD_SHA256}"
    tar -xzf "${TMP_DIR}/${GOMOD_TARBALL}" -C "${TMP_DIR}" cyclonedx-gomod
    "${TMP_DIR}/cyclonedx-gomod" mod -json -output target/bom.json
    ;;
  generic|auto)
    echo "Generating SBOM via generic Trivy filesystem scan (less accurate)"
    mkdir -p target
    trivy fs --format cyclonedx --output target/bom.json "${SCAN_PATH:-.}"
    ;;
  none)
    echo "No SBOM generation needed"
    ;;
  *)
    echo "Unknown SBOM_ECOSYSTEM: $SBOM_ECOSYSTEM" >&2
    exit 1
    ;;
esac
