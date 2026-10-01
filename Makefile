# Thin layer over Scripts/; logic belongs in the scripts.
.PHONY: build test install run quit dev-reaper release icon clean

build:
	swift build

test:
	swift test

install:
	Scripts/install-extension.sh

run:
	Scripts/run-dev-reaper.sh

quit:
	Scripts/quit-dev-reaper.sh

dev-reaper:
	Scripts/setup-dev-reaper.sh

release:
	Scripts/release.sh

icon:
	Scripts/make-icon.sh

clean:
	rm -rf .build
