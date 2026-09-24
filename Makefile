.PHONY: help deps api sandbox web ios android release-ios release-ios-nosign clean

.DEFAULT_GOAL := help

FLUTTER ?= $(shell command -v flutter 2>/dev/null || echo /Users/macbook/development/flutter/bin/flutter)

APP_API_URL_IOS ?= http://127.0.0.1:8788
APP_API_URL_ANDROID ?= http://10.0.2.2:8788
SANDBOX_API_URL_IOS ?= http://127.0.0.1:8787
SANDBOX_API_URL_ANDROID ?= http://10.0.2.2:8787
IOS_RELEASE_FLAGS ?=

help:
	@echo "Available targets:"
	@echo "  make deps               - install Flutter dependencies"
	@echo "  make api                - run app-api backend on port 8788"
	@echo "  make sandbox            - run sandbox proxy on port 8787"
	@echo "  make web                - run Flutter app on Chrome"
	@echo "  make ios                - open iOS Simulator and run Flutter app"
	@echo "  make android            - launch Android emulator (if any) and run Flutter app"
	@echo "  make release-ios        - build iOS release IPA"
	@echo "  make release-ios-nosign - build iOS release without code signing"
	@echo "  make clean              - flutter clean"

deps:
	$(FLUTTER) pub get

api:
	cd app-api && npm install && npm run dev

sandbox:
	cd server && npm install && npm run dev

web:
	$(FLUTTER) run -d chrome \
		--dart-define=APP_API_BASE_URL=$(APP_API_URL_IOS) \
		--dart-define=SANDBOX_API_BASE_URL=$(SANDBOX_API_URL_IOS)

ios:
	open -a Simulator
	@ios_device=$${IOS_DEVICE:-$$($(FLUTTER) devices --machine | python3 -c 'import json,sys; devices=json.load(sys.stdin); print(next((d.get("id","") for d in devices if d.get("isSupported") and d.get("targetPlatform")=="ios"), ""))')}; \
	if [ -z "$$ios_device" ]; then \
		echo "No iOS simulator/device found. Run '$(FLUTTER) devices' to verify."; \
		exit 1; \
	fi; \
	echo "Running on iOS device: $$ios_device"; \
	$(FLUTTER) run -d "$$ios_device" \
		--dart-define=APP_API_BASE_URL=$(APP_API_URL_IOS) \
		--dart-define=SANDBOX_API_BASE_URL=$(SANDBOX_API_URL_IOS)

android:
	@emulator_id=$$($(FLUTTER) emulators | awk 'NF && $$1 !~ /^Id/ {print $$1; exit}'); \
	if [ -n "$$emulator_id" ]; then \
		echo "Launching Android emulator: $$emulator_id"; \
		$(FLUTTER) emulators --launch "$$emulator_id"; \
	else \
		echo "No Android emulator configured. Starting anyway if a device is already connected."; \
	fi
	$(FLUTTER) run -d android \
		--dart-define=APP_API_BASE_URL=$(APP_API_URL_ANDROID) \
		--dart-define=SANDBOX_API_BASE_URL=$(SANDBOX_API_URL_ANDROID)

release-ios:
	$(FLUTTER) build ipa --release $(IOS_RELEASE_FLAGS)

release-ios-nosign:
	$(FLUTTER) build ios --release --no-codesign

clean:
	$(FLUTTER) clean
