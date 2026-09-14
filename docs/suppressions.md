# Suppressing a finding

Use this for a false positive, or for a real finding you have assessed and accepted.
Not for making a build green.

Trivy and OSV-Scanner read ignore files whose paths come from the environment, so you
can point them at your own files without touching pipeline code. Suppression is shared
between the SCA and Container Scanning pipelines, since both read the same two files.

---

## Trivy

In `ci/suppress_trivy.yaml`:

```yaml
vulnerabilities:
  - id: CVE-2025-12345
    statement: "Vulnerable code path is unreachable in our configuration."
    expires: 2026-12-31
```

## OSV-Scanner

In `ci/suppress_osv_scanner.toml`:

```toml
[[IgnoredVulns]]
id = "GHSA-xxxx-yyyy-zzzz"
ignoreUntil = 2026-12-31
reason = "No fix available, mitigated at the network layer."
```

## Using your own files

```yaml
TRIVY_IGNOREFILE: ${{ github.workspace }}/security/trivy.yaml
OSV_IGNOREFILE: ${{ github.workspace }}/security/osv-scanner.toml
```

---

## Always set an expiry and a reason

A suppression without a review date is a permanent blind spot. Both tools support an
expiry field, and both formats have somewhere to write down why. Use them. A year from
now the reason is the only thing that tells you whether the suppression is still
justified, and the expiry is the only thing that forces anyone to look.

---

## SAST has no ignore file

OpenGrep findings are suppressed either at the rule level, or by excluding paths:

```yaml
OPENGREP_EXCLUDE: "*.sarif vendor/ testdata/ *.generated.go"
```

Patterns are relative to `PROJECT`, not the repository root.

Excluding a path hides every current and future finding in it, which is the right call
for vendored code and generated files and the wrong call for code you own.

---

## Reference

- Trivy: [Filtering and ignore files](https://trivy.dev/docs/latest/configuration/filtering/#trivyignoreyaml)
- OSV-Scanner: [Ignore vulnerabilities by ID](https://google.github.io/osv-scanner/configuration/#ignore-vulnerabilities-by-id)
