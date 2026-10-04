import subprocess
import os
import sys
import logging
import json
from parse_sarif import evaluate, remove_stale_report, GATE_FAIL_THRESHOLD, GATE_WARN_THRESHOLD

GREEN = '\033[92m'
RED = '\033[91m'
RESET = '\033[0m'
BOLD = '\033[1m'
YELLOW = '\033[93m'

logging.basicConfig(
    level=logging.INFO,
    format='%(message)s'  # Clean format to prevent double-timestamps in CI logs
)
logger = logging.getLogger("sca-orchestrator")

# Configurable values
SBOM_PATH = os.getenv("SBOM_PATH", "target/bom.json")
TRIVY_IGNOREFILE = os.getenv("TRIVY_IGNOREFILE", "suppress_trivy.yaml")
OSV_IGNOREFILE = os.getenv("OSV_IGNOREFILE", "suppress_osv_scanner.toml")
TRIVY_SARIF_OUTPUT = os.getenv("TRIVY_SARIF_OUTPUT", "sca-trivy.sarif")
OSV_SARIF_OUTPUT = os.getenv("OSV_SARIF_OUTPUT", "sca-osv-scanner.sarif")
SCA_MERGED_SARIF_OUTPUT = os.getenv("SCA_MERGED_SARIF_OUTPUT", "sca-merged.sarif")

def run_trivy():
    remove_stale_report(TRIVY_SARIF_OUTPUT)
    logger.info(f"{BOLD}[trivy] Starting SBOM scan...{RESET}")
    cmd = [
        "trivy", "sbom", SBOM_PATH,
        "--format", "sarif",
        "-q",
        "--ignorefile", TRIVY_IGNOREFILE,
        "--output", TRIVY_SARIF_OUTPUT
    ]
    logger.info(f"{BOLD}Running: {' '.join(cmd)}{RESET}")
    return subprocess.run(cmd).returncode

def run_osv_scanner():
    remove_stale_report(OSV_SARIF_OUTPUT)
    logger.info(f"{BOLD}[osv-scanner] Starting SBOM scan...{RESET}")
    cmd = [
        "osv-scanner", "scan", "source",
        "--lockfile", SBOM_PATH,
        "--config", OSV_IGNOREFILE,
        "--format", "sarif",
        "--output-file", OSV_SARIF_OUTPUT,
        "--verbosity", "error"
    ]
    logger.info(f"{BOLD}Running: {' '.join(cmd)}{RESET}")
    exit_code = subprocess.run(cmd).returncode
    if exit_code == 1:
        return 0  # OSV Scanner returns 1 if vulnerabilities are found, but we want to continue the pipeline
    return exit_code

def merge_sarifs():
    merged = {
        "$schema": "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/main/sarif-2.1/schema/sarif-schema-2.1.0.json",
        "version": "2.1.0",
        "runs": [],
    }

    for path in (TRIVY_SARIF_OUTPUT, OSV_SARIF_OUTPUT):
        if not os.path.exists(path):
            logger.warning(f"{path} not found, skipping in merge")
            continue
        with open(path) as f:
            sarif = json.load(f, strict=False)
        merged["runs"].extend(sarif.get("runs", []))

    with open(SCA_MERGED_SARIF_OUTPUT, "w") as f:
        json.dump(merged, f)

    logger.info("SARIF files merged successfully.")

def main():

    tools = {"trivy": run_trivy, "osv-scanner": run_osv_scanner}
    sarif_files = {"trivy": TRIVY_SARIF_OUTPUT, "osv-scanner": OSV_SARIF_OUTPUT}
    tool_status = {}   # "PASSED" | "WARNING" | "FAILED" | "ERROR"
    gate_failed = False

    # Run each SCA tool and collect their exit codes
    for name, tool_fn in tools.items():
        exit_code = tool_fn()
        logger.info("-" * 40)

        path = sarif_files[name]
        if exit_code != 0 and os.path.exists(path):
            logger.error(f"{RED}[!] {name} exit code {exit_code} but wrote {path}{RESET}")
            tool_status[name] = "ERROR"
            gate_failed = True

    merge_sarifs()  # combined artifact only, not used for the gate decision

    # Evaluate each SARIF file for gate decision
    for name, path in sarif_files.items():
        if name in tool_status:
            continue  # already flagged ERROR above, don't overwrite it

        if not os.path.exists(path):
            logger.error(f"{RED}[!] {name} SARIF missing: {path},tool failed to run (not a vulnerability){RESET}")
            tool_status[name] = "ERROR"
            gate_failed = True
            continue

        eval_result = evaluate(path)

        if eval_result.gate_failed:
            tool_status[name] = "FAILED"
            gate_failed = True
        elif eval_result.gate_warn:
            tool_status[name] = "WARNING"
        else:
            tool_status[name] = "PASSED"

    # Print summary of results
    logger.info(f"\n{BOLD}========== SCA PIPELINE SUMMARY =========={RESET}")
    for name, status in tool_status.items():
        if status == "PASSED":
            logger.info(f"[{name}]: {GREEN}PASSED{RESET}")
        elif status == "WARNING":
            logger.warning(f"[{name}]: {YELLOW}WARNING (findings between {GATE_WARN_THRESHOLD} and {GATE_FAIL_THRESHOLD}){RESET}")
        elif status == "ERROR":
            logger.error(f"[{name}]: {RED}ERROR (tool did not run correctly){RESET}")
        else:
            logger.error(f"[{name}]: {RED}FAILED (CVSS >= {GATE_FAIL_THRESHOLD} found){RESET}")
    logger.info(f"{BOLD}=========================================={RESET}\n")

    # Exit with non-zero code if any tool failed the gate
    if gate_failed:
        logger.error(f"{RED}One or more SCA tools failed the gate check.{RESET}")
        sys.exit(1)

if __name__ == "__main__":
    main()
