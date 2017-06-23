#!/usr/bin/perl -w

our $pp_line = qr{\s*\#\s*};
our $pp_if = qr{${pp_line}if};
our $pp_ifndef = qr{${pp_line}ifndef};
our $pp_elif = qr{${pp_line}elif};
our $pp_else = qr{${pp_line}else};
our $pp_end = qr{${pp_line}endif};
our $pp_control = qr{${pp_if}|${pp_ifndef}|${pp_elif}|${pp_else}|${pp_else}|${pp_end}};
our @pp_stack = ();

our $defined = qr{(ifdef|[^\!]defined)[\s|\(]*};
our $not_defined = qr{(ifndef|\!defined)[\s|\(]*};

our $to_extract = 0;

# These are a bit confusing, since we've inherited all kind of '#ifndef SYMBOL\n#define SYMBOL (foo)' expressions from the ecore.
# And thus those we want to take would be placed under the 'throw_segments' and those that we want to remove under 'take_segments'.
our $take_segments = qr{ATTN_DESC|aligned_u64|QM_OTHER_PQS_PER_PF|MISC_REG_DRIVER_CONTROL_0|LINUX_REMOVE|REMOVE_DBG|USE_DBG_BIN_FILE};
#our $take_segments = qr{CONFIG_ECORE_ZIPPED_FW};
our $throw_segments = qr{CONFIG_ECORE_SW_CHANNEL|CONFIG_ECORE_LOCK_ALLOC|UEFI|U64_HI|U64_LO|DIRECT_REG|ECORE_CONFIG_DIRECT_HWFN|MFW};

our $take_pp = qr{${pp_line}ifdef\s*${take_segments}|${pp_line}ifndef\s*${throw_segments}|${pp_line}if\s*${take_segments}};
our $throw_pp = qr{${pp_line}ifdef\s*${throw_segments}|${pp_line}ifndef\s*${take_segments}};

##############################################################################
#                               Subroutines                                  #
##############################################################################

# Take / discard according to the 'pp_stack' and extraction.
sub process_line {
	my $string_stack = join(' ', @pp_stack);

	if ((@pp_stack == 0) || ($pp_stack[$#pp_stack] eq "INITIAL")) {
		return $to_extract;
	} elsif ((($string_stack =~ m/EXTRACT/) && ($to_extract == 0)) ||
		 (($string_stack !~ m/EXTRACT/) && ($to_extract == 1))) {
		return 1;
	} elsif ($string_stack =~ m/REM|WAS/) {
		return 1;
	}

	return 0;
}


# List of assumptions:
#   - 'Special' segements that marked to be taken are NOT nested inside segments marked for deletion.
#   - 'Special' marked segments always start with '#ifdef SYMBOL' or '#ifndef SYMBOL' [or special HSI conditions for '#if SYMBOL']
#   - __EXTRACT__LINUX__ doesn't have else/elif clauses.
#   - Ecore .h enclosing ifndefs are for symbols prefixed with __ECORE, #define of symbol on subsequent line.
#     [and qed's sources with __QED]; HSI files are an exception, as they come in various flavours.
sub process_pp_line {
	my $inline = $_[0];
	my $encolsing_ifndef = qr{__ECORE|__QED|_FW_FUNCS_DEFS_H|_INIT_DEFS_H|_DBG_FW_FUNCS_H|GTT_REG_ADDR_H|_INIT_FW_FUNCS_H|MCP_PUBLIC_H|NVM_CFG_H};

	# First, take the special cases into account
	if ($inline =~ m/\#ifndef __EXTRACT__LINUX__/) {
		# We're starting a segment that will be taken ONLY if 'to_extract'
		# is set. But we need to skip it.
		push(@pp_stack, "EXTRACT");
		return 1;
	}

	if ($inline =~ m/${pp_ifndef}\s*${encolsing_ifndef}/) {
		# We've hit a header-file surrounding ifndef; Need to extract it,
		# since it's possible this is only a part of a resulting file.
		$_[0] = <EFILE>; # Skip the following '#define'.
		push(@pp_stack, "INITIAL");
		return 1;
	}

	# Handle all regular pre-processor macros
	if ($inline =~ m/${pp_if}/) {
		if ($inline =~ m/${take_pp}/) {
			# This Segement needs to silently be taken; This line has to be discarded.
			push(@pp_stack, "ADD");
			return 1;
		} elsif ($inline =~ m/${throw_pp}/) {
			# This Segmennt needs to be thrown silently; This line has to be discarded.
			push(@pp_stack, "REM");
			return 1;
		} else {
			# This is an actual if condition, needs to be added/removed only according to nesting.
			push(@pp_stack, "SEG");
		}
	} elsif ($inline =~ m/${pp_else}|${pp_elif}/) {
		if( ($pp_stack[$#pp_stack] eq "REM") && ($inline =~ m/${pp_else}/)){
			# Else-clause of a special 'remove' segment becomes an 'add'.
			pop(@pp_stack);
			push(@pp_stack, "ADD");
			return 1;
		} elsif ($pp_stack[$#pp_stack] eq "ADD") {
			# Mark all remaining else/elif clauses of special 'add' as 'was' for removal.
			pop(@pp_stack);
			push(@pp_stack, "WAS");
			return 1;
		}
	} elsif ($inline =~ m/${pp_end}/) {
		my $last_symbol = pop(@pp_stack);
		if (!($last_symbol eq "SEG")) {
			# The closure of all special segments needs to be removed
			return 1;
		}
	}

	return process_line($inline);
}

##############################################################################
#                         Script entry point                                 #
##############################################################################
my $output_string = "";

die ("Need to receive <input file> <optional 'extract'>  as arguments\n") unless(@ARGV > 0);
open(EFILE, "<$ARGV[0]") || die("Cannot open $ARGV[0]: $!\n");

# There are a couple of large files which we skip instead of process
if (($ARGV[0] =~ m/init_values|reg_addr/) && ($ARGV[0] !~ m/gtt_reg_addr/)) {
	while (<EFILE>) {
		print $_;
	}
	goto out;
}

# Mark whether to extract; When extracting will take ONLY content under
# ifndef __EXTRACT__LINUX__
if (@ARGV > 1) {
	$to_extract = 1;
}

NEXT_LINE: while (my $inline = <EFILE>) {
	chomp $inline;
	my $to_skip = 0;

	if ($inline =~ m/${pp_control}/)  {
		$to_skip = process_pp_line($inline);
	} else {
		$to_skip = process_line($inline);
	}

	if ($to_skip == 0) {
		$output_string .= "$inline\n";
	}
}

print $output_string;

out:
close EFILE;
exit 0;
