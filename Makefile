.PHONY: app run install test clean

app:
	./scripts/build-app.sh

run: app
	open dist/MacroForMac.app

install: app
	rm -rf /Applications/MacroForMac.app
	cp -R dist/MacroForMac.app /Applications/
	open /Applications/MacroForMac.app

test:
	swift test

clean:
	rm -rf .build dist
