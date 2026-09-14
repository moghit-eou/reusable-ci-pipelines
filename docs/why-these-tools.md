# Why these tools

Every tool here was tested against real projects before being wired into CI. This page
is the short version of those decisions: what was chosen, what was rejected, and the
two design calls that shape everything else.

---

## What runs, and why

| Tool | Role | Why |
|---|---|---|
| **Trivy** | SCA, Container Scanning | Scans both SBOMs and container images. Exposes a direct severity flag, and reads lockfiles as a secondary check. |
| **OSV-Scanner** | SCA, Container Scanning | Backed by Google's OSV database, with fast CVE updates. Catches findings Trivy sometimes reports as severity "unknown". |
| **OpenGrep** | SAST, Dockerfile linting | Same CLI and rule format as Semgrep, without the paid-tier feature gate. |
| **Hadolint** | Container Scanning | Dockerfile-specific linter, run alongside OpenGrep's Dockerfile rules. |

All four are open source, all four emit SARIF, and none of them require an account or
a hosted service.

### OpenGrep rather than Semgrep

Semgrep moved several features behind a paid platform tier. OpenGrep is the community
fork with those features open, and it keeps the same CLI and the same rule format, so
it is not a different tool to learn. Rules are YAML patterns matched against a parsed
AST rather than against text, which is why they can find an insecure call structurally
instead of by grepping for a function name.

### Two SCA tools rather than one

Not redundancy. In testing the two disagreed in ways that mattered: one would report a
finding with no severity score at all while the other supplied a real one, and CVEs
new enough that database coverage differed showed up in one before the other. Each
tool syncs its own upstream database on its own schedule. Running both closes gaps
neither closes alone.

### Rejected

Tools that were tested and not adopted generally failed on one of three things: they
needed a hosted account or an API key to be useful, they emitted no SARIF so their
findings could not join the shared gate, or they duplicated coverage already provided
without adding anything.

---

## Design call 1: scan an SBOM, not the dependency cache

This is the most consequential decision in the SCA pipeline.

Early testing scanned a Maven project's local repository (`~/.m2`, populated by
`mvn dependency:resolve`) directly. The result was over 300 CVE findings, most of them
false positives, with no realistic way to triage them.

The reason is that `~/.m2/repository` is a **cache**, not a dependency list. It holds
everything Maven has ever downloaded on that machine, including transitive artifacts
that were resolved and then discarded, artifacts belonging to other projects, and
multiple versions of the same library. Scanning it answers "what has this machine
downloaded", not "what does this project ship".

Generating a [CycloneDX](https://cyclonedx.org/) SBOM first answers the right
question, and has a second benefit: the scanners stop caring about your package
manager. Adding a language becomes a matter of teaching the SBOM step to produce a
bill of materials, not modifying any scanner. That is what makes
[adding an ecosystem](new-ecosystem.md) cheap.

---

## Design call 2: two gate models

Trivy and OSV-Scanner report **known vulnerabilities**: a CVE, with a database entry
and a CVSS score. OpenGrep and Hadolint report **rule matches**: a pattern fired, or
it did not. There is no CVE and therefore no score.

Forcing both through one CVSS threshold would mean inventing a severity number for
findings that never had one, which misrepresents what was found. So there are two
models, kept apart on purpose:

| | CVSS gate | Rule severity gate |
|---|---|---|
| Used by | Trivy, OSV-Scanner | OpenGrep, Hadolint |
| Measures | Known vulnerability severity | Pattern match severity |
| Fails when | Max CVSS at or above `GATE_FAIL_THRESHOLD` | Any `ERROR` level rule matches |
| Tunable | Yes, per project | By ruleset selection |

### Why a custom SARIF parser

Trivy and OSV-Scanner both produce SARIF and both populate the `security-severity`
property, but they do not share a CLI flag for turning a score into a build decision.
Trivy accepts `--severity CRITICAL` directly; OSV-Scanner has no equivalent. Relying
on each tool's native behaviour would mean two tools failing builds by two different
rules.

Instead both outputs go through one shared function, `parse_sarif.evaluate()`, which
reads the score SARIF already carries and applies one threshold regardless of which
tool produced the finding. One rule, one place to change it, consistent behaviour
across the pipeline.

---

## Design call 3: three pipelines, not one

Container Scanning, SCA and SAST are three separate workflows with three orchestrators
and three gates.

| Pipeline | Scans | Does not scan |
|---|---|---|
| SAST | Your source code | Dependencies, the image, the Dockerfile |
| SCA | Your dependencies, via an SBOM | Source code, the image |
| Container Scanning | The built image and the Dockerfile | Application source, application dependencies |

Three genuinely different artifacts, at three points in the supply chain: what you
wrote, what you depend on, and what you ship. One combined workflow would either run
them in sequence, so a broken step blocks unrelated findings from surfacing, or grow
conditional logic to keep them apart internally. The split gives independent triggers,
parallel execution, and a failure you can read at a glance.

---

## Wanting more depth

These pipelines were built for the Medical Informatics Platform, and the longer
narrative of that rollout, including the case studies behind the numbers on this page,
lives in the
[EBRAINS DevSecOps Handbook](https://github.com/moghit-eou/EBRAIN-DevSecOps-handbook).
It is written for the EBRAINS community and assumes that context, but the reasoning
carries over.
