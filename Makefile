.PHONY: ci check-scripts go-test build-linux-arm64 ios-build-sim

BASH_SCRIPTS := notify.sh codex-notify.sh $(wildcard scripts/*.sh)

ci: check-scripts go-test build-linux-arm64

check-scripts:
	bash -n $(BASH_SCRIPTS)
	python3 -m py_compile scripts/install-hooks-macos.py

go-test:
	go test ./...

build-linux-arm64:
	./scripts/build-linux-arm64.sh

ios-build-sim:
	xcodebuild -project ios/Notibel.xcodeproj -scheme Notibel -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
