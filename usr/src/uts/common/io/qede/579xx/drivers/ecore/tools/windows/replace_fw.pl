#!/usr/bin/perl -w

use strict;
use English;


#=======================================================================
#PROCESS ARGUMENTS
#=======================================================================
my $srcKey = "-i";
my $destKey = "-d";
my $csvKey= "-c";
my $typeKey= "-t";

#SET DEFAULT VALUES
my %args = ( $srcKey=>'none', $destKey=>'none', $csvKey => 'none', $typeKey=>'ALL');

#PARSE RECIEVED ARGUMENTS
parse_arguments();
my $srcFolder=$args{$srcKey};
my $destFolder=$args{$destKey};
my $csvFile=$args{$csvKey};
my $type=$args{$typeKey};

die "Type can only be ALL, FW_HSI, FW_TOOLS" unless ($type eq 'ALL' || $type eq 'FW_HSI' || $type eq 'FW_TOOLS');

my %types = ('FW_HSI' => 0, 'FW_TOOLS' => 0);
if ($type eq 'ALL')
{
	$types{'FW_HSI'} = 1;
	$types{'FW_TOOLS'} = 1;
}
else
{
	$types{$type} = 1;
}
#=======================================================================
#MAIN 
#=======================================================================
open (CSV,$csvFile) || die "Can't open $csvFile: $!\n";
my @lines = <CSV>;

#find columns
my %columns = ('src' => 999, 'dst' => 999, 'type' => 999, 'prefix' => 999);
my @headlines = split(/,/,$lines[0]);
for (my $i=0; $i <= $#headlines; $i++)
{
	chomp($headlines[$i]);

	if ($headlines[$i] eq 'Source')
	{
		$columns{'src'} = $i;
	}
	if ($headlines[$i] eq 'Destination')
	{
		$columns{'dst'} = $i;
	}
	if ($headlines[$i] eq 'Type')
	{
		$columns{'type'} = $i;
	}
	if ($headlines[$i] eq 'Prefix')
	{
		$columns{'prefix'} = $i;
	}
}
die "Couldn't find required columns in csv (Source, Destination, Type)" unless
(!($columns{'src'} == 999 || $columns{'dst'} == 999 || $columns{'type'} == 999 || $columns{'prefix'} == 999));

my %modes = ( 0 => 'Read only', 1 => 'Write only', 2 => 'Read / Write' );
my $totalErrorLevel = 0;

for (my $i=1; $i <= $#lines; $i++)
{
	my @fields = split(/,/,$lines[$i]);
	chomp($fields[$columns{'type'}]);
	if ($fields[$columns{'type'}] ne '') 
	{	
		chomp($fields[$columns{'type'}]);
		if ($types{$fields[$columns{'type'}]} == 1)
		{
			my $dstFile = $destFolder.'\\'.$fields[$columns{'dst'}];
			my $srcFile = $srcFolder.'\\'.$fields[$columns{'src'}];
			
			open (SRC,$srcFile) || die "Can't open $srcFile: $!\n";
			my @srcLines = <SRC>;
			close SRC;
			
			chmod 0600, $dstFile or die "Couldn't chmod $dstFile: $!\n";
			open (DST,">$dstFile") || die "Can't open $dstFile: $!\n";
			if ($fields[$columns{'prefix'}] ne '') 
			{
				$fields[$columns{'prefix'}] =~ s/\\/\//g;	#Replace '\' with '/' so that split will be easy
				my @includes = split('//n',$fields[$columns{'prefix'}]);
				foreach my $include (@includes) {print DST $include."\n";}
			}
			foreach my $srcLine (@srcLines) {print DST $srcLine;}
			close DST;
		}
	}
}

exit $totalErrorLevel;

#=======================================================================
#PARSE_ARGUMENTS
#=======================================================================
#function checks usage, and parses command line arguments.
sub parse_arguments
{
    for (my $i=0;$i<=$#ARGV;$i++)
    {
        if (defined $args{$ARGV[$i]})
        {
            $args{$ARGV[$i]}=$ARGV[$i+1];
            $i++;
        }
        else
        {
            die "Unknown Switch: $ARGV[$i]\n"; 
        }   
    }
    die "\nUSAGE: $PROGRAM_NAME -i <input folder> -d <output_folder> -c <csv file> -t <type of file to replace>\n"
    unless (!($args{$srcKey} eq 'none' || $args{$destKey} eq 'none' || $args{$csvKey} eq 'none'));
}

