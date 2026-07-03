.PHONY: help devices get upgrade clean analyze test run build-apk build-appbundle build-ios

help:
	@echo "Available commands:"
	@echo "  make devices      - List connected devices"
	@echo "  make get          - Get dependencies"
	@echo "  make upgrade      - Upgrade dependencies"
	@echo "  make clean        - Clean build files"
	@echo "  make analyze      - Analyze code"
	@echo "  make test         - Run tests"
	@echo "  make run          - Run debug app"
	@echo "  make build-apk    - Build release APK"
	@echo "  make build-appbundle - Build app bundle (release)"
	@echo "  make build-ios    - Build iOS release"

devices:
	flutter devices

get:
	flutter pub get

upgrade:
	flutter pub upgrade

clean:
	flutter clean

analyze:
	flutter analyze

test:
	flutter test

run:
	flutter run

build-apk:
	flutter build apk --release

build-appbundle:
	flutter build appbundle --release

build-ios:
	flutter build ios --release
