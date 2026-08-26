.PHONY: build test app run install clean

build:
	swift build

test:
	swift test

app:
	./Scripts/build-app.sh --configuration release

run: app
	open dist/OptiRecord.app

install: app
	rm -rf /Applications/OptiRecord.app
	cp -R dist/OptiRecord.app /Applications/
	@echo "Installed. 初回起動時に画面収録とマイクの許可を求められます。"

clean:
	swift package clean
	rm -rf dist
