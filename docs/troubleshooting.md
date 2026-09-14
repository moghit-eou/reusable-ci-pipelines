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
