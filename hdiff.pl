#!C:\Perl64\bin\perl.exe -w

######################################################################
#
# File      : hdiff.pl
#
# Author    : Barry Kimelman
#
# Created   : November 2, 2006
#
# Purpose   : Given two files this program generates a "diff report"
#             and then produces a highlighted color coded 2-column HTML
#             difference report.
#
# Notes     : The default color values and a number of other values can
#             be changed by optional parameters.
#
#-------------------------------------------------------------------------------
#
# Modification Log
#
# Date       Author            Description
# ---------- ----------------- -------------------------------------------------
# 11/02/2006 B. Kimelmnan      Script created.
# 11/06/2006 B. Kimelmnan      Fix "loss of synchronization" problem.
# 11/03/2011 B. Kimelmnan      Email result to a user.
# 01/28/2019 B. Kimelmnan      Remove email and make platform independant
#
######################################################################

use strict;
use warnings;
use Getopt::Std;
use File::stat;
use Sys::Hostname;
use FindBin;
use lib $FindBin::Bin;

require "list_file_info.pl";
require "comma_format.pl";

my ( %diff_commands , $doc_header , $font_family , $font_size );
my ( $host , $today , %diff_summary , %diff_count );
my ( $total_summary , $total_count , %color_codes );
my ( $filename1 , $filename2 , $trunc_limit );
my $diff_report = "";

my %options = ( "D" => 0 , "n" => 0 , "x" => 0 , "u" => 0 , "t" => 8 ,
					"N" => 0 , "w" => 100 , "H" => 10 , "X" => 0 ,
					"o" => "diff-report.htm" );

######################################################################
#
# Function  : debug_print
#
# Purpose   : Optionally print a debugging message.
#
# Inputs    : @_ - array of strings comprising message
#
# Output    : (none)
#
# Returns   : nothing
#
# Example   : debug_print("Process the files : ",join(" ",@xx),"\n");
#
# Notes     : (none)
#
######################################################################

sub debug_print
{
	if ( $options{"D"} ) {
		print STDERR join("",@_);
	} # IF

	return;
} # end of debug_print

######################################################################
#
# Function  : uuencode_data
#
# Purpose   : Generate a stream of uuencoded data representing the
#             contents of a buffer.
#
# Inputs    : $_[0] - buffer of data to be encoded
#             $_[1] - filename of uuencode header
#
# Output    : (none)
#
# Returns   : uuencoded data
#
# Example   : uuencode_data($data,"stuff.htm");
#
# Notes     : (none)
#
######################################################################

sub uuencode_data
{
    my ( $data , $filename ) = @_;
    my ( $uuencoded_data, $line , $buffer , $length );
    
# Process the file
	$uuencoded_data = "begin 0644 $filename\n";

	$buffer = $data;
	while ( 0 < length $buffer ) {
		$length = length $buffer;
		if ( $length >= 45 ) {
			$line = substr($buffer,0,45);
			$buffer = substr($buffer,45);
		} # IF
		else {
			$line = $buffer;
			$buffer = "";
		} # ELSE
		$uuencoded_data .= pack("u", $line);
	} # WHILE
	$uuencoded_data .= "\nend\n";

	return($uuencoded_data);
} # end of uuencode_data

######################################################################
#
# Function  : count_lines_in_file
#
# Purpose   : Count the number of lines in a file.
#
# Inputs    : $_[0] - name of file
#
# Output    : (none)
#
# Returns   : number of lines
#
# Example   : $count = count_lines_in_file($filename);
#
# Notes     : (none)
#
######################################################################

sub count_lines_in_file
{
	my ( $filename ) = @_;
	my ( @lines );

	unless ( open(INPUT,"<$filename") ) {
		warn("open failed for \"$filename\" : $!\n");
		return 0;
	} # UNLESS

	@lines = <INPUT>;
	close INPUT;

	return scalar @lines;
} # end of count_lines_in_file

######################################################################
#
# Function  : pad_string
#
# Purpose   : Pad a string
#
# Inputs    : $_[0] - string to be padded
#             $_[1] - padding characters
#             $_[2] - amount of padding
#
# Output    : (none)
#
# Returns   : padded string
#
# Example   : $info = pad_string($string,$pad,$padlen);
#
# Notes     : (none)
#
######################################################################

sub pad_string
{
	my ( $string , $pad , $padlen ) = @_;
	my ( $padding );

	$padding = $pad x $padlen;
	return $string . $padding;
} # end of pad_string

######################################################################
#
# Function  : build_file_info
#
# Purpose   : Build a string containing file information
#
# Inputs    : $_[0] - name of file
#
# Output    : (none)
#
# Returns   : file information
#
# Example   : $info = build_file_info($path);
#
# Notes     : (none)
#
######################################################################

sub build_file_info
{
	my ( $path ) = @_;
	my ( $filestat , $modtime , @user , $login , $gcos , $owner , $info , $kb );
	my ( $num_kb , @headers , $maxlen , @padlen , $count );

	$filestat = stat($path);
	unless ( defined $filestat ) {
		die("stat() failed for \"$path\" : $!\n");
	} # UNLESS
	$modtime = localtime($filestat->mtime);

	if ( $^O =~ m/MSWin/ ) {
		$owner = $ENV{'username'};
	} # IF
	else {
		@user = getpwuid $filestat->uid;
		$login = $user[0];
		$gcos = $user[6];
		$owner = (defined $gcos) ? $gcos : $login;
	} # ELSE

	@headers = ( "owner" , "filesize" , "number of lines" , "last modified" );
	$maxlen = (sort { $b <=> $a} map { length $_ } @headers)[0];
	$maxlen += 1;
	@padlen = map { $maxlen - length $_ } @headers;
	$count = count_lines_in_file($path);
	$info = pad_string($headers[0],"&nbsp;",$padlen[0]) . ": $owner<BR>";

	$kb = 1 << 10;
	$num_kb = $filestat->size / $kb;
	$info .= pad_string($headers[1],"&nbsp;",$padlen[1]) . ": " . comma_format($filestat->size) . sprintf "(%.2f KB)",$num_kb;

	$info .= "<BR>" . pad_string($headers[2],"&nbsp;",$padlen[2]) . ": $count";
	$info .= "<BR>" . pad_string($headers[3],"&nbsp;",$padlen[3]) . ": $modtime";

	return $info;
} # end of build_file_info

######################################################################
#
# Function  : expand_tabs
#
# Purpose   : Expand tabs to spaces.
#
# Inputs    : $_[0] - record to be expanded
#             $_[1] - tab width
#
# Output    : (none)
#
# Returns   : expanded record
#
# Example   : $expanded = expand_tabs($record,8);
#
# Notes     : (none)
#
######################################################################

sub expand_tabs
{
	my ( $record , $tab_width ) = @_;
	my ( $location );

	while ($record =~ m/\t/g) {
		$location = pos($record) - 1;
		substr ($record,$location,1) = ' ' x ($tab_width - ($location % $tab_width));
	} # WHILE

	return $record;
} # end of expand_tabs

######################################################################
#
# Function  : read_file_contents
#
# Purpose   : Read the contents of a file.
#
# Inputs    : $_[0] - filename
#             $_[1] - reference to array to receive file contents
#
# Output    : appropriate diagnostics
#
# Returns   : (nothing)
#
# Example   : read_file_contents($filename,\@records);
#
# Notes     : The tabs in the input records are expanded into spaces.
#
######################################################################

sub read_file_contents
{
	my ( $filename , $ref_records ) = @_;
	my ( $buffer );

	@$ref_records = ();
	unless ( open(INPUT,"<$filename") ) {
		die("Can't open \"$filename\" : $!\n");
	} # UNLESS

	while ( $buffer = <INPUT> ) {
		chomp $buffer;
		$buffer = expand_tabs($buffer,$options{"t"});
		push @$ref_records,$buffer;
	} # WHILE
	close INPUT;

	return;
} # end of read_file_contents

######################################################################
#
# Function  : eat_lines
#
# Purpose   : Extract lines from the beginning of an array.
#
# Inputs    : $_[0] - reference to array of lines
#             $_[1] - number of lines to be extracted
#             $_[2] - reference to array to receive extracted lines
#             $_[3] - debugging comment
#
# Output    : (none)
#
# Returns   : (nothing)
#
# Example   : eat_lines(\@records,$num_lines,\@extracted,"help");
#
# Notes     : (none)
#
######################################################################

sub eat_lines
{
	my ( $ref_lines , $num_lines , $ref_extracted , $comment ) = @_;
	my ( $count , $line );

	$count = scalar @$ref_lines;
	debug_print("eat_lines($comment) : num_lines = $num_lines , count = $count\n");
	@$ref_extracted = ();
	for ( $count = 0 ; $count < $num_lines ; ++$count ) {
		$line = shift @$ref_lines;
		push @$ref_extracted,$line;
	} # FOR

	return;
} # end of eat_lines

######################################################################
#
# Function  : eat_lines_until
#
# Purpose   : Extract lines from the beginning of an array.
#
# Inputs    : $_[0] - reference to array of lines
#             $_[1] - reference to array counter
#             $_[2] - stop eating when count reaches this limit
#             $_[3] - reference to array to receive extracted lines
#             $_[4] - debugging comment
#
# Output    : (none)
#
# Returns   : (nothing)
#
# Example   : eat_lines_until(\@records,\$counter,$limit,\@extracted,"help");
#
# Notes     : (none)
#
######################################################################

sub eat_lines_until
{
	my ( $ref_lines , $ref_counter , $limit , $ref_extracted , $comment ) = @_;
	my ( $count , $line , $num_eaten );

	$count = scalar @$ref_lines;
	debug_print("\neat_lines_until($comment) : limit = $limit , counter = $$ref_counter\n");
	@$ref_extracted = ();
	$num_eaten = 0;
	for ( ; 1+$$ref_counter < $limit ; ++$$ref_counter ) {
		$num_eaten += 1;
		$line = shift @$ref_lines;
		push @$ref_extracted,$line;
	} # FOR
	debug_print("eat_lines_until($comment) : num_eaten = $num_eaten\n");

	return;
} # end of eat_lines_until

######################################################################
#
# Function  : add_to_lines_array
#
# Purpose   : Add lines to "lines" array.
#
# Inputs    : $_[0] - prefix to be added before lines
# Inputs    : $_[1] - reference to array of lines to be added
#             $_[2] - reference to line number counter
#             $_[3] - reference to array to receive lines
#             $_[4] - if not empty then a HTML color code
#             $_[5] - debugging comment
#
# Output    : (none)
#
# Returns   : (nothing)
#
# Example   : add_to_lines_array("",\@lines,\$line_number,\@old_lines,"","help");
#
# Notes     : The lines are added to the "lines" array as a single block
#             of data.
#
######################################################################

sub add_to_lines_array
{
	my ( $prefix , $ref_lines , $ref_line_number , $ref_array , $html_color_code , $comment ) = @_;
	my ( $count , $line , $num_lines , $line_number_str , $color_info1 , $color_info2 );
	my ( $line_data , $length , $spaces , $line_segment );

	$count = scalar @$ref_lines;
	if ( $count < 1 ) {
		push @$ref_array," ";
		return;
	} # IF

	debug_print("add_to_lines_array(lines = $$ref_line_number/$count [$html_color_code] $comment)\n");
	if ( 1 > length $html_color_code ) {
		$color_info1 = "";
		$color_info2 = "";
	} # IF
	else {
		$color_info1 = "<SPAN style=\"background-color:${html_color_code};\">";
		$color_info2 = "</SPAN>";
	} # ELSE

	$line_data = "";
	$num_lines = scalar @$ref_lines;
	$line_number_str = "";
	for ( $count = 0 ; $count < $num_lines ; ++$count , ++$$ref_line_number ) {

# If requested generate line number
		if ( $options{"n"} ) {
			$line_number_str = sprintf "%d",$$ref_line_number;
			$length = length $line_number_str;
			$spaces = " " x (6 - $length);
			$line_number_str = $line_number_str . $spaces;
		} # IF
		if ( $options{"N"} ) {
			$line_number_str = sprintf "[%d]",$$ref_line_number;
			$length = length $line_number_str;
			$spaces = " " x (6 - $length);
			$line_number_str = $line_number_str . $spaces;
		} # IF

		$line_segment = $$ref_lines[$count];
		unless ( defined $line_segment ) {
			$line_segment = "";
		} # UNLESS

# If requested truncate lengthy lines
		if ( exists $options{"T"} ) {
			if ( $options{"T"} < length $line_segment ) {
				$line_segment = substr $line_segment,0,$trunc_limit;
			} # IF
		} # IF

# If requested attempt to clean up HTML tags
		if ( $options{"X"} ) {
			$line_segment =~ s/</\&lt;/g;
		} # IF

		$line_data .= $line_number_str . $line_segment;
		if ( 1+$count < $num_lines ) {
			$line_data .= "\n";
		} # IF
	} # FOR
	if ( 0 < length $prefix ) {
		$line_data = "<center><span class=\"titleinfo\">== $prefix ==</span></center>\n" .
						$color_info1 . $line_data . $color_info2;
	} # IF
	else {
		$line_data = $color_info1 . $line_data . $color_info2;
	} # ELSE
	push @$ref_array,$line_data;

	return;
} # end of add_to_lines_array

######################################################################
#
# Function  : gen_html_report
#
# Purpose   : Read the contents of a file.
#
# Inputs    : $_[0] - 1st filename
#             $_[1] - reference to array to containing file1 records
#             $_[2] - 2nd filename
#             $_[3] - reference to array to containing file2 records
#             $_[4] - reference to array to containing difference records
#
# Output    : appropriate diagnostics
#
# Returns   : number of lines
#
# Example   : $num_lines = gen_html_report($file1,\@lines1,$file2,\@lines2,
#                                   \@diff_lines);
#
# Notes     : (none)
#
######################################################################

sub gen_html_report
{
	my ( $file1 , $ref_records1 , $file2 , $ref_records2 , $ref_diff ) = @_;
	my ( $line1 , $line2 , $status , $file1_rectotal , $file2_rectotal );
	my ( $num_lines1 , $num_lines2 , $num_diff_lines , $diff_line , $errmsg );
	my ( $num1 , $num2 , $num3 , $num4 , $operation , $cmd , $first_old_line );
	my ( $num_source_lines , $num_target_lines , $num_diff_operation_lines );
	my ( $diff_data , $count , @old_lines , @new_lines , @temp1_lines );
	my ( @temp2_lines , $num_lines , @html_data , $classname );
	my ( $line_number_str , $first_new_line , $fetch_limit , $lines_limit );
	my ( $num_old_lines , $num_new_lines , $num_affected_lines , $prefix );
	my ( $command , $encoded );

	$diff_report = $doc_header . "\n";
	$diff_report .= "$today on $host<BR><BR>\n";

# Include UNIX diff report only when requested by user

	if ( $options{"x"} ) {
		@temp1_lines = @$ref_diff;
		chomp @temp1_lines;
		$diff_report .= "<textarea rows=\"" . $options{"H"} . "\" cols=\"" .
					$options{"w"} .  "\" style=\"border: green double 5px;\">\n";
		foreach $diff_data ( @temp1_lines ) {
			$diff_data = expand_tabs($diff_data,$options{"t"});
			$diff_report .= "$diff_data\n";
		} # FOREACH
		$diff_report .= "</textarea>\n<BR>\n";
	} # IF

# Display a color code chart

	$diff_report .= "<BR>Color Legend:<BR>\n";
	$diff_report .= "<TABLE border=\"0\" CELLSPACING=\"2\" CELLPADDING=\"2\">\n";
	$diff_report .= "<TR><TD style=\"background-color:" . $color_codes{"d"} . ";\">" .
					"Delete Record</TD></TR>\n";
	$diff_report .= "<TR><TD style=\"background-color:" . $color_codes{"c"} . ";\">" .
					"Change Record</TD></TR>\n";
	$diff_report .= "<TR><TD style=\"background-color:" . $color_codes{"a"} . ";\">" .
					"Add Record</TD></TR>\n";
	$diff_report .= "</TABLE><BR>\n";

	if ( exists $options{"T"} ) {
		$diff_report .= "Note : This report was generated with a truncation limit of " .
					$options{"T"} . " characters<BR><BR>\n";
	} # IF

# Display the start of the diff table

	$diff_report .= "<TABLE border=\"1\" CELLSPACING=\"0\" CELLPADDING=\"2\">\n";
	$diff_report .= "<THEAD><TR class=\"aquamarineback\">" .
				"<TH>Original Code<BR>$filename1</TH><TH>New Code<BR>$filename2</TH></THEAD>\n";
	$diff_report .= "<TBODY>\n";

# Initialize the variables used during the construction of the visual diff report

	$num_lines1 = scalar @$ref_records1;
	$num_lines2 = scalar @$ref_records2;
	$num_diff_lines = scalar @$ref_diff;
	@old_lines = ();
	@new_lines = ();
	$file1_rectotal = 0;
	$file2_rectotal = 0;

# Process the UNIX diff report one operation at a time

	while ( 0 < @$ref_diff ) {
		$diff_line = shift @$ref_diff;
		chomp $diff_line;
		if ( $diff_line =~ m/^(\d+)([adc])(\d+)$/ ) {
			$num1 = $1;
			$num2 = $num1;
			$operation = $2;
			$num3 = $3;
			$num4 = $num3;
		} elsif ( $diff_line =~ m/^(\d+),(\d+)([adc])(\d+)$/ ) {
			$num1 = $1;
			$num2 = $2;
			$operation = $3;
			$num3 = $4;
			$num4 = $num3;
		} elsif ( $diff_line =~ m/^(\d+)([adc])(\d+),(\d+)$/ ) {
			$num1 = $1;
			$operation = $2;
			$num2 = $num1;
			$num3 = $3;
			$num4 = $4;
		} elsif ( $diff_line =~ m/^(\d+),(\d+)([adc])(\d+),(\d+)$/ ) {
			$num1 = $1;
			$num2 = $2;
			$operation = $3;
			$num3 = $4;
			$num4 = $5;
		} else {
			die("Bad diff line : $diff_line\n");
		} # ELSE
		unless ( exists $diff_commands{$operation} ) {
			die("Bad diff operation : $diff_line\n");
		} # UNLESS

# Perform some calculations based on the type of diff operation

		$cmd = $diff_commands{$operation};
		debug_print("\n$num1,$num2 $cmd $num3,$num4\n");
		$num_source_lines = ($num2 - $num1) + 1;
		$num_target_lines = ($num4 - $num3) + 1;
		$num_affected_lines = $operation eq "a" ? $num_target_lines : $num_source_lines;
		$total_summary += $num_affected_lines;
		$total_count += 1;
		if ( exists $diff_summary{$operation} ) {
			$diff_summary{$operation} += $num_affected_lines;
			$diff_count{$operation} += 1;
		} # IF
		else {
			$diff_summary{$operation} = $num_affected_lines;
			$diff_count{$operation} = 1;
		} # ELSE

		$first_old_line = $file1_rectotal + 1;
		$first_new_line = $file2_rectotal + 1;

# Process the lines from the "original" file that correspond to all
# the lines since the last diff operation

		eat_lines_until($ref_records1,\$file1_rectotal,$num1,\@temp1_lines,"$file1 pre-block");
		unless ( $options{"u"} ) {
			add_to_lines_array("",\@temp1_lines,\$first_old_line,\@old_lines,"","file1 pre-block");
		} # UNLESS
		else {
			$first_old_line += scalar @temp1_lines;
		} # ELSE

# Process the lines from the "modified" file that correspond to all
# the lines since the last diff operation

		$fetch_limit = $num3;
		if ( $operation eq "d" ) {
			$fetch_limit += 1;
		} # IF
		eat_lines_until($ref_records2,\$file2_rectotal,$fetch_limit,\@temp2_lines,"$file2 pre-block");
		unless ( $options{"u"} ) {
			add_to_lines_array("",\@temp2_lines,\$first_new_line,\@new_lines,"","file2 pre-block");
		} # UNLESS
		else {
			$first_new_line += scalar @temp2_lines;
		} # ELSE

# Process the lines from the "original" file that correspond to the lines that
# are affected by the current diff operation

		eat_lines($ref_records1,$num_source_lines,\@temp1_lines,"$file1 $cmd data");
		$file1_rectotal = $num2;
		$classname = $color_codes{$operation};
		$classname = $operation eq "a" ? "" : $color_codes{$operation};
###		$prefix = ($operation ne "a") ? $cmd : "";
		$prefix = $cmd;
		add_to_lines_array("$prefix",\@temp1_lines,\$first_old_line,\@old_lines,$classname,"file1 $cmd data");
###		add_to_lines_array("",\@temp1_lines,\$first_old_line,\@old_lines,$classname,"file1 $cmd data");
# Process the lines from the "modified" file that correspond to the lines that
# are affected by the current diff operation

		if ( $operation ne "d" ) {
			eat_lines($ref_records2,$num_target_lines,\@temp2_lines,"$file2 $cmd data");
			$file2_rectotal = $num4;
			$classname = $color_codes{$operation};
			$prefix = ($operation ne "d") ? $cmd : "";
			add_to_lines_array("",\@temp2_lines,\$first_new_line,\@new_lines,$classname,"file2 $cmd data");
		} # IF
		else {  # If a delete operation include a blank line in the report
			push @new_lines," ";
		} # ELSE

# Process the lines in the UNIX diff report that correspond to the current
# diff operation

		if ( $operation eq "c" ) {
			$num_diff_operation_lines = $num_target_lines + $num_source_lines + 1;
		} elsif ( $operation eq "d" ) {
			$num_diff_operation_lines = $num_source_lines;
		} else {  # must be an "a"
			$num_diff_operation_lines = $num_target_lines;
		} # ELSE
		if ( $num_diff_operation_lines > @$ref_diff ) {
			die("Premature EOF on diff file\n");
		} # IF
		for ( $count = 0 ; $count < $num_diff_operation_lines ; ++$count ) {
			$diff_data = shift @$ref_diff;
		} # FOR

	} # WHILE loop over difference operations

# Process all remaining lines in the "original" and "modified" files

	unless ( $options{"u"} ) {
		$count = scalar @$ref_records1;
		debug_print("\n$count remaining $file1 records\n");
		if ( $count > 0 ) {
			add_to_lines_array("",$ref_records1,\$first_old_line,\@old_lines,"","file1 leftovers");
		} # IF

		$count = scalar @$ref_records2;
		debug_print("$count remaining $file2 records\n");
		if ( $count > 0 ) {
			add_to_lines_array("",$ref_records2,\$first_new_line,\@new_lines,"","file2 leftovers");
		} # IF
	} # UNLESS

# Now add the generated visual diff report lines to the final report

	$num_old_lines = scalar @old_lines;
	$num_new_lines = scalar @new_lines;
	$lines_limit = ($num_old_lines > $num_new_lines) ? $num_old_lines : $num_new_lines;

	for ( $count = 0 ; $count < $lines_limit ; ++$count ) {
		$diff_report .= "<TR>";
		if ( defined $old_lines[$count] ) {
			$diff_report .= "<TD VALIGN=\"top\"><PRE>$old_lines[$count]</PRE></TD>\n";
		} # IF
		else {
			$diff_report .= "<TD VALIGN=\"top\">&nbsp;</TD>\n";
		} # ELSE
		if ( defined $new_lines[$count] ) {
			$diff_report .= "<TD VALIGN=\"top\"><PRE>$new_lines[$count]</PRE></TD>\n";
		} # IF
		else {
			$diff_report .= "<TD VALIGN=\"top\">&nbsp;</TD>\n";
		} # ELSE
		$diff_report .= "</TR>\n";
	} # FOR
	$diff_report .= "</TBODY>\n";
	$diff_report .= "</TABLE>\n";

# Print a summary of all the diff operations

	$diff_report .= "<BR><TABLE border=\"0\" CELLSPACING=\"0\" CELLPADDING=\"2\">\n";
	$diff_report .= "<TR><TH class=\"underline\">Operation</TH><TH WIDTH=\"20\">&nbsp;</TH><TH class=\"underline\">Count</TH>" .
				"<TH WIDTH=\"20\">&nbsp;</TH><TH class=\"underline\">Number of affected lines</TH>\n";
	foreach $operation ( keys %diff_count ) {
		$diff_report .= "<TR><TD>$diff_commands{$operation}</TD><TD>&nbsp;</TD><TD>$diff_count{$operation}</TD>" .
				"<TD>&nbsp;</TD><TD>$diff_summary{$operation}</TD></TR>\n";
	} # FOREACH
	$diff_report .= "<TR class=\"greyback\"><TD>Total</TD><TD>&nbsp;</TD><TD>$total_count</TD>" .
			"<TD>&nbsp;</TD><TD>$total_summary</TD></TR>\n";
	$diff_report .= "</TABLE>\n";

	$diff_report .= "</BODY>\n";
	$diff_report .= "</HTML>\n";
	unless ( open(REPORT,">$options{'o'}") ) {
		die("open failed for '$options{'o'}' : $!\n");
	} # UNLESS
	print REPORT "$diff_report";
	close REPORT;

	return;
} # end of gen_html_report

######################################################################
#
# Function  : usage
#
# Purpose   : Print a program usage message.
#
# Inputs    : (none)
#
# Output    : program usage message
#
# Returns   : nothing
#
# Example   : usage();
#
# Notes     : (none)
#
######################################################################

sub usage
{

	warn("Usage : $0 [-xDnuH] [-d delete_color_code] [-c change_color_code] ",
				"[-a add_color_code]\t\n[-t tab_width] [-w diff_window_width] ",
				"[-h diff_window_height] [-s font_size] [-f font_family] ",
				"[-T truncation_size] [-e email_id] ",
				"file1 file2\n");
	return;
} # end of usage

######################################################################
#
# Function  : MAIN
#
# Purpose   : program entry point
#
# Inputs    : $ARGV[0] - 1st filename
#             $ARGV[1] - 2nd filename
#             $ARGV[2] - file containing difference report
#
# Output    : (none)
#
# Returns   : 0 --> success , non-zero --> failure
#
# Example   : hdiff.pl -xnuH file1 file2 > diff_report.htm
#
# Notes     : (none)
#
######################################################################

MAIN:
{
	my ( $status , @lines1 , @lines2 , @diff_lines , $cmd , %codes , $code );
	my ( $count , $header , $info1 , $info2 );

	$count = scalar @ARGV;
	if ( $^O =~ m/MSWin/ ) {
		$options{'e'} = $ENV{'USERNAME'};
	} # IF
	else {
		$options{'e'} = $ENV{'LOGNAME'};
	} # ELSE
	$status = getopts("uxDNnd:c:a:s:f:t:w:h:T:HhXe:",\%options);
	if ( $options{"h"} ) {
		if ( $^O =~ m/MSWin/ ) {
# Windows stuff goes here
			system("pod2text $0 | more");
		} # IF
		else {
# Non-Windows stuff (i.e. UNIX) goes here
			system("pod2man $0 | nroff -man | less -M");
		} # ELSE
		exit 0;
	} # IF

	unless ( $status  && $count == 2 ) {
		usage();
		exit 1;
	} # UNLESS
	if ( exists $options{"T"} ) {
		if ( $options{"T"} =~ m/\D/ ) {
			die("Error : non numeric characters specified for -T option\n");
		} # IF
		$trunc_limit = $options{"T"} - 1;
	} # IF
	if ( $options{"n"} && $options{"N"} ) {
		die("Options 'n' and 'N' are mutually exclusive.\n");
	} # IF

	%diff_commands = ( "a" => "add" , "d" => "delete" , "c" => "change" );
	%color_codes = ( "a" => "#FF8C00"  , # default color for append is orange
					"c" => "#FFFF00" ,   # default color for change is yellow
					"d" => "#C0C0C0"     # default color for delete is grey
					) ;
	if ( exists $options{"c"} ) {
		unless ( $options{"c"} =~ m/^[0-9a-fA-F]{6}$/ ) {
			die("Invalid color code for change records\n");
		} # UNLESS
		$color_codes{"c"} = "#" . uc $options{"c"};
	} # IF
	if ( exists $options{"d"} ) {
		unless ( $options{"d"} =~ m/^[0-9a-fA-F]{6}$/ ) {
			die("Invalid color code for delete records\n");
		} # UNLESS
		$color_codes{"d"} = "#" . uc $options{"d"};
	} # IF
	if ( exists $options{"a"} ) {
		unless ( $options{"a"} =~ m/^[0-9a-fA-F]{6}$/ ) {
			die("Invalid color code for add records\n");
		} # UNLESS
		$color_codes{"a"} = "#" . uc $options{"a"};
	} # IF

	%codes = map { $_ , 1 } values %color_codes;
	if ( 3 > keys %codes ) {
		warn("You have requested duplicate color code values\n");
		foreach $code ( keys %color_codes ) {
			warn("\t",$diff_commands{$code}," => $color_codes{$code}\n");
		} # FOREACH
		die("Please try again.\n");
	} # IF

	$host = hostname;
	$today = scalar localtime;

	$font_size = (exists $options{"s"}) ? $options{"s"} : "14px";
	$font_family = (exists $options{"f"}) ? $options{"f"} : "Courier New, Courier, Arial";

	$filename1 = $ARGV[0];
	$filename2 = $ARGV[1];

	read_file_contents($filename1,\@lines1);
	read_file_contents($filename2,\@lines2);
	$cmd = "diff $filename1 $filename2";
	@diff_lines = `$cmd`;
	$status = $?;
	if ( 1 > @diff_lines ) {
		die("'$cmd' produced no output\n");
	} # IF

	%diff_summary = ();
	%diff_count = ();
	$total_summary = 0;
	$total_count = 0;

##	$header = "<H2>Difference between $filename1 and $filename2</H2>";
	$info1 = build_file_info($filename1);
	$info2 = build_file_info($filename2);

	$header = <<ENDHEADER;
<TABLE border="0" cellpadding="5" cellspacing="0">
<TR>
<TD><span class="largetext">Difference between</span></TD>
<TD><span class="largetext"><A HREF=\"javascript:void()\" class=\"info\">$filename1<span>$info1</span></A></TD>
</TR>
<TR>
<TD><span class="largetext">and</span></TD>
<TD><span class="largetext"><A HREF=\"javascript:void()\" class=\"info\">$filename2<span>$info2</span></A></TD>
</TR>
</TABLE>
ENDHEADER

	$doc_header = <<ENDDOCTYPE;
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN"
"http://www.w3.org/TR/html4/strict.dtd">
<HTML>
<HEAD>
<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
<TITLE>Difference between $filename1 and $filename2</TITLE>
<style type="text/css" media="print,screen" >
thead {
	display:table-header-group;
}
tbody {
	display:table-row-group;
}
.aquamarineback { background-color: #0fffff; }
.greyback { background-color: #c0c0c0; font-weight: bold; }
.titleinfo { font-weight: bold; font-style: italic; font-size: 16px; }
body { font-family: ${font_family}; font-size: ${font_size}; }
.underline { text-decoration: underline; }
.largetext { font-size: 150%; font-weight: bold; }
a.info
{
position:relative; /*this is the key*/
z-index:24;
background-color:#ccc;
color:blue;
text-decoration:underline;
}

a.info:hover
{
z-index:25;
background-color:#ff0
}

a.info span
{
display: none
}

a.info:hover span
{
/*the span will display just on :hover state*/
display:block;
position:absolute;
top:2em; left:1em; width:26em;
border:1px solid #5C3317;
background-color:#AF886C;
color:#000;
text-align: left;
text-decoration:none;
font-size: 75%;
}
</style>
</HEAD>
<BODY>
$header
ENDDOCTYPE

	gen_html_report($filename1,\@lines1,$filename2,\@lines2,\@diff_lines);
	list_file_info_full($options{'o'},{ 'o' => 1 , 'g' => 1 , 'k' => 0 });

	exit 0;
} # end of MAIN
__END__
=head1 NAME

hdiff.pl

=head1 SYNOPSIS

hdiff.pl [-xDnuH] [-d delete_color_code] [-c change_color_code]
[-a add_color_code]\t\n[-t tab_width] [-w diff_window_width]
[-h diff_window_height] [-s font_size] [-f font_family]
[-T truncation_size] [-e email_id] file1 file2

=head1 DESCRIPTION

This perl script will generate a side-by-side difference report of 2 files in HTML format.
Note that the color codes used in the color code options must be 6 digit hexadecimal
numbers. Note that when you hover the mouse over the 2 filenames extra information is
displayed.

=head1 OPTIONS

  -D - activate debug mode
  -t tab_width - width of tabstop spacing
  -T truncation_size - text line truncation size
  -s font_size - font size for displayed text
  -f font_family - font family for displayed text
  -w diff_window_width - width of window displaying output from UNIX diff command
  -h diff_window_height - height of window displaying output from UNIX diff command
  -d delete_color_code - used to specify color code for "delete" blocks
  -c change_color_code - used to specify color code for "change" blocks
  -a add_color_code - used to specify color code for "add" blocks
  -x - show the actual output from the UNIX "diff" command
  -n - display text lines with line numbers
  -u - only show the updates
  -X - clean up lines containing HTML tags
  -e email_id - the email id (minus the domain name) , the default is the login id
  -h - display help summary

=head1 PARAMETERS

  file1 - name of 1st file
  file2 - name of 2nd file

=head1 EXAMPLES

hdiff.pl -xnuH oldfile.sc newerfile.sc > diff.htm

Use the following to email the file to yourself:

hdiff.pl -e <adid> <config1.txt> <config2.txt>

=head1 EXIT STATUS

 0 - successful completion
 nonzero - an error occurred

=head1 AUTHOR

Barry Kimelman

=cut
