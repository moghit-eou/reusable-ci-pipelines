# Configuration

Set these in a workflow `env:` block for CI, or in `ci/docker/env/*.env` for local
runs. Everything has a working default, so you only override what you need.

In `.env` files, write values **without quotes**. `--env-file` does not strip them.

---

## The gate

| Variable | Default | Purpose |
|---|---|---|
| `GATE_FAIL_THRESHOLD` | `8.0` | CVSS at or above this fails the pipeline |
| `GATE_WARN_THRESHOLD` | `5.0` | CVSS at or above this warns but passes |

```yaml
GATE_FAIL_THRESHOLD: "7.0"
GATE_WARN_THRESHOLD: "4.0"
```

These apply to SCA and Container Scanning, the two pipelines whose findings carry CVSS
scores. SAST has no threshold: OpenGrep runs with `--severity=ERROR --error` and any
`ERROR` level match fails the job.

Raising `GATE_FAIL_THRESHOLD` is the usual first move when adopting the pipelines into
an existing project with a backlog of findings. Start permissive, then tighten.

---

## What to scan

| Variable | Default | Purpose |
|---|---|---|
| `PROJECT` | | Folder to scan, relative to the repository root |
| `ECOSYSTEM` | `none` | SCA only: `maven`, `npm`, `golang`, `generic`, `none` |
| `SARIF_CATEGORY` | | Security tab category, must be unique per job |
| `ARTIFACT_NAME` | | Workflow artifact name, must be unique per job |

---

## SAST

| Variable | Default | Purpose |
|---|---|---|
| `SEMGREP_CONFIG_RULESETS` | built in list | Space separated rulesets |
| `OPENGREP_EXCLUDE` | `*.sarif ci/ Dockerfile* ...` | Paths to skip, relative to `PROJECT` |
| `OPENGREP_SARIF_OUTPUT` | `sast-opengrep.sarif` | Report filename |

---

## SCA

| Variable | Default | Purpose |
|---|---|---|
| `SBOM_ECOSYSTEM` | `none` | Which SBOM generator to use |
| `SBOM_PATH` | `target/bom.json` | SBOM location, relative to `PROJECT` |
| `TRIVY_IGNOREFILE` | `suppress_trivy.yaml` | Trivy suppressions |
| `OSV_IGNOREFILE` | `suppress_osv_scanner.toml` | OSV-Scanner suppressions |
| `TRIVY_SARIF_OUTPUT` | `sca-trivy.sarif` | Trivy report |
| `OSV_SARIF_OUTPUT` | `sca-osv-scanner.sarif` | OSV-Scanner report |
| `SCA_MERGED_SARIF_OUTPUT` | `sca-merged.sarif` | Combined report |

---

## Container Scanning

| Variable | Default | Purpose |
|---|---|---|
| `IMAGE_NAME` | | Image to scan, must already be built |
| `DOCKERFILE_PATH` | `Dockerfile` | Dockerfile name, relative to `PROJECT` |
| `TRIVY_SCA_SARIF_OUTPUT` | `container-sca-trivy.sarif` | Image CVEs from Trivy |
| `OSV_SCA_SARIF_OUTPUT` | `container-sca-osv-scanner.sarif` | Image CVEs from OSV-Scanner |
| `OPENGREP_SAST_SARIF_OUTPUT` | `container-sast-opengrep.sarif` | Dockerfile findings from OpenGrep |
| `HADOLINT_SAST_SARIF_OUTPUT` | `container-sast-hadolint.sarif` | Dockerfile findings from Hadolint |
| `MERGED_SARIF_OUTPUT` | `container-scan-merged.sarif` | All four merged |

`MERGED_SARIF_OUTPUT` is the one entry here that is not read from the environment by
the script itself. The merge step is a CLI argument, `--merge-output`, and the
workflow passes the variable through to it. If you call `container_scan.py` directly,
pass the flag.

---

## Choosing Semgrep rulesets

`SEMGREP_CONFIG_RULESETS` is a space separated list, and entries come in two kinds.

**Local folders** from the pinned
[semgrep-rules](https://github.com/semgrep/semgrep-rules) clone. Browse that repository
and add any top level directory:

```yaml
SEMGREP_CONFIG_RULESETS: >-
  ${{ github.workspace }}/../tools/semgrep-rules/generic
  ${{ github.workspace }}/../tools/semgrep-rules/java
  ${{ github.workspace }}/../tools/semgrep-rules/python
  ${{ github.workspace }}/../tools/semgrep-rules/terraform
```

**Registry packs** from [semgrep.dev/explore](https://semgrep.dev/explore), referenced
as `p/<name>`:

```yaml
  p/default p/owasp-top-ten p/secrets auto
```

| Entry | Behaviour |
|---|---|
| Local folder path | Uses the **pinned** ruleset commit, fully reproducible |
| `p/<name>` | Fetched from the registry at scan time, may drift between runs |
| `auto` | Language detected registry rules |

For reproducible results, prefer local folders. `SEMGREP_RULES_REF` in
`ci/setup-tools.sh` pins the exact ruleset commit, so the same input always yields the
same findings.

Stacking a few targeted packs generally beats `auto`, which pulls in everything and
gets noisy. The trade-off is real in both directions: too general and you miss things,
too specific and you spend your time triaging. Start with the language pack for your
stack plus `p/default`, then adjust.

In the local Docker flow the same setting lives in `ci/docker/env/sast.env`, pointing
at `/app/semgrep-rules/...`.

---

## Tool versions

Pinned in `ci/setup-tools.sh` and overridable by environment variable. Every binary is
verified against a pinned SHA256, so overriding a `*_VERSION` requires overriding the
matching `*_SHA256` too, or verification fails by design.

[Renovate](https://docs.renovatebot.com/) markers above each pair keep version and
checksum in sync automatically.
