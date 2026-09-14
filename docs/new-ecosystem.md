# Adding a new ecosystem

SCA works with any language. Adding one means teaching `ci/setup-tools.sh` how to
produce a CycloneDX SBOM for it. The scanners never change, because they only ever see
an SBOM.

Built in today: `maven`, `npm`, `golang`, `generic`, `none`.

---

## Step 1: add a case branch

In `ci/setup-tools.sh`:

```bash
  gradle)
    echo "Generating SBOM for Gradle project"
    mkdir -p target
    ./gradlew cyclonedxBom -q
    cp build/reports/bom.json target/bom.json
    ;;
```

Two things every branch should do: resolve dependencies first, then write the SBOM to
`target/bom.json` (or wherever `SBOM_PATH` points).

## Step 2: install the build tool in the toolbox

In the `sca-toolbox` stage of `ci/docker/Dockerfile`, so the local flow has it:

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
      maven gradle \
    && rm -rf /var/lib/apt/lists/*
```

Skip this if you only run in CI, where you add the toolchain with a setup action
instead.

## Step 3 (CI, optional): cache the dependency directory

Add an `actions/cache` block for whatever directory the ecosystem downloads into. See
[github-actions.md](github-actions.md#dependency-caching).

## Then use it

```bash
make sca PROJECT=./my-gradle-service ECOSYSTEM=gradle
```

```yaml
ECOSYSTEM: gradle
```

---

## Prefer a native CycloneDX generator over `generic`

`ECOSYSTEM: generic` falls back to a Trivy filesystem scan. It needs no toolchain and
is meant to work on any language, which makes it a good way to get coverage on day
one. It is not the right long term choice.

| | Native CycloneDX plugin | `generic` (Trivy filesystem) |
|---|---|---|
| Dependency resolution | Yes, before the SBOM is built | No |
| Transitive dependencies | Complete | Only what appears in lockfiles |
| Version accuracy | Resolved versions | Declared ranges in some cases |
| Rate limiting | Avoided, dependencies already cached | Can hit registry rate limits on cold runs |

Without a resolve step, dependencies may be fetched during the scan itself, which is
where public registry rate limits (Maven Central in particular) start failing builds
intermittently. The built in ecosystems all resolve first, inside `setup-tools.sh`, so
the SBOM is generated from an already populated local cache.

Use `generic` to get coverage quickly, then move to a proper ecosystem branch once the
project matters.
