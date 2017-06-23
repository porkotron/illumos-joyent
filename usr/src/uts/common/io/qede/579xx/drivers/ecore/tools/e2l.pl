#!/usr/bin/perl -w
use File::Basename;

##############################################################################
#                            Data Base                                       #
##############################################################################

# When translating OSAL code into linux code, sometimes linux headers are need to define data structures or functionality.
# E.g., when using osal_list_t, on linux we'll need to add "#include "linux/list.h"
our %includes_global_table = (
	mutex => "linux/mutex.h",
	list => "linux/list.h",
	semaphore => "linux/semaphore.h",
	delay => "linux/delay.h",
	sleep => "linux/delay.h",
	alloc => "linux/slab.h",
	DIV_ROUND_UP => "linux/kernel.h",
	roundup => "linux/kernel.h",
	ARRAY_SIZE => "linux/kernel.h",
	memset => "linux/string.h",
	REG_WR => "linux/io.h",
	ENOMEM => "linux/errno.h",
	DP_MODULE => "linux/compiler.h",
	DP_LEVEL => "linux/kernel.h",
	list_first_entry => "linux/kernel.h",
	LINUX_VERSION_CODE => "linux/version.h",
	NULL => "linux/kernel.h",
	spinlock => "linux/spinlock.h",
	spin_lock => "linux/spinlock.h",
	coherent => "linux/dma-mapping.h",
	cpu_to_le32 => "asm/byteorder.h",
	le32_to_cpu => "asm/byteorder.h",
	cpu_to_le16 => "asm/byteorder.h",
	le16_to_cpu => "asm/byteorder.h",
	cpu_to_be32 => "asm/byteorder.h",
	be32_to_cpu => "asm/byteorder.h",
	memcpy => "linux/string.h",
	mmiowb => "linux/io.h",
	pdev => "linux/pci.h",
	_bit => "linux/bitops.h",
	is_valid_ether_addr => "linux/etherdevice.h",
	PCI_EXT_CAP_ID_SRIOV => "linux/pci_regs.h",
	roundup_pow_of_two => "linux/log2.h",
	ilog2 => "linux/log2.h",
	tasklet => "linux/interrupt.h",
	BUILD_BUG_ON => "linux/bug.h",
	EXPORT_SYMBOL => "linux/module.h",
	delayed_work => "linux/workqueue.h",
	z_stream_s => "linux/zlib.h",
	"struct firmware" => "linux/firmware.h",
	vzalloc => "linux/vmalloc.h",
	num_present_cpus => "linux/cpumask.h",
	vlan_ethhdr => "linux/if_vlan.h",
	ethhdr => "linux/if_ether.h",
	iphdr => "linux/ip.h",
	ipv6hdr => "linux/ipv6.h",
	tcphdr => "linux/tcp.h",
	WARN => "linux/bug.h",
	crc32 => "linux/crc32.h",
	kstrtoul => "linux/kernel.h",
	DECLARE_CRC8_TABLE => "linux/crc8.h",
	crc8_populate_msb => "linux/crc8.h", # 'crc8' is not explicitly listed since this string appears also in ecore_dbg_values.h
	L1_CACHE_BYTES => "asm/cache.h",
);

# Like previous, only here global headers are added under some ifdef, mostly due to compatibility
our %includes_global_dependent_table = (
	DECLARE_HASHTABLE => { "HEADER" => "linux/hashtable.h", "LIMIT" => "defined(QED_UPSTREAM)" },
	"linux/fs.h" => { "HEADER" => "linux/fs.h", "LIMIT" => "defined(CONFIG_DEBUG_FS)" },
	"linux/debugfs.h" => { "HEADER" => "linux/debugfs.h", "LIMIT" => "defined(CONFIG_DEBUG_FS)" },

);

# Due [mostly] to relocation of code, it's possible that new local inclusion will be needed.
# E.g., eth_stats are moved into a qed interface file, so that file needs to be included whenever the struct is accessed.
our %includes_local_table = (
	DECLARE_HASHTABLE => "qed_compat.h",
	eth_stats => "qed_if.h",
	fcoe_stats => "qed_fcoe_if.h",
	iscsi_stats => "qed_iscsi_if.h",
	qed_ll2_stats => "qed_ll2_if.h",
	rdma_start_in_params => "qed_roce_if.h",
	qed_copy_preconfig_to_bus => "qed_debugfs.h",
	QED_RSS => "qed_eth_if.h",
);

# Same relation to the local_table as the global_dependent had to the global_table
our %includes_local_dependent_table = (
	"qed_init_values_zipped.h" => { "HEADER" => "qed_init_values_zipped.h", "LIMIT" => "defined(CONFIG_QED_ZIPPED_FW) && !defined(CONFIG_QED_BINARY_FW)" },
	"qed_init_values.h" => { "HEADER" => "qed_init_values.h", "LIMIT" => "!defined(CONFIG_QED_ZIPPED_FW) && !defined(CONFIG_QED_BINARY_FW)" },
);

# Until we'll have a working binary file that replaces generated arrays, we need to prevent the inclusion of some of them,
# dependent on their actual usage.
our %prevent_table = (
	dump_mem => {"prevent_symbol" => "DUMP_MEM_ARR", "found" => 0 },
	pxp_global_win => {"prevent_symbol" => "PXP_GLOBAL_WIN", "found" => 0 },
);

# Hashes to mark whether a given symbol was found or not
our %used_ig = ();
our @il_order = ( "common_hsi.h", "storage_common.h", "tcp_common.h", "fcoe_common.h", "iscsi_common.h" );
our %used_il = ();
our %used_igt = ();
our %used_igdt = ();
our %used_ilt = ();
our %used_ildt = ();

# These should remain as "xxx_t" and not transformed into "struct xxx"
our $allowed_t = qr {(?<!dma_addr)(?<!size)(?<!spinlock)(?<!qed_int_comp_cb)(?<!iscsi_event_cb)(?<!affiliated_event)(?<!unaffiliated_event)(?<!pci_power)(?<!skb_frag)};

# A parameter is anything between the "," - it can contain "struct", sizeof(),
# ->, . and many other things - in short, anything that is not a comma.
our $parm = qr{\s*([^,\s][^,]*[^,\s]:?)\s*};

our $comment_start = qr{\/\*};
our $comment_end = qr{\*\/};
our $c_line_end = qr{\;|\{|\}|$comment_end};

our $pp_line = qr{\s*\#\s*};
# when set, current scope is inside a pre-processor segment
our $pp_segment = 0;
# when set, we're inside the context of a multi-lined comment
our $inside_cmt = 0;

##############################################################################
#                               Subroutines                                  #
##############################################################################

sub correct_include {
	my ($inc_file, $name_to_use, $file_arr) = @_;

	for my $filename (@$file_arr) {
		if (${$inc_file} eq $filename) {
			${$inc_file} = $name_to_use;
			return 1;
		}
	}

	return 0;
}

# Given a local include header, make sure we're not including a united file.
# If so, include the combined file instead. Also make sure we're not including
# ourselves.
sub translate_include_private {
	my @file_add_qed = ( "reg_addr.h" );
	my @file_common = ( "common_hsi.h", "qed_utils.h" );
	my @file_cxt = ( "qed_cxt.h", "qed_cxt_api.h" );
	my @file_fcoe = ( "qed_fcoe.h", "qed_fcoe_api.h" );
	my @file_iscsi = ( "qed_iscsi.h", "qed_iscsi_api.h" );
	my @file_roce = ( "qed_roce.h", "qed_roce_api.h" );
	my @file_l2 = ( "qed_l2.h", "qed_l2_api.h" );
	my @file_ll2 = ( "qed_ll2.h", "qed_ll2_api.h" );
	my @file_mcp = ( "qed_mcp.h", "qed_mcp_api.h" );
	my @file_dcbx = ( "qed_dcbx.h", "qed_dcbx_api.h" );
	my @file_int = ( "qed_int.h", "qed_int_api.h", "qed_hw_defs.h" );
	my @file_sp = ( "qed_sp_commands.h", "qed_sp_api.h", "qed_spq.h" );
	my @file_sriov = ( "qed_sriov.h", "qed_iov_api.h" );
	my @file_qed_if = ( "qed_proto_if.h" );
	my @file_vf = ( "qed_vf.h", "qed_vf_api.h" , "qed_vfpf_if.h" );
	my @file_ptp = ( "qed_ptp_api.h" );
	my @file_selftest = ( "qed_selftest_api.h" );
	my @file_hsi = ( "pcics_reg_driver.h", "qed_attn_values.h" , "qed_dbg_fw_funcs.h" , "qed_dbg_values.h" , "qed_fw_funcs_defs.h" , "qed_gtt_reg_addr.h" , "qed_gtt_values.h" , "qed_init_defs.h" , "qed_init_fw_funcs.h", "qed_iro.h" , "qed_iro_values.h", "qed_rt_defs.h" , "qed_hsi_common.h" , "qed_hsi_eth.h" , "qed_hsi_toe.h" , "qed_hsi_roce.h" , "qed_hsi_iwarp.h", "qed_hsi_rdma.h" , "qed_hsi_fcoe.h" , "qed_hsi_iscsi.h" , "mcp_public.h" , "nvm_cfg.h", "mfw_hsi.h" , "spad_layout.h", "nvm_map.h" , "qed_hsi_debug_tools.h", "qed_hsi_init_func.h", "qed_hsi_init_tool.h");

	# Skip certain inclusions
	if ($_[0] =~ m/bcm_osal.h|qed_status.h/) {
		return 1;
	}

	if (correct_include(\$_[0], "qed_$_[0]", \@file_add_qed)) {}
	elsif (correct_include(\$_[0], "qed_hsi.h", \@file_hsi)) {}
	elsif (correct_include(\$_[0], "common_hsi.h", \@file_common)) {}
	elsif (correct_include(\$_[0], "qed_cxt.h", \@file_cxt)) {}
	elsif (correct_include(\$_[0], "qed_fcoe.h", \@file_fcoe)) {}
	elsif (correct_include(\$_[0], "qed_iscsi.h", \@file_iscsi)) {}
	elsif (correct_include(\$_[0], "qed_roce.h", \@file_roce)) {}
	elsif (correct_include(\$_[0], "qed_l2.h", \@file_l2)) {}
	elsif (correct_include(\$_[0], "qed_ll2.h", \@file_ll2)) {}
	elsif (correct_include(\$_[0], "qed_mcp.h", \@file_mcp)) {}
	elsif (correct_include(\$_[0], "qed_dcbx.h", \@file_dcbx)) {}
	elsif (correct_include(\$_[0], "qed_int.h", \@file_int)) {}
	elsif (correct_include(\$_[0], "qed_sp.h", \@file_sp)) {}
	elsif (correct_include(\$_[0], "qed_sriov.h", \@file_sriov)) {}
	elsif (correct_include(\$_[0], "qed_vf.h", \@file_vf)) {}
	elsif (correct_include(\$_[0], "qed_if.h", \@file_qed_if)) {}
	elsif (correct_include(\$_[0], "qed_ptp_api.h", \@file_ptp)) {}
	elsif (correct_include(\$_[0], "qed_selftest.h", \@file_selftest)) {}


	# Skip this inclusion if it's same as current filename
	if ($_[0] eq $target_filename) {
		return 1;
	}

	return 0;
}

sub create_include_list {
	if ($_[0] =~ m/${pp_line}include/) {
		if ($_[0] =~ m/${pp_line}include\s*\"(.+)\"/) {
			#Translate private includes
			my $inc_file = $1;
			if (translate_include_private($inc_file) == 0) {
				if (exists $includes_local_dependent_table{$inc_file}) {
					$used_ildt{$inc_file} = 1;
				} else {
					$used_il{$inc_file} = 1;
				}
			}
		} elsif ($_[0] =~ /${pp_line}include\s*<(.+)>/) {
			my $inc_file = $1;
			if (exists $includes_global_dependent_table{$inc_file}) {
				$used_igdt{$inc_file} = 1;
			} else {
				$used_ig{$inc_file} = 1;
			}
		}
		return 1;
	} else {
		# There isn't an explicit #include; Instead, need to determine whether
		# there's need to include something as result of line's content.
		foreach $inc (keys %includes_global_table) {
			if ($_[0] =~ m/$inc/) {
				$used_igt{$includes_global_table{$inc}} = 1;
			}
		}
		foreach $inc (keys %includes_global_dependent_table) {
			if ($_[0] =~ m/$inc/) {
				$used_igdt{$inc} = 1;
			}
		}
		foreach $inc (keys %includes_local_table) {
			if ($_[0] =~ m/$inc/) {
				my $include_name = $includes_local_table{$inc};
				if (translate_include_private($include_name) == 0) {
					$used_ilt{$include_name} = 1;
				}
			}
		}
		foreach $inc (keys %includes_local_dependent_table) {
			if ($_[0] =~ m/$inc/) {
				my $include_name = $includes_local_dependent_table{$inc}{"HEADER"};
				if (translate_include_private($include_name) == 0) {
					$used_ildt{$inc} = 1;
				}
			}
		}
		foreach $inc (keys %prevent_table) {
			if ($_[0] =~ m/$inc/) {
				$prevent_table{$inc}{"found"} = 1;
			}
		}
	}

	return 0;
}

# Translation function - each line of the code will go through this function
# after consolidating all functions and macros to a single line (the 80 columns
# will be enforced later)
sub translate_line {
	# The for loop is just there to avoid the "@_ =~" prefix in each line:
	for (@_) {
		s/OSAL_DIV_S64/div64_s64/go;
		s/\bROUNDUP\b/roundup/go;
		s/OSAL_UDELAY/udelay/go;
		s/OSAL_NUM_ACTIVE_CPU/num_present_cpus/go;
		s/OSAL_ROUNDUP_POW_OF_TWO/roundup_pow_of_two/g;
		s/OSAL_LOG2/ilog2/g;

		s/OSAL_SET_BIT/__set_bit/go;
		s/OSAL_CLEAR_BIT/clear_bit/go;
		s/OSAL_TEST_BIT/test_bit/go;
		s/OSAL_TEST_AND_CLEAR_BIT/test_and_clear_bit/go;
		s/OSAL_FIND_FIRST_ZERO_BIT/find_first_zero_bit/go;
		s/OSAL_FIND_FIRST_BIT/find_first_bit/go;
		s/OSAL_BITMAP_WEIGHT/bitmap_weight/go;
		s/OSAL_TEST_AND_FLIP_BIT/test_and_change_bit/go;
		s/OFFSETOF/offsetof/go;
		s/\(sizeof\(unsigned long\) \* 8 \/\* BITS_PER_LONG \*\/\)/BITS_PER_LONG/go;

		s/OSAL_MEMSET/memset/g;
		s/OSAL_ARRAY_SIZE/ARRAY_SIZE/g;
		s/OSAL_STRCPY/strcpy/g;
		s/OSAL_STRNCPY/strncpy/g;
		s/OSAL_STRLEN/strlen/g;
		s/OSAL_STRCMP/strcmp/g;
		s/OSAL_SPRINTF/sprintf/g;
		s/OSAL_SNPRINTF/snprintf/g;
		s/OSAL_STRTOUL/kstrtoul/g;
		s/OSAL_INLINE/inline/g;
		s/OSAL_NULL/NULL/g;
		s/OSAL_MIN_T/min_t/g;
		s/OSAL_MAX_T/max_t/g;
		s/OSAL_REG_ADDR/REG_ADDR/g;
		s/OSAL_PAGE_SIZE/PAGE_SIZE/g;
		s/OSAL_CACHE_LINE_SIZE/L1_CACHE_BYTES/g;
		s/OSAL_BUILD_BUG_ON/BUILD_BUG_ON/g;
		s/OSAL_IOMEM/__iomem/g;
		s/OSAL_UNLIKELY/unlikely/g;
		s/osal_size_t/size_t/g;
		s/osal_uintptr_t/uintptr_t/g;
		s/U64_HI/upper_32_bits/g;
		s/U64_LO/lower_32_bits/g;

		# OSAL_MSLEEP --> msleep for big values
		if ($_ =~ /OSAL_MSLEEP\(([0-9]*)\)/) {
			$value = $1;
			if ($value  < 20) {
				$down = $value * 1000;
				$up = $value * 2000;
				s/OSAL_MSLEEP\(([0-9]*)\)/usleep_range($down, $up)/go;
			} else {
				s/OSAL_MSLEEP/msleep/go;
			}
		}
		s/OSAL_MSLEEP/msleep/go;

		s/OSAL_NVM_IS_ACCESS_ENABLED\(p_hwfn\)/1/go;

		#DPC related
		s/OSAL_DPC_INIT\($parm,$parm\)/tasklet_init($1, ecore_int_sp_dpc, (long unsigned int)$2)/go;
		s/osal_dpc_t/struct tasklet_struct */go;
		s/OSAL_DPC_ALLOC\($parm\)/kmalloc(sizeof(struct tasklet_struct), GFP_KERNEL)/go;
		s/OSAL_POLL_MODE_DPC\($parm\)//go;
		s/OSAL_DPC_SYNC\($parm\)/qed_slowpath_irq_sync($1)/go;
		s/osal_int_ptr_t/long unsigned int/go;

		s/OSAL_ALLOC\($parm,$parm,$parm\)/kmalloc($3, $2)/g;
		s/OSAL_ZALLOC\($parm,$parm,$parm\)/kzalloc($3, $2)/g;
		s/OSAL_CALLOC\($parm,$parm,$parm,$parm\)/kcalloc($3, $4, $2)/g;
		s/OSAL_VZALLOC\($parm,$parm\)/vzalloc($2)/g;
		s/OSAL_FREE\($parm,$parm\)/kfree($2)/g;
		s/OSAL_VFREE\($parm,$parm\)/vfree($2)/g;
		s/OSAL_MEM_ZERO\($parm,$parm\)/memset($1, 0, $2)/g;
		s/OSAL_MEMCPY/memcpy/g;
		s/OSAL_MEMCMP/memcmp/g;

		s/OSAL_DMA_ALLOC_COHERENT\($parm,$parm,$parm\)/dma_alloc_coherent(\&$1->pdev->dev, $3, $2, GFP_KERNEL)/g;
		s/OSAL_DMA_FREE_COHERENT\($parm,$parm,$parm,$parm\)/dma_free_coherent(\&$1->pdev->dev, $4, $2, $3)/g;
		s/OSAL_MMIOWB\($parm\)/mmiowb()/go;
		s/OSAL_BARRIER\($parm\)/barrier()/go;
		s/OSAL_SMP_WMB\($parm\)/smp_wmb()/go;
		s/OSAL_SMP_RMB\($parm\)/smp_rmb()/go;
		s/OSAL_RMB\($parm\)/rmb()/go;
		s/OSAL_WMB\($parm\)/wmb()/go;

		# There are some OSALs that simply need to be removed
		s/OSAL_SPIN_LOCK_ALLOC\([\s\S]*\)//go;
		s/OSAL_SPIN_LOCK_DEALLOC\($parm\)//go;
		s/OSAL_MUTEX_ALLOC\([\s\S]*\)//go;
		s/OSAL_MUTEX_DEALLOC\($parm\)//go;
		s/OSAL_DMA_SYNC\([\s\S]*\)//go;
		s/OSAL_HW_INFO_CHANGE\([\s\S]*\)\s*;//go;

		s/osal_mutex/mutex/go;
		s/OSAL_MUTEX_INIT/mutex_init/go;
		s/OSAL_MUTEX_ACQUIRE\($parm\)/mutex_lock($1)/g;
		s/OSAL_MUTEX_RELEASE\($parm\)/mutex_unlock($1)/g;
		s/osal_spinlock_t/spinlock_t/go;
		s/OSAL_SPIN_LOCK_INIT/spin_lock_init/go;
		s/OSAL_SPIN_LOCK_IRQSAVE/spin_lock_irqsave/go;
		s/OSAL_SPIN_UNLOCK_IRQSAVE/spin_unlock_irqrestore/go;
		s/OSAL_SPIN_LOCK/spin_lock_bh/go;
		s/OSAL_SPIN_UNLOCK/spin_unlock_bh/go;

		s/OSAL_LIST_INIT/INIT_LIST_HEAD/go;
		s/OSAL_LIST_PUSH_TAIL\($parm,$parm\)/list_add_tail($1, $2)/g;
		s/OSAL_LIST_PUSH_HEAD\($parm,$parm\)/list_add($1, $2)/g;
		s/OSAL_LIST_REMOVE_ENTRY\($parm,$parm\)/list_del($1)/g;
		s/OSAL_LIST_FOR_EACH_ENTRY\($parm,$parm,$parm,$parm\)/list_for_each_entry($1, $2, $3)/g;
		s/OSAL_LIST_FOR_EACH_ENTRY_SAFE\($parm,$parm,$parm,$parm,$parm\)/list_for_each_entry_safe($1, $2, $3, $4)/g;
		s/OSAL_LIST_FIRST_ENTRY\($parm,$parm,$parm\)/list_first_entry($1, $2, $3)/g;
		s/OSAL_LIST_IS_EMPTY\($parm\)/list_empty($1)/g;
		s/osal_list_entry/list_head/go;
		s/osal_list/list_head/go;

		# OSAL_LIST_INSERT_ENTRY_BEFORE --> list_add_tail
		s/OSAL_LIST_INSERT_ENTRY_BEFORE\($parm,$parm,$parm\)/list_add_tail($1, $2)/g;

		# OSAL_LIST_INSERT_ENTRY_AFTER --> list_add
		s/OSAL_LIST_INSERT_ENTRY_AFTER\($parm,$parm,$parm\)/list_add($1, $2)/g;

		# OSAL_LIST_SPLICE_INIT --> list_splice_init 
		s/OSAL_LIST_SPLICE_INIT\($parm,$parm\)/list_splice_init($1, $2)/g;

		# OSAL_LIST_SPLICE_TAIL_INIT --> list_splice_tail_init 
		s/OSAL_LIST_SPLICE_TAIL_INIT\($parm,$parm\)/list_splice_tail_init($1, $2)/g;

		# SRIOV related
		s/ECORE_IOV/QED_IOV/go;
		s/OSAL_VF_SEND_MSG2PF\(.*\)/0/g;
		s/return OSAL_PF_VF_MSG\($parm,$parm\)/qed_schedule_iov($1, QED_IOV_WQ_MSG_FLAG);\nreturn 0/g;
		s/OSAL_PF_VF_MALICIOUS\($parm,$parm\);//g;
		s/OSAL_IOV_CHK_UCAST/qed_iov_chk_ucast/g;
		s/OSAL_VF_UPDATE_ACQUIRE_RESC_RESP\(.*\)/0/g;
		s/OSAL_VF_FILL_ACQUIRE_RESC_REQ\(${parm},${parm},${parm}/qed_vf_fill_driver_data\($1, $3/g;
		s/OSAL_VF_CQE_COMPLETION\(.*\)/0/g;
		s/OSAL_IOV_GET_OS_TYPE\(\)/VFPF_ACQUIRE_OS_LINUX/g;
		s/OSAL_VF_FLR_UPDATE\($parm\)/qed_schedule_iov($1, QED_IOV_WQ_FLR_FLAG)/g;
		s/OSAL_BEFORE_PF_START/qed_copy_preconfig_to_bus/go;
		s/OSAL_AFTER_PF_STOP/qed_copy_bus_to_postconfig/go;
		s/OSAL_IOV_POST_START_VPORT\([\s\S]*\);//go;
		s/OSAL_IOV_PRE_START_VPORT/qed_iov_pre_start_vport/go;
		s/OSAL_IOV_VF_CLEANUP/qed_iov_clean_vf/go;
		s/OSAL_IOV_VF_VPORT_UPDATE/qed_iov_pre_update_vport/go;
		s/OSAL_IOV_VF_VPORT_STOP\($parm,$parm\);//go;
		s/OSAL_PF_VALIDATE_MODIFY_TUNN_CONFIG/qed_pf_validate_modify_tunn_config/go;
		s/OSAL_IOV_VF_MSG_TYPE\([\s\S]*\);//go;
		s/OSAL_IOV_PF_RESP_TYPE\([\s\S]*\);//go;

		# Zipped firmwre data related
		s/OSAL_UNZIP_DATA/qed_unzip_data/g;

		# Link related
		s/OSAL_LINK_UPDATE/qed_link_update/g;

		# DCBX Async Event Notification
		s/OSAL_DCBX_AEN/qed_dcbx_aen/g;

		# Recovery related
		s/OSAL_SCHEDULE_RECOVERY_HANDLER/qed_schedule_recovery_handler/g;
		s/OSAL_HW_ERROR_OCCURRED/qed_hw_error_occurred/g;

		# Statistics related
		s/OSAL_GET_PROTOCOL_STATS/qed_get_protocol_stats/g;

		# Prepare ISR for the slowpath interrupt
		s/OSAL_SLOWPATH_IRQ_REQ/qed_slowpath_irq_req/g;

		# ROCE related
		s/OSAL_GET_RDMA_SB_ID\($parm,$parm\)/qed_rdma_get_sb_id\($1, $2)/g;

		# MFW TLV related
		s/OSAL_MFW_TLV_REQ/qed_mfw_tlv_req/g;

		# MFW TLV related
		s/OSAL_MFW_FILL_TLV_DATA/qed_mfw_fill_tlv_data/g;

		# Some black voodoo magic for DP_NOTICE, to allow ecore sources to use 'is_assert'
		# While qed sources don't use that parameter [but those sources might still be processed here.
		s/DP_NOTICE\(${parm},${parm},\s*\"${parm}/DP_NOTICE\($1, \"$3/g;
		s/DP_NOTICE\(p_dev, is_assert, fmt/DP_NOTICE\(cdev, fmt/g;

		s/\(1 << ${parm}\)/BIT\($1\)/g;

		s/OSAL_ASSERT.*;//go;
		s/OSAL_WARN/WARN/go;
		s/#define CHECK_ARR_SIZE.*//go;
		s/CHECK_ARR_SIZE.*;//go;

		# This is hard-coded, but it's unlikely the DP_* macros would change in ecore.h.
		# If they do - we'll fix this as well.
		s/PRINT_ERR\(${parm}, /pr_err\(/go;
		s/PRINT\(${parm}, /pr_notice\(/go;
		s/\(p_dev\)->name/DP_NAME\(cdev\)/go;
		s/ECORE_MSG_DRV/NETIF_MSG_DRV/go;
		s/ECORE_MSG_PROBE/NETIF_MSG_PROBE/go;
		s/ECORE_MSG_LINK/NETIF_MSG_LINK/go;
		s/ECORE_MSG_TIMER/NETIF_MSG_TIMER/go;
		s/ECORE_MSG_IFDOWN/NETIF_MSG_IFDOWN/go;
		s/ECORE_MSG_IFUP/NETIF_MSG_IFUP/go;
		s/ECORE_MSG_RX_ERR/NETIF_MSG_RX_ERR/go;
		s/ECORE_MSG_TX_ERR/NETIF_MSG_TX_ERR/go;
		s/ECORE_MSG_TX_QUEUED/NETIF_MSG_TX_QUEUED/go;
		s/ECORE_MSG_INTR/NETIF_MSG_INTR/go;
		s/ECORE_MSG_TX_DONE/NETIF_MSG_TX_DONE/go;
		s/ECORE_MSG_RX_STATUS/NETIF_MSG_RX_STATUS/go;
		s/ECORE_MSG_PKTDATA/NETIF_MSG_PKTDATA/go;
		s/ECORE_MSG_HW/NETIF_MSG_HW/go;
		s/ECORE_MSG_WOL/NETIF_MSG_WOL/go;

		# Change the components ifdefs
		s/CONFIG_ECORE_ROCE/CONFIG_QEDR/go;
		s/CONFIG_ECORE_IWARP/CONFIG_IWARP/go;
		s/CONFIG_ECORE_FCOE/CONFIG_QEDF/go;
		s/CONFIG_ECORE_ISCSI/CONFIG_QEDI/go;
		s/CONFIG_ECORE_L2/CONFIG_QEDE/go;

		#Endianity
		s/OSAL_BE32_TO_CPU/be32_to_cpu/g;
		s/OSAL_CPU_TO_BE32/cpu_to_be32/g;
		s/OSAL_CPU_TO_BE64/cpu_to_be64/g;
		s/OSAL_BE32/__be32/g;
		s/OSAL_CPU_TO_LE32/cpu_to_le32/g;
		s/OSAL_CPU_TO_LE16/cpu_to_le16/g;
		s/OSAL_LE32_TO_CPU/le32_to_cpu/g;
		s/OSAL_LE16_TO_CPU/le16_to_cpu/g;

		# CRC-32
		s/OSAL_CRC32/crc32/g;

		# CRC-8
		s/static u8 cdu_crc8_table\[CRC8_TABLE_SIZE\]/DECLARE_CRC8_TABLE(cdu_crc8_table)/g;
		s/OSAL_CRC8_POPULATE/crc8_populate_msb/g;
		s/OSAL_CRC8/crc8/g;

		# Struct initialization (C99):
		s/${comment_start}\s*SF\:${parm}${comment_end}/.$1 = /g;

		# Ecore return values
		s/enum _ecore_status_t/int/go;
		s/ECORE_SUCCESS/0/go;
		s/ECORE_NOMEM/-ENOMEM/go;
		s/ECORE_BUSY/-EBUSY/go;
		s/ECORE_TIMEOUT/-EBUSY/go; # FIXME - probably not the right one
		s/ECORE_ABORTED/-EBUSY/go;
		s/ECORE_INVAL/-EINVAL/go;
		s/ECORE_NORESOURCES/-EINVAL/go;
		s/ECORE_NOTIMPL/-EINVAL/go;
		s/ECORE_UNKNOWN_ERROR/-EINVAL/go;
		s/ECORE_AGAIN/-EAGAIN/go;
		s/ECORE_EXISTS/-EEXIST/go;
		s/ECORE_NODEV/-ENODEV/go;
		s/ECORE_IO/-EIO/go;
		s/ECORE_CONN_RESET/-ECONNRESET/go;
		s/ECORE_CONN_REFUSED/-ECONNREFUSED/go;

		# TODO - this should be generated, but currently we don't
		# have a tight 'expression-element' definition which isn't
		# greedy, so we solve most cases explicitly.
		s/if \(rc != 0\)/if (rc)/go;
		s/if \(rc == 0\)/if (!rc)/go;

		# Register access - remove the unnecessary hwfn reference
		s/DIRECT_REG_WR\(${parm},${parm},${parm}\)/DIRECT_REG_WR($2, $3)/g;
		s/DIRECT_REG_RD\(${parm},${parm}\)/DIRECT_REG_RD($2)/g;

		# ecore	--> qed
		s/ecore/qed/go;
		s/ECORE/QED/go;
		s/p_dev/cdev/go;

		s/OSAL_PCI_FIND_CAPABILITY\(([^,]*)/pci_find_capability\($1->pdev/g;
		s/OSAL_PCI_FIND_EXT_CAPABILITY\(([^,]*)/pci_find_ext_capability\($1->pdev/g;
		s/OSAL_PCI_READ_CONFIG_DWORD\(([^,]*)/pci_read_config_dword\($1->pdev/g;
		s/OSAL_PCI_READ_CONFIG_WORD\(([^,]*)/pci_read_config_word\($1->pdev/g;
		s/OSAL_PCI_READ_CONFIG_BYTE\(([^,]*)/pci_read_config_byte\($1->pdev/g;
		s/OSAL_PCI_WRITE_CONFIG_WORD\(([^,]*)/pci_write_config_word\($1->pdev/g;
		s/PCICFG_DEVICE_STATUS_CONTROL_2_ATOMIC_REQ_ENABLE/PCI_EXP_DEVCTL2_LTR_EN/g;
		s/PCICFG_DEVICE_STATUS_CONTROL_2/p_hwfn->cdev->pdev->pcie_cap + PCI_EXP_DEVCTL2/g;
		s/PCICFG_VENDOR_ID_OFFSET/PCI_VENDOR_ID/g;
		s/PCICFG_DEVICE_ID_OFFSET/PCI_DEVICE_ID/g;

		s/OSAL_BAR_SIZE\(${parm},${parm}\)/pci_resource_len($1->pdev, ($2 > 0) ? 2 : 0)/g;
		#there is already an existing defination of SECTION_SIZE in
		#./arch/arm64/include/asm/pgtable.h. This fixes compilation error on arm64
		s/SECTION_SIZE/QED_SECTION_SIZE/go;

		# typedef struct name	--> struct name
		s/typedef\s+struct\s+$parm/struct $1/g;
		s/typedef\s+struct$parm;/struct $1;/g;

		# ^} name_t; --> };
		s/^\s*\}\w+_t;/\};/go;

		# enum name_t --> enum name {
		s/enum\s+(${allowed_t})_t/enum $1/g;

		# name_t --> struct name (unless it is in the allowed_t list)
		if (!(m/enum/g)) {
			s/(\w+${allowed_t})_t\s$parm/struct $1 $2/g;
		}
	};
};

sub translate_segment {
	my $was_comment = $inside_cmt;
	my $orig_line = $_[0];
	my $combined_line = $_[0];
	my $combined_ref = "";

	# The assumption is that in the ecore, no comment will start again in a
	# line that just ended a comment
	if ($_[0] =~ m/${comment_end}/g) {
		$inside_cmt = 0;
	} elsif ($_[0] =~ m/${comment_start}.*/g) {
		$inside_cmt = 1;
	}

	if ($_[0] =~ m/${pp_line}/) {
		$pp_segment = 1;
	}

	translate_line($orig_line);
	$combined_ref = $orig_line;

	# Assuming that multi comment line will not start after code but on a
	# separate line. Combine lines until the line-ending character.
	if ($inside_cmt == 0 && $was_comment == 0 && $_[0] !~ m/\/\//go && $pp_segment == 0) {
		while ($combined_line !~ m/$c_line_end\s*/) {
			my $curr_pos = tell(EFILE);
			my $newline = <EFILE> || last;
			chomp $newline;
			if ($newline =~ m/${comment_start}|\/\/|${pp_line}/go) {
				seek(EFILE, $curr_pos, 0);
				last;
			}
			$combined_line .= " " . $newline;
			translate_line($newline);
			$orig_line .= "\n" . $newline;
			$combined_ref .= " " . $newline;
#			print STDERR "Combining lines: '$combined_ref'\n";
		}
	}
	translate_line($combined_line);
	if ($combined_ref eq $combined_line) {
		# Translating each line seperately yeild the same result
		# as the combined line together
		$_[0] = $orig_line;
	} elsif ($combined_line =~ m/^\s*$/) {
		$_[0] = "";
	} else {
		# Use the combined line - save the original indent, and colapse
		# all other white-spaces to a single space.
		$combined_line =~ m/^(\s*)(\S.*)/o;
		my $indent = $1;
		my $content = $2;

		$content =~ s/\s+/ /go;
		$_[0] = $indent . $content;
	}

	# only if the current line is pre-processor and it ends with "\" the next
	# one is still pre-processor line
	if ($pp_segment != 1 || $_[0] !~ m/\\\s*$/go) {
		$pp_segment = 0;
	}
}

sub add_crc8_header_prefix {
	my $prefix = "\#if \(!defined \(_DEFINE_CRC8\) && !defined\(_MISSING_CRC8_MODULE\)\) /* QED_UPSTREAM */\n";
	print "$prefix";
}

sub add_crc_header_suffix {
	my $suffix = "\#else\n";
	$suffix   .= "\#include \"qed_compat.h\"\n";
	$suffix   .= "\#endif\n";
	print "$suffix";
}

##############################################################################
#                         Script entry point                                 #
##############################################################################
die ("Need to receive <input file>  as argument\n") unless(@ARGV > 0);
open(EFILE, "<$ARGV[0]") || die("Cannot open $ARGV[0]: $!\n");
our ($target_filename, $target_dir, $target_tmp) = fileparse($ARGV[0], qr/\.[^.]*/);
my $target_output = "";

# There are a couple of large files which we skip instead of process
if ($target_filename =~ m/init_values|reg_addr/) {
	while (<EFILE>) {
		print $_;
	}
	goto out;
}

# Process the data
NEXT: while (my $inline = <EFILE>) {
	chomp $inline;

	# Take empty lines as-is
	if ($inline =~ m/^\s*$/go) {
		$target_output .= "\n";
		goto NEXT;
	}

	# This might read a couple more lines, to allow multi-line pattern matching
	# following this, line would be translated into linux format
	translate_segment($inline);

	# Find out which includes need to be added, and populate the 'used' hashes accordingly
	if (create_include_list($inline) == 0) {
		$target_output .= "$inline\n";
	}
}

# If a header file, add an encapsulating ifdef
if ($target_filename =~ m/.*\.h/) {
	my $ifdef_name = uc $target_filename;
	$ifdef_name =~ s/\./_/go;
	print "\#ifndef _$ifdef_name\n\#define _$ifdef_name\n";
}

# Print the new file; Start with the inclusions
our %printed_globals = ();
print "\#include <linux/types.h>\n";
foreach my $include_header (sort keys %used_ig) {
	print "\#include <$include_header>\n";
	$printed_globals{$include_header} = 1;
}
foreach my $include_header (sort keys %used_igt) {
	unless ($printed_globals{$include_header}) {
		if ($include_header =~ m/linux\/crc8.h/) {
			add_crc8_header_prefix();
		}
		print "\#include <$include_header>\n";
		if ($include_header =~ m/linux\/crc8.h/) {
			add_crc_header_suffix();
		}
	}
	$printed_globals{$include_header} = 1;
}
foreach my $include_header (sort keys %used_igdt) {
	my $header_name = $includes_global_dependent_table{$include_header}{"HEADER"};
	my $header_cond = $includes_global_dependent_table{$include_header}{"LIMIT"};
	print "\#if $header_cond\n\#include <$header_name>\n\#endif\n" unless ($printed_globals{$header_name});
	$printed_globals{$header_name} = 1;
}

# Until we'll use a binary file, we need to put the local inclusions prior to the local includes
if ($target_filename =~ m/.*\.c/) {
	my $prevent_include = "";
	foreach my $struct_name (sort keys %prevent_table) {
		unless ($prevent_table{$struct_name}{"found"}) {
			my $symbol = $prevent_table{$struct_name}{"prevent_symbol"};
			$prevent_include .= "\#define __PREVENT_${symbol}__\n";
		}
	}
	print $prevent_include;
}

our %printed_locals = ();
foreach my $include_header (sort {
	#There are a couple of headers that we want to keep in order
	my $a_index = 0;
	my $b_index = 0;

	++$a_index until $il_order[$a_index] eq $a or $a_index >= $#il_order;
	++$b_index until $il_order[$b_index] eq $b or $b_index >= $#il_order;

	my $val = 0;
	if ($a_index < $b_index) {
		$val = -1;
	} elsif ($a_index > $b_index) {
		$val = 1;
	}
	if ($val != 0) {
		$val
	} else {
		$a cmp $b;
	}
} keys %used_il) {
	print "\#include \"$include_header\"\n";
	$printed_locals{$include_header} = 1;
}
foreach my $include_header (sort keys %used_ilt) {
	print "\#include \"$include_header\"\n";
	$printed_locals{$include_header} = 1;
}
foreach my $include_header (sort keys %used_ildt) {
	my $header_name = $includes_local_dependent_table{$include_header}{"HEADER"};
	my $header_cond = $includes_local_dependent_table{$include_header}{"LIMIT"};
	print "\#if $header_cond\n\#include \"$header_name\"\n\#endif\n" unless ($printed_locals{$header_name});
	$printed_locals{$header_name} = 1;
}

# Print actual contents [non-include]
print $target_output;

# If a header file, add the closure to the encapsulating ifdef
if ($target_filename =~ m/.*\.h/) {
	print "\#endif";
}


out:
close EFILE;
exit 0;
