APP_NAME = SuperOpt
APP_BUNDLE = build/$(APP_NAME).app
INSTALL_DIR = /Applications

.PHONY: clean build install kill run

clean:
	rm -rf build

build:
	./build.sh

install: clean
	@[ -d "$(APP_BUNDLE)" ] || ./build.sh
	@echo "Installing $(APP_NAME) to $(INSTALL_DIR)..."
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	mv "$(APP_BUNDLE)" "$(INSTALL_DIR)/"
	@echo "Done. You can launch $(APP_NAME) from Applications."

kill:
	pkill -9 -f "SuperOpt" || echo "No running SuperOpt processes found."

run: kill clean install
	open "$(INSTALL_DIR)/$(APP_NAME).app"
