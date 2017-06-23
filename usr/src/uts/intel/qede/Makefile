#
# This file and its contents are supplied under the terms of the
# Common Development and Distribution License ("CDDL"), version 1.0.
# You may only use this file in accordance with the terms of version
# 1.0 of the CDDL.
#
# A full copy of the text of the CDDL should have accompanied this
# source.  A copy of the CDDL is also available via the Internet at
# http://www.illumos.org/license/CDDL.
#

#
# Copyright (c) 2017 Joyent, Inc.
#

UTSBASE = ../..

MODULE		= qede
OBJECTS		= $(QEDE_OBJS:%=$(OBJS_DIR)/%) $(QEDE_GEN_OBJS:%=$(OBJS_DIR)/%)
LINTS		= $(QEDE_OBJS:%.o=$(LINTS_DIR)/%.ln)
ROOTMODULE	= $(ROOT_DRV_DIR)/$(MODULE)
CONF_SRCDIR	= $(UTSBASE)/common/io/qede

include $(UTSBASE)/intel/Makefile.intel

#
# Common definitions that are used by QLogic.
#
CPPFLAGS	+= -D__inline=inline
CPPFLAGS	+= -D_inline=inline
CPPFLAGS	+= -DILLUMOS

#
# Includes that are needed
#
CPPFLAGS	+= -I$(UTSBASE)/common/io/qede
CPPFLAGS	+= -I$(UTSBASE)/common/io/qede/579xx/drivers/ecore
CPPFLAGS	+= -I$(UTSBASE)/common/io/qede/579xx/drivers/ecore/hsi_repository
CPPFLAGS	+= -I$(UTSBASE)/common/io/qede/579xx/hsi/
CPPFLAGS	+= -I$(UTSBASE)/common/io/qede/579xx/hsi/hw
CPPFLAGS	+= -I$(UTSBASE)/common/io/qede/579xx/hsi/mcp

#
# XXX Temporarily gag this as there are a ton of these in the code base.
#
CERRWARN	+= -_gcc=-Wno-unused-variable
CERRWARN	+= -_gcc=-Wno-unused-label

ALL_TARGET	= $(BINARY) $(CONFMOD)
LINT_TARGET	= $(MODULE).lint
INSTALL_TARGET	= $(BINARY) $(ROOTMODULE) $(ROOT_CONFFILE)

LDFLAGS		+= -dy -N misc/mac

.KEEP_STATE:

def:		$(DEF_DEPS)

all:		$(ALL_DEPS)

clean:		$(CLEAN_DEPS)

clobber:	$(CLOBBER_DEPS)

lint:		$(LINT_DEPS)

modlintlib:	$(MODLINTLIB_DEPS)

clean.lint:	$(CLEAN_LINT_DEPS)

install:	$(INSTALL_DEPS)

include $(UTSBASE)/intel/Makefile.targ
