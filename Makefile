#!/usr/bin/make -f
# Copyright (C) 2021 Torge Matthies
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Author contact info:
#   E-Mail address: openglfreak@googlemail.com
#   PGP key fingerprint: 0535 3830 2F11 C888 9032 FAD2 7C95 CD70 C9E8 438D
.POSIX:

SYSROOT =
PREFIX = $(SYSROOT)/usr/local
SRCDIR = src
EXAMPLESDIR = examples

SHELLCHECK = shellcheck -C
MKDIR = mkdir -p --
CP = cp -LRpf --
TOUCH = touch --
CHMODX = chmod a+x --
RM = rm -f --
RMDIR = rmdir --

all: check

check: $(SRCDIR)/update-efi.sh
	$(SHELLCHECK) -a $(SRCDIR)/update-efi.sh $(EXAMPLESDIR)/*.conf

install: $(PREFIX)/bin/update-efi

$(PREFIX)/bin/update-efi: $(SRCDIR)/update-efi.sh
	$(MKDIR) $(PREFIX)/bin
	$(CP) $(SRCDIR)/update-efi.sh $(PREFIX)/bin/update-efi
	$(TOUCH) $(PREFIX)/bin/update-efi
	$(CHMODX) $(PREFIX)/bin/update-efi

uninstall:
	$(RM) $(PREFIX)/bin/update-efi
	-$(RMDIR) $(PREFIX)/bin 2>/dev/null || :
	-$(RMDIR) $(PREFIX) 2>/dev/null || :

.PHONY: all check install uninstall
.ONESHELL:
