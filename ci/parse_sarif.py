import json
import os
from dataclasses import dataclass

GATE_FAIL_THRESHOLD = float(os.getenv("GATE_FAIL_THRESHOLD", "8.0"))
GATE_WARN_THRESHOLD = float(os.getenv("GATE_WARN_THRESHOLD", "5.0"))

@dataclass
class EvaluationResult:
    gate_failed: bool
    gate_warn: bool

def remove_stale_report(path):
    """Delete a report left by an earlier run."""
    try:
        os.remove(path)
    except FileNotFoundError:
        pass

def evaluate(sarif_paths):
    if isinstance(sarif_paths, str):
        sarif_paths = [sarif_paths]

    max_score = 0.0
    for path in sarif_paths:
        try:
            with open(path) as f:
                sarif = json.load(f, strict=False)
        except FileNotFoundError:
            raise FileNotFoundError(f"[parse_sarif] SARIF file not found: {path}")
        except json.JSONDecodeError as e:
            raise ValueError(f"[parse_sarif] SARIF file at {path} is not valid JSON: {e}")

        for run in sarif.get("runs", []):
            try:
                rules = run["tool"]["driver"].get("rules", [])
            except KeyError as e:
                raise KeyError(f"[parse_sarif] SARIF file at {path} has a run missing expected field {e}")

            severities = {r["id"]: r.get("properties", {}).get("security-severity") for r in rules}

            for result in run.get("results", []):
                score = severities.get(result["ruleId"])
                if score is not None:
                    max_score = max(max_score, float(score))

    return EvaluationResult(
            gate_failed=max_score >= GATE_FAIL_THRESHOLD,
            gate_warn=GATE_WARN_THRESHOLD <= max_score < GATE_FAIL_THRESHOLD,
        )
