# Troubleshooting

## When the target has nothing to scan

A run can end like this even though the toolbox is working:

```
[osv-scanner] Starting SBOM scan...
No package sources found, --help for usage information.
----------------------------------------
[!] osv-scanner exit code 128 but wrote report-osv-scanner.sarif
========== SCA PIPELINE SUMMARY ==========
[osv-scanner]: ERROR (tool did not run correctly)
[trivy]: PASSED
==========================================
```

What is likely happening:

- osv-scanner exits `128` when it finds no packages to enumerate, and the summary
  surfaces that as `ERROR` rather than as an empty result.
- Trivy tends to be more forgiving on the same input, so a split verdict between the
  two is often worth investigating before assuming they disagree about
  vulnerabilities.

Common causes worth ruling out:

- A project that does not produce a usable build graph, for example imports pointing
  at files no longer in the repo, or a missing lockfile. This can leave cyclonedx
  emitting an SBOM with few or no components.
- A target image such as `hello-world`, which may carry no OS packages or lockfiles
  at all.


Things to try:

- Count what actually made it into the SBOM:

  ```bash
  python -c "import json;print(len(json.load(open('target/bom.json')).get('components',[])))"
  ```

  A low or zero count suggests the problem is upstream of the scanners.

---

## Rate limited while generating the SBOM

A run fails or hangs part way through SBOM generation, with the package registry
returning 429, 403 or a "too many requests" message. Maven Central is the usual one,
but npm and proxy registries do it too.

What is happening: the SBOM generator is fetching dependencies **while** it builds the
bill of materials, so every scan turns into a fresh download of the whole dependency
tree straight from the public registry. Do that on every push, across a few
repositories, and you hit the registry's per-IP limit. Shared CI runners make it worse,
since the limit is counted against an address you do not control.

**Resolve dependencies before generating the SBOM.** That is the fix, and it is why
`ci/setup-tools.sh` runs the resolve step first for every built in ecosystem:

| Ecosystem | Resolve step that runs first |
|---|---|
| `maven` | `mvn dependency:resolve` |
| `npm` | `npm ci` |
| `golang` | `go mod download` |

Once resolution has populated the local cache, the SBOM is generated from that cache
and the generator makes no network calls of its own.

So if you are seeing rate limits:

- **Using a built in ecosystem?** Check that the resolve step actually ran and
  succeeded. A resolve failure that is swallowed leaves the generator to fetch
  everything itself, which is exactly the situation above.
- **Using `ECOSYSTEM: generic`?** This is expected. `generic` has no resolve step by
  design, so it can fetch during the scan. It is the main reason to move to a real
  ecosystem branch, see [new-ecosystem.md](new-ecosystem.md).
- **Added your own ecosystem?** Your `case` branch needs a resolve step before it
  writes the SBOM. Without one it will hit this on a cold runner.
- **Still hitting it?** Warm the cache with `actions/cache` so a re-run does not
  re-download, and remember that `actions/cache` skips its save step when the job
  fails, so a project whose gate fails will never populate its cache.
