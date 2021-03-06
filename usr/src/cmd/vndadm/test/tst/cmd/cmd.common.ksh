#
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
# Copyright (c) 2014 Joyent, Inc.  All rights reserved.
#

#
# Common ksh-based utilities
#

vt_arg0=$(basename $0)

function fatal
{
	typeset msg="$*"
	[[ -z "$msg" ]] && msg="failed"
	echo "$vt_arg0: $msg" >&2
	exit 1
}

[[ -z "$1" ]] && fatal "missing required vnic"
[[ -z "$2" ]] && fatal "missing required vnic"
[[ -z "$3" ]] && fatal "missing required vnic"
