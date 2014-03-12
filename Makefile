INSTALL=ln -s
RM=rm -f

SRCFILES=$(shell ls -d [a-z]*)
BINFILES=$(addprefix $(HOME)/bin/, $(SRCFILES))

usage:
	@echo Usage:
	@echo '	make install	Link scripts to ~/bin.'
	@echo '	make uninstall	Delete scripts from ~/bin.'

install: $(BINFILES)

uninstall:
	$(RM) $(BINFILES)

$(HOME)/bin/%: %
	$(INSTALL) $(PWD)/$< $@
