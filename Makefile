.PHONY: sast sca container-scan clean

# Directory or image to scan, override on the CLI, e.g.:
#   make sast PROJECT=./mip-backend-maven
#   make sca PROJECT=./mip-backend-maven ECOSYSTEM=maven  (maven, npm, generic, golang)
#   make container-scan IMAGE=platform-backend:local SCAN_TYPE=sca
#   make container-scan IMAGE=platform-backend:local SCAN_TYPE=sast PROJECT=./mip-backend-maven

PROJECT   ?=
ECOSYSTEM ?=
IMAGE     ?=
SCAN_TYPE ?=

define USAGE
Usage:
  make sast   PROJECT=<dir>
  make sca    PROJECT=<dir> ECOSYSTEM=<maven|npm|golang|generic|none|...>
            more ecosystems: https://github.com/moghit-eou/reusable-ci-pipelines/blob/main/docs/new-ecosystem.md
  make container-scan IMAGE=<image> SCAN_TYPE=<sast|sca> [PROJECT=<dir>]  # PROJECT required when SCAN_TYPE=sast
endef
export USAGE

sast: ## Run the SAST pipeline against $PROJECT
ifndef PROJECT
	$(error $$PROJECT is required.$(USAGE))
endif
	./toolbox.sh sast $(PROJECT)

sca: ## Run the SCA pipeline against $PROJECT for $ECOSYSTEM
ifndef PROJECT
	$(error $$PROJECT is required.$(USAGE))
endif
ifndef ECOSYSTEM
	$(error $$ECOSYSTEM is required.$(USAGE))
endif
	./toolbox.sh sca $(PROJECT) $(ECOSYSTEM)

container-scan: ## Run the container-scan pipeline ($SCAN_TYPE: sast|sca) against $IMAGE
ifndef IMAGE
	$(error $$IMAGE is required.$(USAGE))
endif
ifndef SCAN_TYPE
	$(error $$SCAN_TYPE is required.$(USAGE))
endif
ifeq ($(SCAN_TYPE),sast)
ifndef PROJECT
	$(error $$PROJECT is required when SCAN_TYPE=sast.$(USAGE))
endif
endif
	./toolbox.sh container-scan $(IMAGE) $(SCAN_TYPE) $(PROJECT)

clean: ## Remove local SARIF outputs and toolbox images
	rm -f *.sarif */*.sarif
	docker image rm -f mip-toolbox:sast mip-toolbox:sca mip-toolbox:container-scan 2>/dev/null || true