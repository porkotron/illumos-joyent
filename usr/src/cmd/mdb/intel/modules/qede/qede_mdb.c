/*
 * Copyright 2015 QLogic Corporation
 * The contents of this file are subject to the terms of the
 * QLogic End User License (the "License").
 * You may not use this file except in compliance with the License. 
 * 
 * You can obtain a copy of the License at
 * http://www.qlogic.com/Resources/Documents/DriverDownloadHelp/
 * QLogic_End_User_Software_License.txt
 * See the License for the specific language governing permissions
 * and limitations under the License.
 */
#include "qede.h"
#include <sys/mdb_modapi.h>

static const mdb_dcmd_t qede_mdb_dcmds[] =
{
	NULL
};

static const mdb_walker_t qede_mdb_walkers[] =
{
	NULL
};

static mdb_modinfo_t qede_mdb =
{
	MDB_API_VERSION,
	qede_mdb_dcmds,
	qede_mdb_walkers
};

mdb_modinfo_t * _mdb_init(void)
{
	return (&qede_mdb);
}

void _mdb_fini(void)
{
	return;
}
