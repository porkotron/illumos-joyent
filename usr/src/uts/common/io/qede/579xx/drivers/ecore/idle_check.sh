#!/bin/bash

IDLE_CHECK_LOCATION=../../tools/idle_chk_build

cat << end > ecore_self_test.c
/* self test */

#include "bcm_osal.h"
#include "ecore_gtt_reg_addr.h"
#include "ecore_hsi_common.h"
#include "ecore.h"
#include "ecore_hw.h"
#include "reg_addr.h"

/*statistics and error reporting*/
static int idle_chk_errors;
static int idle_chk_warnings;

#define NA 0xCD

#define IDLE_CHK_ERROR			1
#define IDLE_CHK_ERROR_NO_TRAFFIC	2
#define IDLE_CHK_WARNING		3

#define MAX_FAIL_MSG 200

#define SNPRINTF(a, ...)	do{a[0]=a[0];}while(0)	/* FIXME */

/*struct for the argument list for a predicate in the self test database*/
struct st_pred_args {
	u32 val1; /* value read from first register*/
	u32 val2; /* value read from second register, if applicable */
	u32 imm1; /* 1st value in predicate condition, left-to-right */
	u32 imm2; /* 2nd value in predicate condition, left-to-right */
	u32 imm3; /* 3rd value in predicate condition, left-to-right */
	u32 imm4; /* 4th value in predicate condition, left-to-right */
};

/*struct representing self test record - a single test*/
struct st_record {
	u8 chip_mask;
	u8 macro;
	u32 reg1;
	u32 reg2;
	u16 loop;
	u16 incr;
	int(*predicate)(struct st_pred_args *);
	u32 reg3;
	u8 severity;
	char *failMsg;
	struct st_pred_args pred_args;
};

/* predicates for self test */
static int peq(struct st_pred_args *args)
{
	return (args->val1 == args->imm1);
}

static int pneq(struct st_pred_args *args)
{
	return (args->val1 != args->imm1);
}

static int pand_neq(struct st_pred_args *args)
{
	return ((args->val1 & args->imm1) != args->imm2);
}

static int pand_neq_x2(struct st_pred_args *args)
{
	return (((args->val1 & args->imm1) != args->imm2) &&
		((args->val1 & args->imm3) != args->imm4));
}

static int pneq_err(struct st_pred_args *args)
{
	return ((args->val1 != args->imm1) && (idle_chk_errors > args->imm2));
}

static int pgt(struct st_pred_args *args)
{
	return (args->val1 > args->imm1);
}

static int pneq_r2(struct st_pred_args *args)
{
	return (args->val1 != args->val2);
}

static int plt_sub_r2(struct st_pred_args *args)
{
	return (args->val1 < (args->val2 - args->imm1));
}

static int pne_sub_r2(struct st_pred_args *args)
{
	return (args->val1 != (args->val2 - args->imm1));
}

static int prsh_and_neq(struct st_pred_args *args)
{
	return (((args->val1 >> args->imm1) & args->imm2) != args->imm3);
}

static int peq_neq_r2(struct st_pred_args *args)
{
	return ((args->val1 == args->imm1) && (args->val2 != args->imm2));
}

static int peq_neq_neq_r2(struct st_pred_args *args)
{
	return ((args->val1 == args->imm1) && (args->val2 != args->imm2) &&
		(args->val2 != args->imm3));
}

/* handle self test fails according to severity and type*/
static void ecore_self_test_log(struct ecore_dev *p_dev,
				 u8 severity,
				 char *p_message)
{
	switch (severity) {
	case IDLE_CHK_ERROR:
		DP_ERR(p_dev, "ERROR %s", p_message);
		idle_chk_errors++;
		break;
	case IDLE_CHK_ERROR_NO_TRAFFIC:
		DP_INFO(p_dev, "INFO %s", p_message);
		break;
	case IDLE_CHK_WARNING:
		DP_NOTICE(p_dev, "WARNING %s", p_message);
		idle_chk_warnings++;
		break;
	}
}

static void ecore_idle_reg_rd(struct ecore_path *p_path,
			       u32		    *p_dst,
			       u32		    reg,
			       u32		    offset,
			       int		    ptt)
{
	ecore_ptt_set_win(p_path, ptt, reg - (reg % 4)); /* FIXME */
	*p_dst = REG_RD(p_path, offset + (reg % 4));
}

/*specific test for QM rd/wr pointers and rd/wr banks*/
static void ecore_idle_chk6(struct ecore_path	*p_path,
			     struct st_record	*p_rec,
			     char		*p_message,
			     int 		ptt)
{
	int i;
	u32 rd_ptr, wr_ptr, rd_bank, wr_bank, offset;

	offset = ecore_bar_get_ext_addr(p_path, ptt);

	for (i = 0; i < p_rec->loop; i++) {
		/* read regs */
		ecore_idle_reg_rd(p_path, &p_rec->pred_args.val1,
				  p_rec->reg1 + i * p_rec->incr, offset, ptt);
		ecore_idle_reg_rd(p_path, &p_rec->pred_args.val2,
				  p_rec->reg1 + i * p_rec->incr + 4, offset,
				  ptt);

		/* calc read and write pointers */
		rd_ptr = ((p_rec->pred_args.val1 & 0x3FFFFFC0) >> 6);
		wr_ptr = ((((p_rec->pred_args.val1 & 0xC0000000) >> 30) & 0x3) |
			  ((p_rec->pred_args.val2 & 0x3FFFFF) << 2));

		/* perfrom pointer test */
		if (rd_ptr != wr_ptr) {
			SNPRINTF(p_message, MAX_FAIL_MSG,
				 "QM: PTRTBL entry %d - rd_ptr is not equal to wr_ptr. Values are 0x%x and 0x%x\n",
				 i, rd_ptr, wr_ptr);
			ecore_self_test_log(p_path->p_dev, p_rec->severity,
					    p_message);
		}

		/* calculate read and write banks */
		rd_bank = ((p_rec->pred_args.val1 & 0x30) >> 4);
		wr_bank = (p_rec->pred_args.val1 & 0x03);

		/* perform bank test */
		if (rd_bank != wr_bank) {
			SNPRINTF(p_message, MAX_FAIL_MSG,
				 "QM: PTRTBL entry %d - rd_bank is not equal to wr_bank. Values are 0x%x 0x%x\n",
				 i, rd_bank, wr_bank);
			ecore_self_test_log(p_path->p_dev, p_rec->severity,
					    p_message);
		}
	}
}

/* specific test for cfc info ram and cid cam*/
static void ecore_idle_chk7(struct ecore_path	*p_path,
			     struct st_record	*p_rec,
			     char		*p_message,
			     int 		ptt)
{
	int i;
	u32 offset, tmp = 0;

	offset = ecore_bar_get_ext_addr(p_path, ptt);

	/* iterate through lcids */
	for (i = 0; i < p_rec->loop; i++) {
		/* make sure cam entry is valid (bit 0) */
		ecore_idle_reg_rd(p_path, &tmp, p_rec->reg2 + i *4,
				  offset, ptt);
		if ((tmp & 0x1) != 0x1)
			continue;

		/* get connection type (multiple reads due to widebus) */
		ecore_idle_reg_rd(p_path, &tmp, p_rec->reg1 + i * p_rec->incr,
				  offset, ptt);
		ecore_idle_reg_rd(p_path, &tmp,
				  p_rec->reg1 + i * p_rec->incr + 4,
				  offset, ptt);				  
		ecore_idle_reg_rd(p_path, &p_rec->pred_args.val1,
				  p_rec->reg1 + i * p_rec->incr + 8,
				  offset, ptt);				  
		ecore_idle_reg_rd(p_path, &tmp,
				  p_rec->reg1 + i * p_rec->incr + 12,
				  offset, ptt);

		/* obtain connection type */
		p_rec->pred_args.val1 &= 0x1E000000;
		p_rec->pred_args.val1 >>= 25;

		/* get activity counter value */
		ecore_idle_reg_rd(p_path, &p_rec->pred_args.val2,
				  p_rec->reg3 + i * 4, offset, ptt);

		/* validate ac value is legal for con_type at idle state */
		if (p_rec->predicate(&p_rec->pred_args)) {
			SNPRINTF(p_message, MAX_FAIL_MSG, "%s. Values are "
				"0x%x 0x%x\n", p_rec->failMsg,
				p_rec->pred_args.val1, p_rec->pred_args.val2);
			ecore_self_test_log(p_path->p_dev, p_rec->severity,
					    p_message);
		}
	}
}

/* struct holding the database of self test checks (registers and predicates) */
/* lines start from 2 since line 1 is heading in csv*/
end

perl ${IDLE_CHECK_LOCATION}/idle_chk_db.pl ${IDLE_CHECK_LOCATION}/idle_check.csv >> ecore_self_test.c

cat << end >>  ecore_self_test.c

/* self test procedure
 * scan auto-generated database
 * for each line:
 * 1.	compare chip mask
 * 2.	determine type (according to maro number)
 * 3.	read registers
 * 4.	call predicate
 * 5.	collate results and statistics
 */
int ecore_idle_chk(struct ecore_path *p_path, bool b_print)
{
	u16 i;				/* loop counter */
	u16 st_ind;			/* self test database access index */
	struct st_record rec;		/* current record variable */
	char message[MAX_FAIL_MSG];	/* message to log */
	int ptt;
	u32 offset, tmp = 0;

	/*init stats*/
	idle_chk_errors = 0;
	idle_chk_warnings = 0;

	ptt = ecore_ptt_acquire(p_path, 0xdeadbadd); /* FIXME - owner? */
	offset = ecore_bar_get_ext_addr(p_path, ptt);

	/*database main loop*/
	for (st_ind = 0; st_ind < ST_DB_LINES; st_ind++) {
		rec = st_database[st_ind];

		/* identify macro */
		switch (rec.macro) {
		case 1:
			/* read single reg and call predicate */
			ecore_idle_reg_rd(p_path, &rec.pred_args.val1,
					 rec.reg1, offset, ptt);
			DP_VERBOSE(p_path->p_dev, ECORE_MSG_HW,
				   "mac1 add %x\n", rec.reg1);
			if (rec.predicate(&rec.pred_args)) {
				SNPRINTF(message, sizeof(message),
					"%s.Value is 0x%x\n", rec.failMsg,
					rec.pred_args.val1);
				ecore_self_test_log(p_path->p_dev, rec.severity,
						    message);
			}
			break;
		case 2:
			/* read repeatedly starting from reg1 and call
			 * predicate after each read
			 */
			for (i = 0; i < rec.loop; i++) {
				ecore_idle_reg_rd(p_path, &rec.pred_args.val1,
						  rec.reg1 + i * rec.incr,
						  offset, ptt);
				DP_VERBOSE(p_path->p_dev, ECORE_MSG_HW,
					   "mac2 add %x\n", rec.reg1);
				if (rec.predicate(&rec.pred_args)) {
					SNPRINTF(message, sizeof(message),
						"%s. Value is 0x%x in loop %d\n",
						rec.failMsg,
						rec.pred_args.val1, i);
					ecore_self_test_log(p_path->p_dev,
							    rec.severity,
							    message);
				}
			}
			break;
		case 3:
			/* read two regs and call predicate */
			ecore_idle_reg_rd(p_path, &rec.pred_args.val1,
						  rec.reg1, offset, ptt);
			ecore_idle_reg_rd(p_path, &rec.pred_args.val2,
						  rec.reg2, offset, ptt);
			DP_VERBOSE(p_path->p_dev, ECORE_MSG_HW,
				   "mac3 add1 %x add2 %x\n",
				   rec.reg1, rec.reg2);
			if (rec.predicate(&rec.pred_args)) {
				SNPRINTF(message, sizeof(message),
					 "%s. Values are 0x%x 0x%x\n",
					 rec.failMsg, rec.pred_args.val1,
					 rec.pred_args.val2);
				ecore_self_test_log(p_path->p_dev, rec.severity,
						    message);
			}
			break;
		case 4:
			/*unused to-date*/
			for (i = 0; i < rec.loop; i++) {
				ecore_idle_reg_rd(p_path, &rec.pred_args.val1,
						  rec.reg1 + i * rec.incr,
						  offset, ptt);
				ecore_idle_reg_rd(p_path, &rec.pred_args.val2,
						  rec.reg2 + i * rec.incr,
						  offset, ptt);
				rec.pred_args.val2 >>= 1;
				if (rec.predicate(&rec.pred_args)) {
					SNPRINTF(message, sizeof(message),
						 "%s. Values are 0x%x 0x%x in loop %d\n", rec.failMsg,
						 rec.pred_args.val1,
						 rec.pred_args.val2, i);
					ecore_self_test_log(p_path->p_dev,
							    rec.severity,
							    message);
				}
			}
			break;
		case 5:
			/* compare two regs, pending
			 * the value of a condition reg
			 */
			ecore_idle_reg_rd(p_path, &rec.pred_args.val1,
					  rec.reg1, offset, ptt);
			ecore_idle_reg_rd(p_path, &rec.pred_args.val2,
					  rec.reg2, offset, ptt);
			DP_VERBOSE(p_path->p_dev, ECORE_MSG_HW,
				   "mac3 add1 %x add2 %x add3 %x\n",
				   rec.reg1, rec.reg2, rec.reg3);
			ecore_idle_reg_rd(p_path, &tmp,
					  rec.reg3, offset, ptt);
			if (!tmp && rec.predicate(&rec.pred_args)) {
				SNPRINTF(message, sizeof(message),
					 "%s. Values are 0x%x 0x%x\n",
					 rec.failMsg, rec.pred_args.val1,
					 rec.pred_args.val2);
				ecore_self_test_log(p_path->p_dev,
						    rec.severity,
						    message);
			}
			break;
		case 6:
			/* compare read and write pointers
			 * and read and write banks in QM
			 */
			ecore_idle_chk6(p_path, &rec, message, ptt);
			break;
		case 7:
			/*compare cfc info cam with cid cam*/
			ecore_idle_chk7(p_path, &rec, message, ptt);
			break;
		default:
			DP_VERBOSE(p_path->p_dev, ECORE_MSG_HW,
				   "unknown macro in self test data base. macro %d line %d",
				   rec.macro, st_ind);
		}
	}

	ecore_ptt_release(p_path, ptt);

	if (!b_print)
		return idle_chk_errors;

	/* return value accorindg to statistics */
	if (idle_chk_errors == 0) {
		DP_VERBOSE(p_path->p_dev, ECORE_MSG_HW,
			   "completed successfully (logged %d warnings)\n",
			   idle_chk_warnings);
	} else {
		DP_NOTICE(p_path->p_dev,
			  "failed (with %d errors, %d warnings)\n",
			  idle_chk_errors, idle_chk_warnings);
	}

	return idle_chk_errors;
}

end

echo ecore_self_test.c is ready

