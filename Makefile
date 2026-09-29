APP      := ClaudePace.app
BUILT    := build/$(APP)
APPS_DIR := /Applications
SWIFT    := swift
SPM      := --build-system native

# A nix devshell / profile may export SDKROOT for the nix apple-sdk, which the
# system CLT compiler rejects. Build with the system toolchain.
unexport SDKROOT
unexport DEVELOPER_DIR

.PHONY: build run release app check scan export screenshot install link unlink clean help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

build: ## Build a debug binary
	$(SWIFT) build $(SPM)

run: ## Build and launch (dev, unbundled)
	$(SWIFT) run $(SPM) ClaudePace

release: ## Build an optimized release binary
	$(SWIFT) build -c release $(SPM)

app: ## Build ClaudePace.app bundle
	./build.sh

check: ## Run budget math checks
	$(SWIFT) run $(SPM) BudgetChecks

scan: ## Print this month's spend by model
	$(SWIFT) run $(SPM) BudgetChecks --scan

export: ## Dump this month's usage: make export FORMAT=json|csv [BY=day|model|project|session]
	@$(SWIFT) run $(SPM) -q BudgetChecks --export $(or $(FORMAT),json) $(if $(BY),--by $(BY))

screenshot: app ## Render the popup to docs/screenshot.png (TAB=models|projects|sessions)
	$(BUILT)/Contents/MacOS/ClaudePace --screenshot docs/screenshot.png $(if $(TAB),--tab $(TAB))

install: app ## Copy ClaudePace.app into /Applications
	rm -rf "$(APPS_DIR)/$(APP)"
	cp -R "$(BUILT)" "$(APPS_DIR)/$(APP)"
	@echo "Installed $(APPS_DIR)/$(APP)"

link: app ## Symlink ClaudePace.app into /Applications (points at this build)
	rm -rf "$(APPS_DIR)/$(APP)"
	ln -s "$(CURDIR)/$(BUILT)" "$(APPS_DIR)/$(APP)"
	@echo "Linked $(APPS_DIR)/$(APP) -> $(CURDIR)/$(BUILT)"

unlink: ## Remove ClaudePace.app from /Applications
	rm -rf "$(APPS_DIR)/$(APP)"
	@echo "Removed $(APPS_DIR)/$(APP)"

clean: ## Remove build artifacts
	rm -rf .build build
