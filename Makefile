APP_NAME    = KeynoteBuilder
SCRIPT      = $(APP_NAME).applescript
APP_BUNDLE  = $(APP_NAME).app
RESOURCES   = $(APP_BUNDLE)/Contents/Resources

.PHONY: build clean run

build: $(APP_BUNDLE)

$(APP_BUNDLE): $(SCRIPT) fuzzy_match.pl
	osacompile -o $(APP_BUNDLE) $(SCRIPT)
	cp fuzzy_match.pl $(RESOURCES)/

run: build
	open $(APP_BUNDLE)

clean:
	rm -rf $(APP_BUNDLE)
