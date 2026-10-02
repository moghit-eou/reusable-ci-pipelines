# Reproducibility

Not everything in these pipelines is pinned equally. In one sentence:

> Security-tool versions are reproducibly pinned
> System and build-tool versions follow the runner or container image unless explicitly overridden.

So the same commit, scanned twice, always runs the same scanners. It does not
necessarily run on the same Java, Maven, Node or Docker. And it is checked against
vulnerability data that changes every day, on purpose.

This page lists which is which, and what to do when a result changes.

---

## Pinned

These are identical on every run. Changing them takes a commit, usually a Renovate
pull request.

| What | How it is pinned | Where |
|---|---|---|
| Trivy, OSV-Scanner, OpenGrep, Hadolint | Version + SHA256 of the release asset | `ci/setup-tools.sh` |
| `semgrep-rules` | Commit SHA | `ci/setup-tools.sh` |
| `cyclonedx-maven-plugin` | Exact version, and `mvn -C` (strict checksums) | `ci/setup-tools.sh` |
| `cyclonedx-npm` and its dependencies | sha512 integrity in a lockfile | `ci/sbom-npm/package-lock.json` |
| `cyclonedx-gomod` | Version + SHA256 | `ci/setup-tools.sh` |
| GitHub Actions | Commit SHA | `.github/workflows/*.yml` |
| Python (CI) | `setup-python` with an exact version | `.github/workflows/*.yml` |
| Toolbox base image | `ubuntu:24.04@sha256:...` | `ci/docker/Dockerfile` |

## Follows the runner or the image

Nobody chose these versions. They are whatever is installed on the machine the
pipeline runs on.

| What | Comes from |
|---|---|
| Java, Maven, Node, npm, Docker, git, curl (CI) | The GitHub runner image behind `runs-on: ubuntu-latest`. GitHub updates it every week and moves `latest` to a new Ubuntu release from time to time |
| Maven, npm, Go, Docker, Python (local, toolbox image) | `apt-get install` without versions, so the Ubuntu archive on the day the image is built |

`ci/setup-tools.sh` prints these versions, and the runner image version, in a block
called **Unpinned environment**, before generating the SBOM.

## Fetched at run time, on purpose

| What | Why it is not pinned |
|---|---|
| The `auto` and `p/default` Semgrep rulesets | Downloaded from semgrep.dev on every scan. They add useful rules that are not in `semgrep-rules`. Drop them from `SEMGREP_CONFIG_RULESETS` if you need a fully pinned SAST run |
| The Go toolchain (`GOTOOLCHAIN=auto`, toolbox image) | Fetches the Go version the scanned project's `go.mod` asks for, verified against the Go checksum database. It follows your project, not the date |

## Changes by design

The Trivy vulnerability database and the OSV data are updated continuously. A
dependency that passed yesterday can fail today because a CVE was published
overnight, with no change to your code or to the pipeline. That is the reason the
workflows also run on a weekly schedule.

---

## When a result changes and the code did not

Check, in this order:

1. **The scanner.** Each SARIF file records the scanner and its version under
   `runs[].tool.driver`. A Renovate bump since the last run explains a lot.
2. **The data.** Look up the finding's CVE or advisory date. Most changes are a new
   advisory, not a pipeline change.
3. **The environment.** Compare the **Unpinned environment** block of the two runs'
   `setup-tools.sh` logs: runner image, Java, Maven, Node, npm.

## Pinning more

If your project needs more than this, these are the levers, from cheapest to most
work:

| To pin | Do this | Cost |
|---|---|---|
| The runner OS | `runs-on: ubuntu-24.04` instead of `ubuntu-latest` | No bot updates it, so bump it by hand when GitHub retires the image. The image still gets weekly patch updates |
| Java, Node | Add `actions/setup-java` / `actions/setup-node` with an exact version, pinned to a commit SHA like the other actions | One step per job |
| SAST rules | Remove `auto` and `p/default`, keep only the cloned `semgrep-rules` packs | Fewer rules |
| Toolbox Ubuntu packages | Build from a dated Ubuntu snapshot archive instead of the live archive | Not done here: pinning `apt` versions directly breaks builds, because old versions disappear from the archive |

None of these are applied here by default: the workflows stay short, and the
scanners, which decide what is found, are already pinned.
