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
#   site                    : Open the landing page (site/index.html) in the browser
#   dev-package             : Create unsigned DMG for local testing (version: dev)
#   release                 : Create signed and notarized DMG for distribution
#   sign                    : Codesign and notarize (requires secrets/secrets.env)
#   check                   : Verify all developer dependencies
#   bump-version            : Sync VERSION into plist and site (download + Vemetric)
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

# Local signing identity used by `make sign` / `make release`. Defaults to the Developer ID
# Application identity already in your login keychain (override on the command line if needed).
SIGN_IDENTITY   ?= Developer ID Application

# All Phony targets
.PHONY: help build build-debug run run-onboarding install test clean open site dev-package release release-prep sign check check_xcode check_xcode_first_launch check_brew check_create_dmg bump-version


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
# Check (Verify developer dependencies)
# -----------------------------------------------------------------------------------------------------------
check: ## Verify all developer dependencies
	@$(LOGGER) log_separator
	@$(LOGGER) log_info "Checking developer dependencies"
	@$(MAKE) check_xcode
	@$(MAKE) check_xcode_first_launch
	@$(MAKE) check_brew
	@$(MAKE) check_create_dmg
	@$(LOGGER) log_success "All dependencies OK"

check_xcode:
	@if ! command -v xcodebuild >/dev/null 2>&1; then \
		$(LOGGER) log_error "xcodebuild is not installed. Install Xcode from the App Store."; \
		exit 1; \
	else \
		XCODE_VERSION=$$(xcodebuild -version | head -n1); \
		$(LOGGER) log_info_dim "$$XCODE_VERSION is installed."; \
	fi

check_xcode_first_launch:
	@$(LOGGER) log_info_dim "Running xcodebuild -runFirstLaunch (idempotent, completes quickly if already done)..."
	@if ! xcodebuild -runFirstLaunch; then \
		$(LOGGER) log_error "xcodebuild -runFirstLaunch failed. Run it manually: xcodebuild -runFirstLaunch"; \
		exit 1; \
	else \
		$(LOGGER) log_info_dim "Xcode first-launch setup complete."; \
	fi

check_brew:
	@if ! command -v brew >/dev/null 2>&1; then \
		$(LOGGER) log_error "Homebrew is not installed. Install from https://brew.sh"; \
		exit 1; \
	else \
		BREW_VERSION=$$(brew --version | head -n1); \
		$(LOGGER) log_info_dim "$$BREW_VERSION is installed."; \
	fi

check_create_dmg:
	@if ! command -v create-dmg >/dev/null 2>&1; then \
		$(LOGGER) log_error "create-dmg is not installed. Install with: brew install create-dmg"; \
		exit 1; \
	else \
		$(LOGGER) log_info_dim "create-dmg is installed."; \
	fi

# -----------------------------------------------------------------------------------------------------------
# Bump version (read VERSION file, update Glide-Info.plist and site/index.html)
# -----------------------------------------------------------------------------------------------------------
bump-version: ## Sync VERSION into plist and site (download URL + data-vmtrc-version)
	@if [ ! -f "$(MAKEFILE_DIR)VERSION" ]; then \
		source $(MAKEFILE_DIR)scripts/log.bash && log_error "VERSION file not found. Create it with the desired version (e.g. 1.2.0)"; \
		exit 1; \
	fi
	@V=$$(cat "$(MAKEFILE_DIR)VERSION" | tr -d '\n' | tr -d ' '); \
	V=$${V#v}; \
	if [ -z "$$V" ]; then \
		source $(MAKEFILE_DIR)scripts/log.bash && log_error "VERSION file is empty"; \
		exit 1; \
	fi; \
	$(LOGGER) log_separator; \
	$(LOGGER) log_info "Setting version to $$V (from VERSION file)"; \
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $$V" Glide/Glide-Info.plist; \
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $$V" Glide/Glide-Info.plist; \
	$(LOGGER) log_success "Updated Glide-Info.plist to $$V"; \
	SITE="$(MAKEFILE_DIR)site/index.html"; \
	if [ -f "$$SITE" ]; then \
		sed -i '' -e "s|https://github.com/drluckyspin/glide/releases/download/v[^/]*/Glide-[^/]*\\.zip|https://github.com/drluckyspin/glide/releases/download/v$$V/Glide-$$V.zip|g" "$$SITE"; \
		sed -i '' -e "s|data-vmtrc-version=\"[^\"]*\"|data-vmtrc-version=\"$$V\"|g" "$$SITE"; \
		$(LOGGER) log_success "Updated site/index.html (GitHub download + data-vmtrc-version) to $$V"; \
	fi

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

site: ## Open the landing page (site/index.html) in the default browser
	open "$(MAKEFILE_DIR)site/index.html"

# -----------------------------------------------------------------------------------------------------------
# Dev package (Create unsigned DMG for local testing (version: dev))
# -----------------------------------------------------------------------------------------------------------
dev-package: PACKAGE_VERSION = $(VERSION_DEV)
dev-package: ## Create unsigned DMG for local testing (version: dev)
release: sign ## Create signed and notarized DMG for distribution
sign: release-prep ## Codesign, notarize app and DMG (requires secrets/secrets.env)

dev-package:
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
# Release prep (archive + prepare for signing)
# -----------------------------------------------------------------------------------------------------------
release-prep:
	@$(LOGGER) log_separator
	@$(LOGGER) log_info "Preparing Glide $(VERSION_RELEASE) for signing..."
	@set -e; \
	xcodebuild archive \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration $(CONFIG) \
		-archivePath $(ARCHIVE_PATH) \
		-destination '$(DEST)' \
		CODE_SIGNING_ALLOWED=NO; \
	mkdir -p $(DIST_DIR); \
	rm -rf $(DIST_DIR)/Glide.app; \
	cp -R $(ARCHIVE_PATH)/Products/Applications/Glide.app $(DIST_DIR)/Glide.app; \
	$(LOGGER) log_success "App ready for signing"

# -----------------------------------------------------------------------------------------------------------
# Sign (codesign, notarize app, create DMG, notarize DMG)
# -----------------------------------------------------------------------------------------------------------
# Local signing. Uses the Developer ID identity already in your login keychain and notarizes
# straight from secrets/secrets.env. It does NOT create an ephemeral keychain or change your
# default/search-list keychains, so it never disturbs your session. (CI signs separately and
# inline in .github/workflows/release.yaml; this Makefile target is local-only.)
sign:
	@$(LOGGER) log_separator
	@$(LOGGER) log_info "Signing and notarizing Glide $(VERSION_RELEASE)..."
	@if [ ! -f "$(MAKEFILE_DIR)secrets/secrets.env" ]; then \
		source $(MAKEFILE_DIR)scripts/log.bash && log_error "secrets/secrets.env not found. Add your Apple Developer secrets."; \
		exit 1; \
	fi
	@if ! security find-identity -v -p codesigning | grep -q "$(SIGN_IDENTITY)"; then \
		source $(MAKEFILE_DIR)scripts/log.bash && log_error "No '$(SIGN_IDENTITY)' identity in your login keychain. Import it once (double-click secrets/DevIDCertificates.p12) and retry."; \
		exit 1; \
	fi
	@set -euo pipefail; \
	set -a; \
	source "$(MAKEFILE_DIR)secrets/secrets.env"; \
	set +a; \
	TEMP_DIR="$${TMPDIR:-/tmp}"; \
	APP="$(DIST_DIR)/Glide.app"; \
	VERSION="$(VERSION_RELEASE)"; \
	DMG="Glide-$$VERSION.dmg"; \
	P8="$$TEMP_DIR/glide-asc-AuthKey.p8"; \
	ZIP="$$TEMP_DIR/Glide.zip"; \
	icon_tmp=""; rsrc_tmp=""; \
	cleanup() { \
		err=$$?; \
		rm -f "$$P8" "$$ZIP" "$$icon_tmp" "$$rsrc_tmp" 2>/dev/null || true; \
		if [ $$err -ne 0 ]; then \
			source $(MAKEFILE_DIR)scripts/log.bash && log_warning "Cleaning up interstitial artifacts after failure..."; \
			rm -f rw.*."$$DMG"; \
		fi; \
		exit $$err; \
	}; \
	trap cleanup EXIT; \
	echo "$$ASC_PRIVATE_KEY_B64" | base64 --decode > "$$P8"; \
	chmod 600 "$$P8"; \
	source $(MAKEFILE_DIR)scripts/log.bash && log_info "Codesigning app (identity: $(SIGN_IDENTITY))..."; \
	codesign --force --options runtime --timestamp --sign "$(SIGN_IDENTITY)" "$$APP"; \
	codesign -vvv --deep --strict "$$APP"; \
	source $(MAKEFILE_DIR)scripts/log.bash && log_info "Notarizing app..."; \
	ditto -c -k --sequesterRsrc --keepParent "$$APP" "$$ZIP"; \
	xcrun notarytool submit "$$ZIP" \
		--key "$$P8" --key-id "$$ASC_KEY_ID" --issuer "$$ASC_ISSUER_ID" --wait; \
	xcrun stapler staple "$$APP"; \
	xcrun stapler validate "$$APP"; \
	source $(MAKEFILE_DIR)scripts/log.bash && log_info "Creating DMG..."; \
	command -v create-dmg >/dev/null 2>&1 || brew install create-dmg; \
	rm -f "$$DMG" rw.*."$$DMG" 2>/dev/null || true; \
	create-dmg \
		--volname "Glide $$VERSION" \
		--volicon "$(DMG_VOLICON)" \
		--window-pos 200 120 \
		--window-size 600 400 \
		--icon-size 100 \
		--icon "Glide.app" 175 120 \
		--hide-extension "Glide.app" \
		--app-drop-link 425 120 \
		"$$DMG" \
		$(DIST_DIR)/; \
	icon_tmp=$$(mktemp -t dmg-icon.XXXXXXXXXX.icns); \
	rsrc_tmp=$$(mktemp -t dmg-icon.XXXXXXXXXX.rsrc); \
	cp "$(DMG_VOLICON)" "$$icon_tmp"; \
	sips -i "$$icon_tmp" >/dev/null 2>&1; \
	DeRez -only icns "$$icon_tmp" > "$$rsrc_tmp" 2>/dev/null; \
	Rez -append "$$rsrc_tmp" -o "$$DMG"; \
	SetFile -a C "$$DMG"; \
	source $(MAKEFILE_DIR)scripts/log.bash && log_info "Notarizing DMG..."; \
	xcrun notarytool submit "$$DMG" \
		--key "$$P8" --key-id "$$ASC_KEY_ID" --issuer "$$ASC_ISSUER_ID" --wait; \
	xcrun stapler staple "$$DMG"; \
	xcrun stapler validate "$$DMG"; \
	$(LOGGER) log_success "Created signed and notarized $$DMG (login keychain, no keychain switching)"

# -----------------------------------------------------------------------------------------------------------
# Run (Build and run the app)
# -----------------------------------------------------------------------------------------------------------
run: build ## Build and run the app
	@$(LOGGER) log_separator
	@$(LOGGER) log_info "Running Glide"
	open "$(BUILD_OUTPUT_DIR)/Build/Products/$(CONFIG)/Glide.app"

run-onboarding: build ## Build and run Glide with onboarding dialog (for testing banner UI)
	@$(LOGGER) log_separator
	@$(LOGGER) log_info "Running Glide with onboarding (translocation banner visible)"
	open "$(BUILD_OUTPUT_DIR)/Build/Products/$(CONFIG)/Glide.app" --args -force-onboarding -translocation

# -----------------------------------------------------------------------------------------------------------
# Test (Run tests (Debug configuration))
# -----------------------------------------------------------------------------------------------------------
test: ## Run tests (Debug configuration)
	@$(LOGGER) log_separator
	@$(LOGGER) log_info "Running tests"
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination '$(DEST)' -derivedDataPath "$(BUILD_OUTPUT_DIR)"
	@$(LOGGER) log_success "Tests complete"
