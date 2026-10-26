SHAREDIR ?= /usr/share/ravn/trio
BINDIR ?= /usr/bin
DESTDIR ?=

.PHONY: all install test lint check clean help

all: check

help:
	@echo "ravn-trio targets:"
	@echo "  install  Install to $(DESTDIR)$(SHAREDIR) and symlink pj-trio to $(DESTDIR)$(BINDIR)"
	@echo "  test     Run the test suite"
	@echo "  lint     Run shellcheck on all bash scripts"
	@echo "  check    Run lint and test"

install:
	install -d "$(DESTDIR)$(BINDIR)"
	install -d "$(DESTDIR)$(SHAREDIR)/runtime/helper"
	install -d "$(DESTDIR)$(SHAREDIR)/runtime/lib"
	install -d "$(DESTDIR)$(SHAREDIR)/runtime/scripts"
	install -d "$(DESTDIR)$(SHAREDIR)/runtime/completion"
	install -m 755 pj-trio "$(DESTDIR)$(SHAREDIR)/pj-trio"
	install -m 755 trio-status "$(DESTDIR)$(SHAREDIR)/trio-status"
	install -m 644 trio-pm-prompt.md "$(DESTDIR)$(SHAREDIR)/trio-pm-prompt.md"
	install -m 644 trio.conf.example "$(DESTDIR)$(SHAREDIR)/trio.conf.example"
	install -m 644 runtime/commands.tsv "$(DESTDIR)$(SHAREDIR)/runtime/commands.tsv"
	install -m 644 runtime/helper/set_variable.sh "$(DESTDIR)$(SHAREDIR)/runtime/helper/set_variable.sh"
	install -m 644 runtime/lib/*.sh "$(DESTDIR)$(SHAREDIR)/runtime/lib/"
	install -m 755 runtime/scripts/* "$(DESTDIR)$(SHAREDIR)/runtime/scripts/"
	install -m 644 runtime/completion/pj-trio.bash "$(DESTDIR)$(SHAREDIR)/runtime/completion/pj-trio.bash"
	ln -sf "$(SHAREDIR)/pj-trio" "$(DESTDIR)$(BINDIR)/pj-trio"

lint:
	shellcheck -x pj-trio trio-status runtime/scripts/* runtime/lib/*.sh runtime/helper/*.sh runtime/completion/*.bash tests/*.sh

test:
	bash tests/run.sh

check: lint test

clean:
	rm -rf dest
