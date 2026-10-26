SHAREDIR ?= /usr/share/ravn/trio
BINDIR ?= /usr/bin
DESTDIR ?=

.PHONY: all install test lint check clean help

all: check

help:
	@echo "ravn-trio targets:"
	@echo "  install  Install pj-trio to $(DESTDIR)$(BINDIR) and helpers to $(DESTDIR)$(SHAREDIR)"
	@echo "  test     Run the test suite"
	@echo "  lint     Run shellcheck on all bash scripts"
	@echo "  check    Run lint and test"

install:
	install -d "$(DESTDIR)$(BINDIR)"
	install -d "$(DESTDIR)$(SHAREDIR)"
	install -m 755 pj-trio "$(DESTDIR)$(BINDIR)/pj-trio"
	install -m 755 trio-status "$(DESTDIR)$(SHAREDIR)/trio-status"
	install -m 644 trio-pm-prompt.md "$(DESTDIR)$(SHAREDIR)/trio-pm-prompt.md"
	install -m 644 trio.conf.example "$(DESTDIR)$(SHAREDIR)/trio.conf.example"

lint:
	shellcheck pj-trio trio-status tests/*.sh

test:
	bash tests/run.sh

check: lint test

clean:
	rm -rf dest
