.PHONY: build test app run clean lint

build:
	swift build

test:
	swift test

app:
	./Scripts/build-app.sh --configuration release

run: app
	open dist/Aizuchi.app

install: app
	rm -rf /Applications/Aizuchi.app
	cp -R dist/Aizuchi.app /Applications/
	@echo "Installed. 初回起動時に画面収録とマイクの許可を求められます。"

clean:
	swift package clean
	rm -rf dist
