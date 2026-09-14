# DevSecOps Security Pipelines

Three security pipelines, **SAST**, **SCA** and **Container Scanning**, that run the
same way on your laptop and in GitHub Actions.

Each pipeline runs open source scanners, normalises their output to
[SARIF](https://sarifweb.azurewebsites.net/), and applies one shared gate. Locally
they run in purpose-built Docker images through `make`. In CI they run natively on
the runner through the same `ci/` scripts. Nothing differs between the two except
where the scripts execute, so a finding you reproduce locally is the finding CI
reports.

Built during **Google Summer of Code 2026** with [EBRAINS](https://www.ebrains.eu/),
following the
[OWASP DevSecOps Guideline](https://owasp.org/www-project-devsecops-guideline/), and
running in production across the
[Medical Informatics Platform](https://github.com/Medical-Informatics-Platform).

---

## The pipelines

| Pipeline | Scanners | What it inspects | Fails on |
|---|---|---|---|
| **SAST** | OpenGrep with [semgrep-rules](https://github.com/semgrep/semgrep-rules) | Your source code | Any `ERROR` severity rule match |
| **SCA** | Trivy, OSV-Scanner | A CycloneDX SBOM of your dependencies | CVSS at or above the threshold |
| **Container Scanning** | Hadolint, OpenGrep, Trivy, OSV-Scanner | The Dockerfile **and** the built image | Either of the above |

They are deliberately independent. No shared state, no ordering constraints. Run one,
run all three, run them in parallel.

**SAST** matches pattern based rules against your own code. **SCA** generates a
CycloneDX SBOM first and scans that, which decouples the scanners from the package
manager: adding a language means teaching the SBOM step to produce a bill of
materials, not modifying the scanners. **Container Scanning** does both against one
image, linting the Dockerfile and scanning the built layers, then merges all four
SARIF reports before applying the gate.

Why these particular tools, and what was rejected: [docs/why-these-tools.md](docs/why-these-tools.md).

---

## Quick start

**Requirements:** Docker, `make` and Bash. The scanners install themselves inside the
images, so there is nothing else to set up.

```bash
git clone https://github.com/moghit-eou/reusable-ci-pipelines.git
cd reusable-ci-pipelines

make sast PROJECT=./test-golang
make sca  PROJECT=./test-maven ECOSYSTEM=maven
```

Container Scanning needs the image built first:

```bash
docker build -t test-maven:scan ./test-maven
make container-scan IMAGE=test-maven:scan SCAN_TYPE=sca
```

The first run builds the toolbox image, which takes a few minutes because it
downloads the scanners and the Trivy vulnerability database. Later runs reuse the
cached layers and take seconds.

SARIF reports are written **inside `PROJECT`**. `make clean` removes them along with
the toolbox images.

More on the local flow, including how to change settings without rebuilding:
[docs/local-runs.md](docs/local-runs.md).

---

## Adopt it in your repository

Copy two folders. No submodule, no action to install, no dependency on this
repository afterwards.

| Step | What to do |
|---|---|
| 1 | Copy `ci/` to your repository root. Drop `ci/docker/` unless you also want the local `make` flow. |
| 2 | Copy the workflows you need from `.github/workflows/`. |
| 3 | Point them at your code by editing the `env:` block. |

The minimum to edit:

```yaml
    env:
      PROJECT: .                    # folder to scan, relative to the repository root
      ECOSYSTEM: maven              # SCA only: maven | npm | golang | generic | none
      GATE_FAIL_THRESHOLD: "8.0"
      GATE_WARN_THRESHOLD: "5.0"
      SARIF_CATEGORY: sca-backend   # must be unique per job
      ARTIFACT_NAME: sca-report     # must be unique per job
```

For a repository with several projects in it, copy the job once per project and point
`PROJECT` at each folder.

Every job also needs:

```yaml
permissions:
  contents: read
  security-events: write   # to upload SARIF to the Security tab
```

Full walkthrough of the three workflows, including dependency caching and the
gotchas: [docs/github-actions.md](docs/github-actions.md).

---

## Working examples

These pipelines run in production in the Medical Informatics Platform. Each repository
is a different adoption shape, so pick the one closest to yours and copy from it.

| Repository | Shape | What to look at |
|---|---|---|
| [platform-backend](https://github.com/Medical-Informatics-Platform/platform-backend/tree/master/.github/workflows) | One Maven project at the repository root | The simplest case: `PROJECT: .`, `ECOSYSTEM: maven`, one job per pipeline |
| [platform-ui](https://github.com/Medical-Informatics-Platform/platform-ui/tree/master/.github/workflows) | One npm project at the repository root | The same shape with `ECOSYSTEM: npm`. Only the ecosystem and the rulesets change |
| [datacatalog PR #18](https://github.com/Medical-Informatics-Platform/datacatalog/pull/18) | Three projects in one repository | A build matrix covering a Maven backend, an npm frontend and a Python project on `generic`, with per-project rulesets and SARIF categories |

The `datacatalog` case is the useful one if your repository holds more than one
project: it shows how far the `env:` block alone gets you, without touching any
pipeline code.

Those repositories vendor `ci/` in a deliberately simplified form, with values written
directly into the scripts rather than read from the environment. That is a choice made
for their maintainers, who wanted a folder they could read without learning a
configuration layer first. This repository keeps the configurable version, which is
what you want when adopting into an unknown project.

---

## The gate

SCA and Container Scanning read the `security-severity` property (the CVSS score) from
every SARIF result and take the maximum:

| Max CVSS | Status | Exit code |
|---|---|---|
| at or above `GATE_FAIL_THRESHOLD` | **FAILED** | 1, blocks the pipeline |
| at or above `GATE_WARN_THRESHOLD`, below fail | **WARNING** | 0, logged only |
| below warn | **PASSED** | 0 |
| tool crashed or wrote no SARIF | **ERROR** | 1, a broken scanner is never a pass |

Defaults are `8.0` and `5.0`.

SAST gates differently. OpenGrep runs with `--severity=ERROR --error`, so any `ERROR`
level rule match fails the job. A pattern match has no CVE behind it and therefore no
CVSS score to threshold on, which is why the two models are kept apart rather than
merged. See [docs/why-these-tools.md](docs/why-these-tools.md#design-call-2-two-gate-models).

Reports upload **even when the gate fails**, because the upload steps are guarded on
the SARIF file existing, not on the scan's exit code. A blocked build still publishes
its findings.

---

## Reading the reports

SARIF is JSON, readable but unpleasant by hand. Four ways to look at it:

1. **GitHub Security tab**, uploaded automatically by the workflows, with findings
   mapped to lines of code.
2. **VS Code**, with the
   [SARIF Viewer](https://marketplace.visualstudio.com/items?itemName=MS-SarifVSCode.sarif-viewer)
   extension. The fastest way to triage a local `make` run.
3. **[SARIF Web Viewer](https://microsoft.github.io/sarif-web-component/)**, nothing to
   install, good for sharing a report with someone who has no checkout.
4. **The workflow artifact**, useful when a run fails before the Security tab upload.

---

## Want the longer story?

This repository is self-contained: everything you need to run, configure and adopt the
pipelines is here and in `docs/`.

If you want the reasoning in more depth, the
**[EBRAINS DevSecOps Handbook](https://github.com/moghit-eou/EBRAIN-DevSecOps-handbook)**
is a companion write-up of one production rollout: the assessment that started it, the
case studies behind each tool decision, and what went wrong on the way. It is written
for the EBRAINS community and assumes that context, so it is extra reading rather than
a prerequisite.

---

## Documentation

| Page | What it covers |
|---|---|
| [docs/github-actions.md](docs/github-actions.md) | Running in CI: the three workflows step by step, permissions, dependency caching |
| [docs/local-runs.md](docs/local-runs.md) | Running locally: the Makefile, the toolbox images, the env files |
| [docs/configuration.md](docs/configuration.md) | Every environment variable, gate thresholds, Semgrep ruleset selection |
| [docs/new-ecosystem.md](docs/new-ecosystem.md) | Adding a language the SBOM step does not know yet |
| [docs/suppressions.md](docs/suppressions.md) | Suppressing a false positive or an accepted risk |
| [docs/why-these-tools.md](docs/why-these-tools.md) | Tool choices, rejected alternatives, the two gate models |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Empty scan targets, split verdicts between tools |

---

## Related resources

- **Scanners**: [Trivy](https://trivy.dev/), [OSV-Scanner](https://google.github.io/osv-scanner/),
  [OpenGrep](https://github.com/opengrep/opengrep), [Hadolint](https://github.com/hadolint/hadolint)
- **Rulesets**: [semgrep-rules](https://github.com/semgrep/semgrep-rules),
  [Semgrep Registry](https://semgrep.dev/explore)
- **Standards**: [SARIF](https://sarifweb.azurewebsites.net/), [CycloneDX](https://cyclonedx.org/)
- **Guideline**: [OWASP DevSecOps Guideline](https://owasp.org/www-project-devsecops-guideline/)

---

## License

Licensed under the [MIT License](LICENSE).

You may use, modify and redistribute this project, including commercially. The only
condition is that the copyright and license notice stays with copies or substantial
portions of the code.
