# Thin layer over Scripts/; logic belongs in the scripts.
.PHONY: build test install run quit dev-reaper clean

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

clean:
	rm -rf .build
