import subprocess
import os
import sys
import logging
from parse_sarif import remove_stale_report

GREEN = '\033[92m'
RED = '\033[91m'
RESET = '\033[0m'
BOLD = '\033[1m'
YELLOW = '\033[93m'

logging.basicConfig(
    level=logging.INFO,
    format='%(message)s'  # Clean format to prevent double-timestamps in CI logs
)
logger = logging.getLogger("sast-orchestrator")

# --- Configurable values -----------------------------------------------
SEMGREP_CONFIG_RULESETS = os.getenv(
    "SEMGREP_CONFIG_RULESETS",
    " semgrep-rules/generic semgrep-rules/problem-based-packs semgrep-rules/bash "
    " semgrep-rules/java auto semgrep-rules/yaml semgrep-rules/package_managers p/default "
).split()
OPENGREP_EXCLUDE = os.getenv(
    "OPENGREP_EXCLUDE",
    "*.sarif ci/ Dockerfile* .pre-commit-config.yaml docs/** README.md AGENTS.md"
).split()
OPENGREP_SARIF_OUTPUT = os.getenv("OPENGREP_SARIF_OUTPUT", "sast-opengrep.sarif")

def run_opengrep():
    remove_stale_report(OPENGREP_SARIF_OUTPUT)
    logger.info(f"{BOLD}[opengrep] Starting scan...{RESET}")
    base_cmd = ["opengrep", "scan"] + \
        [f"--config {config}" for config in SEMGREP_CONFIG_RULESETS] + \
        [f"--exclude={pattern}" for pattern in OPENGREP_EXCLUDE]

    report_cmd = (base_cmd + ["--sarif", "--output", OPENGREP_SARIF_OUTPUT])
    report_cmd = " ".join(report_cmd).split()
    logger.info(f"{BOLD}Running (report):{RESET} {' '.join(report_cmd)}")
    subprocess.run(report_cmd)

    gate_cmd = (base_cmd + ["--severity=ERROR", "--error"])
    gate_cmd = " ".join(gate_cmd).split()
    logger.info(f"{BOLD}Running (gate):{RESET} {' '.join(gate_cmd)}")
    return subprocess.run(gate_cmd).returncode

def main():

    exit_code = run_opengrep()
    logger.info("-" * 40)

    if exit_code == 0:
        status = "PASSED"
    elif exit_code == 1:
        status = "FAILED"
    else:
        status = "ERROR"

    if not os.path.exists(OPENGREP_SARIF_OUTPUT):
        logger.error(f"{RED}[!] opengrep SARIF missing: {OPENGREP_SARIF_OUTPUT}, tool failed to run{RESET}")
        status = "ERROR"

    logger.info(f"\n{BOLD}========== SAST PIPELINE SUMMARY =========={RESET}")
    if status == "PASSED":
        logger.info(f"[opengrep]: {GREEN}PASSED (exit code 0){RESET}")
    elif status == "FAILED":
        logger.error(f"[opengrep]: {RED}FAILED (exit code 1 - error-severity findings){RESET}")
    else:
        logger.error(f"[opengrep]: {RED}ERROR (exit code {exit_code}, tool did not run correctly){RESET}")
    logger.info(f"{BOLD}==========================================={RESET}\n")

    if status == "ERROR":
        sys.exit(1)

    if status == "FAILED":
        logger.error(f"{RED}SAST gate failed: blocking-severity findings present.{RESET}")
        sys.exit(1)

if __name__ == "__main__":
    main()
