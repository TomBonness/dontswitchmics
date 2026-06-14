.PHONY: build test package install list enforce

build:
	swift build --product DontSwitchMics
	swift build --product dontswitchmicsctl

test:
	swift test

package:
	scripts/package_app.sh

install:
	scripts/install_app.sh

list:
	swift run dontswitchmicsctl --list-devices

enforce:
	swift run dontswitchmicsctl --enforce-once
