# Makefile to install nanoca and associated files

# What to install
SCRIPT = nanoca
MANPAGE = nanoca.1
COMPLETION_SCRIPT = nanoca

# Where to install
PREFIX ?= /usr/local
BIN_DIR = $(PREFIX)/bin
SHARE_DIR = $(PREFIX)/share
MAN1_DIR = $(SHARE_DIR)/man/man1
COMPLETION_DIR = $(SHARE_DIR)/bash-completion/completions

.PHONY: all install uninstall clean debug

all:
	@:

install:
	install -D -m 755 bin/$(SCRIPT) $(BIN_DIR)/$(SCRIPT)
	install -D -m 644 man/$(MANPAGE) $(MAN1_DIR)/$(MANPAGE)
	gzip -f $(MAN1_DIR)/$(MANPAGE)
	install -D -m 644 bash-completion/$(COMPLETION_SCRIPT) $(COMPLETION_DIR)/$(COMPLETION_SCRIPT)

uninstall:
	rm -f $(BIN_DIR)/$(SCRIPT)
	rm -f $(MAN1_DIR)/$(MANPAGE).gz
	rm -f $(COMPLETION_DIR)/$(COMPLETION_SCRIPT)

clean:
	@:

debug:
	@echo "Debug printout:"
	@echo "PREFIX=$(PREFIX)"
	@echo "BIN_DIR=$(BIN_DIR)"
	@echo "SHARE_DIR=$(SHARE_DIR)"
	@echo "MAN1_DIR=$(MAN1_DIR)"
	@echo "COMPLETION_DIR=$(COMPLETION_DIR)"
