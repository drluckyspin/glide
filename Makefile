# -----------------------------------------------------------------------------------------------------------
# Glide Makefile
# -----------------------------------------------------------------------------------------------------------
# This Makefile provides commands to build, run, and package the Glide macOS app.
# Glide adds easy modifier key + mouse drag move and resize capabilities to macOS.
#
# Usage:
#   make <command>
#
# Available Commands:
#   help                    : Show this help message
#   build                   : Build (Release configuration)
#   build-debug             : Build (Debug configuration)
#   clean                   : Clean build artifacts
#   install                 : Build and install to /Applications
#   open                    : Open the Xcode project
#   package                 : Create DMG for local testing (version: dev)
#   release                 : Create DMG for distribution (version from Info.plist)
#   run                     : Build and run the app
#   test                    : Run tests (Debug configuration)
#
# -----------------------------------------------------------------------------------------------------------

# Default target
all: help

# Default shell
SHELL := /bin/bash

# Import log functions (resolve relative to this file)
MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
LOGGER := source $(MAKEFILE_DIR)scripts/log.bash &&
RESET := \033[0m
DIM := \033[2m

# Xcode specific variables
PROJECT         = Glide.xcodeproj
SCHEME          = Glide
CONFIG          = Release
DEST            = platform=macOS
BUILD_OUTPUT_DIR = $(CURDIR)/build

# Version variables
VERSION_DEV     := dev
VERSION_RELEASE := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Glide/Glide-Info.plist)
ARCHIVE_PATH    = $(BUILD_OUTPUT_DIR)/Glide.xcarchive
DIST_DIR        = $(BUILD_OUTPUT_DIR)/dist

# DMG volume icon: uses the app's built AppIcon.icns (create-dmg requires .icns format).
# To use docs/app-icon.png instead, convert it first: add docs/app-icon.icns and set DMG_VOLICON to that path.
DMG_VOLICON     = $(DIST_DIR)/Glide.app/Contents/Resources/AppIcon.icns

# All Phony targets
.PHONY: help build build-debug run install test clean open package release


# -----------------------------------------------------------------------------------------------------------
# Help (Show this help message)
# -----------------------------------------------------------------------------------------------------------
help: ## Show this help message
	@$(LOGGER) log_banner
	@$(LOGGER) log_info "Available make targets:"
	@echo ""
	@(grep -E '^[[:space:]]*help:.*## .*$$' $(MAKEFILE_LIST) 2>/dev/null; grep -E '^[[:space:]]*[a-zA-Z0-9][a-zA-Z0-9_ -]*:.*## .*$$' $(MAKEFILE_LIST) | grep -v '^[[:space:]]*help:.*##' | sort) | \
		awk -F' ## ' '{ n = index($$1, ":"); target = substr($$1, 1, n-1); gsub(/^[ \t]+|[ \t]+$$/, "", target); desc = $$2; gsub(/^[ \t]+|[ \t]+$$/, "", desc); printf " %-22s$(RESET) $(DIM)- %s$(RESET)\n", target, desc }'
	@echo ""

# -----------------------------------------------------------------------------------------------------------
# Build (Release configuration)
# -----------------------------------------------------------------------------------------------------------
build: ## Build (Release configuration)
	@$(LOGGER) log_separator
	@$(LOGGER) log_info "Building Glide"
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -destination '$(DEST)' -derivedDataPath "$(BUILD_OUTPUT_DIR)" build

# -----------------------------------------------------------------------------------------------------------
# Build (Debug configuration)
# -----------------------------------------------------------------------------------------------------------
build-debug: ## Build (Debug configuration)
	@$(LOGGER) log_separator
	@$(LOGGER) log_info "Building Glide (Debug configuration)"
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination '$(DEST)' -derivedDataPath "$(BUILD_OUTPUT_DIR)" build
	@$(LOGGER) log_success "Build complete"

# -----------------------------------------------------------------------------------------------------------
# Clean (Clean build artifacts)
# -----------------------------------------------------------------------------------------------------------
clean: ## Clean build artifacts
	@$(LOGGER) log_separator
	@$(LOGGER) log_info "Cleaning build artifacts"
	@$(LOGGER) log_indent log_dim "Removing build output..."
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -destination '$(DEST)' -derivedDataPath "$(BUILD_OUTPUT_DIR)" clean
	rm -rf "$(BUILD_OUTPUT_DIR)"
	@$(LOGGER) log_indent log_dim "Removing DMG files..."
	rm -f Glide-$(VERSION_DEV).dmg Glide-$(VERSION_RELEASE).dmg
	rm -f rw.*.Glide-*.dmg
	@$(LOGGER) log_success "Clean complete"

# -----------------------------------------------------------------------------------------------------------
# Install (Build and install to /Applications)
# -----------------------------------------------------------------------------------------------------------
install: build ## Build and install to ~/Applications
	@$(LOGGER) log_separator
	@$(LOGGER) log_info "Installing Glide to /Applications"
	@if [ -d "/Applications/Glide.app" ]; then \
		printf "Glide is already installed in /Applications. Replace it? [y/N] "; \
		read answer; \
		case $$answer in \
			y|Y|yes|YES) \
				rm -rf "/Applications/Glide.app"; \
				ditto "$(BUILD_OUTPUT_DIR)/Build/Products/$(CONFIG)/Glide.app" "/Applications/Glide.app"; \
				$(LOGGER) log_success "Installed Glide to /Applications/Glide.app"; \
				;; \
			*) \
				$(LOGGER) log_dim "Install canceled."; \
				;; \
		esac; \
	else \
		ditto "$(BUILD_OUTPUT_DIR)/Build/Products/$(CONFIG)/Glide.app" "/Applications/Glide.app"; \
		$(LOGGER) log_success "Installed Glide to /Applications/Glide.app"; \
	fi

# -----------------------------------------------------------------------------------------------------------
# Open (Open the Xcode project)
# -----------------------------------------------------------------------------------------------------------
open: ## Open the Xcode project
	open $(PROJECT)

# -----------------------------------------------------------------------------------------------------------
# Package (Create DMG for local testing (version: dev))
# -----------------------------------------------------------------------------------------------------------
package: PACKAGE_VERSION = $(VERSION_DEV)
package: ## Create DMG for local testing (version: dev)
release: PACKAGE_VERSION = $(VERSION_RELEASE)
release: ## Create DMG for distribution (version from Info.plist)

package release:
	@$(LOGGER) log_separator
	@$(LOGGER) log_info "Creating DMG for Glide $(PACKAGE_VERSION)..."
	@set -e; \
	icon_tmp=""; rsrc_tmp=""; \
	cleanup() { \
		err=$$?; \
		if [ $$err -ne 0 ]; then \
			source $(MAKEFILE_DIR)scripts/log.bash && log_warning "Cleaning up interstitial artifacts after failure..."; \
			rm -f rw.*.Glide-$(PACKAGE_VERSION).dmg; \
		fi; \
		rm -f "$$icon_tmp" "$$rsrc_tmp" 2>/dev/null || true; \
		exit $$err; \
	}; \
	trap cleanup EXIT; \
	xcodebuild archive \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIG) \
		-archivePath $(ARCHIVE_PATH) \
		-destination '$(DEST)' \
		CODE_SIGNING_ALLOWED=NO; \
	command -v create-dmg >/dev/null 2>&1 || brew install create-dmg; \
	mkdir -p $(DIST_DIR); \
	rm -rf $(DIST_DIR)/Glide.app; \
	cp -R $(ARCHIVE_PATH)/Products/Applications/Glide.app $(DIST_DIR)/Glide.app; \
	create-dmg \
		--volname "Glide $(PACKAGE_VERSION)" \
		--volicon "$(DMG_VOLICON)" \
		--window-pos 200 120 \
		--window-size 600 400 \
		--icon-size 100 \
		--icon "Glide.app" 175 120 \
		--hide-extension "Glide.app" \
		--app-drop-link 425 120 \
		Glide-$(PACKAGE_VERSION).dmg \
		$(DIST_DIR)/; \
	icon_tmp=$$(mktemp -t dmg-icon.XXXXXXXXXX.icns); \
	rsrc_tmp=$$(mktemp -t dmg-icon.XXXXXXXXXX.rsrc); \
	cp "$(DMG_VOLICON)" "$$icon_tmp"; \
	sips -i "$$icon_tmp" >/dev/null 2>&1; \
	DeRez -only icns "$$icon_tmp" > "$$rsrc_tmp" 2>/dev/null; \
	Rez -append "$$rsrc_tmp" -o Glide-$(PACKAGE_VERSION).dmg; \
	SetFile -a C Glide-$(PACKAGE_VERSION).dmg; \
	$(LOGGER) log_success "Created Glide-$(PACKAGE_VERSION).dmg"

# -----------------------------------------------------------------------------------------------------------
# Run (Build and run the app)
# -----------------------------------------------------------------------------------------------------------
run: build ## Build and run the app
	@$(LOGGER) log_separator
	@$(LOGGER) log_info "Running Glide"
	open "$(BUILD_OUTPUT_DIR)/Build/Products/$(CONFIG)/Glide.app"

# -----------------------------------------------------------------------------------------------------------
# Test (Run tests (Debug configuration))
# -----------------------------------------------------------------------------------------------------------
test: ## Run tests (Debug configuration)
	@$(LOGGER) log_separator
	@$(LOGGER) log_info "Running tests"
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination '$(DEST)' -derivedDataPath "$(BUILD_OUTPUT_DIR)"
	@$(LOGGER) log_success "Tests complete"
