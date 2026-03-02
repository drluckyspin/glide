PROJECT         = Glide.xcodeproj
SCHEME          = Glide
CONFIG          = Release
DEST            = platform=macOS
BUILD_OUTPUT_DIR = $(CURDIR)/build

.PHONY: help build build-debug run install test clean open

help:
	@echo "make help         - Show this help"
	@echo "make build        - Build (Release configuration)"
	@echo "make build-debug  - Build (Debug configuration)"
	@echo "make run          - Build and run the app"
	@echo "make install      - Build and install to ~/Applications"
	@echo "make test         - Run tests (Debug configuration)"
	@echo "make clean        - Clean build artifacts"
	@echo "make open         - Open the Xcode project"

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -destination '$(DEST)' -derivedDataPath "$(BUILD_OUTPUT_DIR)" build

build-debug:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination '$(DEST)' -derivedDataPath "$(BUILD_OUTPUT_DIR)" build

run: build
	open "$(BUILD_OUTPUT_DIR)/Build/Products/$(CONFIG)/Glide.app"

install: build
	@if [ -d "/Applications/Glide.app" ]; then \
		printf "Glide is already installed in /Applications. Replace it? [y/N] "; \
		read answer; \
		case $$answer in \
			y|Y|yes|YES) \
				rm -rf "/Applications/Glide.app"; \
				ditto "$(BUILD_OUTPUT_DIR)/Build/Products/$(CONFIG)/Glide.app" "/Applications/Glide.app"; \
				echo "Installed Glide to /Applications/Glide.app"; \
				;; \
			*) \
				echo "Install canceled."; \
				;; \
		esac; \
	else \
		ditto "$(BUILD_OUTPUT_DIR)/Build/Products/$(CONFIG)/Glide.app" "/Applications/Glide.app"; \
		echo "Installed Glide to /Applications/Glide.app"; \
	fi

test:
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination '$(DEST)' -derivedDataPath "$(BUILD_OUTPUT_DIR)"

clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -destination '$(DEST)' -derivedDataPath "$(BUILD_OUTPUT_DIR)" clean
	rm -rf "$(BUILD_OUTPUT_DIR)"

open:
	open $(PROJECT)

