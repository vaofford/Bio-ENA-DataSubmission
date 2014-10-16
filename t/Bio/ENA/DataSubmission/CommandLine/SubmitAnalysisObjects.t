#!/usr/bin/env perl
BEGIN { unshift( @INC, './lib' ) }

BEGIN {
    use Test::MockObject;
    use Test::Most;
    use Test::Output;
    use Test::Exception;

    my $ftp = Test::MockObject->new();
    $ftp->fake_module( 'Bio::ENA::DataSubmission::FTP', test => sub { 1 } );
    $ftp->fake_new('Bio::ENA::DataSubmission::FTP');
    $ftp->mock( 'upload', sub { 1 } );

    my $data_submission = Test::MockObject->new();
    $data_submission->fake_module( 'Bio::ENA::DataSubmission', test => sub { 1 } );
    $data_submission->fake_new('Bio::ENA::DataSubmission');
    $data_submission->mock( 'submit', sub { 1 } );
}

use Moose;
use File::Compare;
use File::Copy;
use File::Path qw( remove_tree);
use Cwd;
use File::Temp;
use Data::Dumper;
use File::Slurp;

my $temp_directory_obj = File::Temp->newdir( DIR => getcwd, CLEANUP => 1   );
my $tmp = $temp_directory_obj->dirname();

use_ok('Bio::ENA::DataSubmission::CommandLine::SubmitAnalysisObjects');

my ( $obj, @args );

#----------------------#
# test illegal options #
#----------------------#

@args = ( '-c', 't/data/test_ena_data_submission.conf' );
throws_ok { Bio::ENA::DataSubmission::CommandLine::SubmitAnalysisObjects->new( args => \@args ) } 'Bio::ENA::DataSubmission::Exception::InvalidInput', 'dies without arguments';

@args = ( '-o', 't/data/fakefile.txt', '-c', 't/data/test_ena_data_submission.conf' );
throws_ok { Bio::ENA::DataSubmission::CommandLine::SubmitAnalysisObjects->new( args => \@args ) } 'Bio::ENA::DataSubmission::Exception::InvalidInput', 'dies without file input';

@args = ( '-f', 'not/a/file', '-c', 't/data/test_ena_data_submission.conf' );
throws_ok { Bio::ENA::DataSubmission::CommandLine::SubmitAnalysisObjects->new( args => \@args ) } 'Bio::ENA::DataSubmission::Exception::FileNotFound', 'dies with invalid input file path';

@args = ( '-f', 't/data/compare_manifest.xls', '-o', 'not/a/file', '-c', 't/data/test_ena_data_submission.conf' );
throws_ok { Bio::ENA::DataSubmission::CommandLine::SubmitAnalysisObjects->new( args => \@args ) } 'Bio::ENA::DataSubmission::Exception::CannotWriteFile', 'dies with invalid output file path';

#--------------#
# test methods #
#--------------#

@args = ( '-f', 't/data/analysis_submission_manifest.xls', '-o', "$tmp/analysis_submission_report.xls", '-c', 't/data/test_ena_data_submission.conf' );
$obj = Bio::ENA::DataSubmission::CommandLine::SubmitAnalysisObjects->new(
    args         => \@args,
    _checksum    => 'im_a_checksum',
    _output_dest => $tmp,
);

# sample XML updating
ok( $obj->_update_analysis_xml,                         'XML update successful' );
ok( -e $obj->_output_dest . "/analysis_2014-01-01.xml", 'XML exists analysis_2014-01-01.xml' );
ok( compare( 't/data/analysis_updated.xml', $obj->_output_dest . "/analysis_2014-01-01.xml" ) == 0, 'Updated XML file correct' );

# test release date comparison
ok( !$obj->_later_than_today('2000-01-01'), 'Date comparison correct' );
ok( $obj->_later_than_today('2050-01-01'),  'Date comparison correct' );
remove_tree( $obj->_output_dest );

@args = ( '-f', 't/data/analysis_submission_manifest.xls', '-o', "$tmp/analysis_submission_report.xls", '-c', 't/data/test_ena_data_submission.conf' );

# submission XML generation
# test with different release dates!
$obj = Bio::ENA::DataSubmission::CommandLine::SubmitAnalysisObjects->new(
    args          => \@args,
    _current_user => 'testuser',
    _timestamp    => 'testtime',
    _output_dest  => $tmp,
    _no_upload    => 1,
    _no_validate  => 1
);
ok( $obj->_generate_submissions(),                        'Submission XMLs generated successfully' );
ok( -e $obj->_output_dest . "/submission_2014-01-01.xml", 'XML exists submission_2014-01-01.xml' );
ok( -e $obj->_output_dest . "/submission_2050-01-01.xml", 'XML exists submission_2050-01-01.xml' );
ok( compare( 't/data/analysis_submission1.xml', $obj->_output_dest . "/submission_2014-01-01.xml" ) == 0, 'Submission XML correct' );
ok( compare( 't/data/analysis_submission2.xml', $obj->_output_dest . "/submission_2050-01-01.xml" ) == 0, 'Submission XML correct' );

# test full run
# Mock out FTP

@args = ( '-f', 't/data/analysis_submission_manifest.xls', '-o', "$tmp/analysis_submission_report.xls", '-c', 't/data/test_ena_data_submission.conf' );
ok( $obj = Bio::ENA::DataSubmission::CommandLine::SubmitAnalysisObjects->new( args => \@args ), 'Initialize object for valid run' );
copy('t/data/success_receipt.xml', $obj->_output_dest.'/receipt_2050-01-01.xml');
copy('t/data/success_receipt.xml', $obj->_output_dest.'/receipt_2014-01-01.xml');

ok( $obj->run(), 'Submission XMLs uploaded with external interfaces mocked out' );
ok(-e $tmp."/analysis_submission_report.xls", 'report on submission created');

is_deeply( 
	diff_xls('t/data/success_analysis_submission_report.xls', $tmp."/analysis_submission_report.xls" ),
	'Report xls created properly'
);


# Rename file if its just contigs.fa
@args = ( '-f', 't/data/analysis_submission_manifest_with_contigs_fa.xls', '-o', "$tmp/analysis_submission_report_with_contigs_fa.xls", '-c', 't/data/test_ena_data_submission.conf' );
$obj = Bio::ENA::DataSubmission::CommandLine::SubmitAnalysisObjects->new(
    args         => \@args,
    _output_dest => $tmp,
);
ok( $obj->_update_analysis_xml,                         'XML update successful' );
ok(-e $obj->_output_dest . "/analysis_2014-01-01.xml", 'file exists');
ok( compare( 't/data/analysis_updated_with_contigs_fa.xml', $obj->_output_dest . "/analysis_2014-01-01.xml" ) == 0, 'XML contains modified filenames' );

ok($obj->_keep_local_copy_of_submitted_files,'keep local copy of submitted files method');

ok(-e $obj->_output_dest . "/datafiles/test_genome_1.fa.gz", 'Saved local copy of test_genome_1.fa.gz');
ok(-e $obj->_output_dest . "/datafiles/test_genome_2.fa.gz", 'Saved local copy of test_genome_2.fa.gz');

remove_tree( $obj->_output_dest );
remove_tree( $obj->_output_root );
remove_tree($tmp);

unlink('t/data/analysis_submission/contigsfa/1/contigs.fa.gz');
unlink('t/data/analysis_submission/contigsfa/2/contigs.fa.gz');
unlink('t/data/analysis_submission/testfile1.fa.gz');
unlink('t/data/analysis_submission/testfile2.fa.gz');
done_testing();


sub diff_xls {
	my ($x1, $x2) = @_;
	my $x1_data = Bio::ENA::DataSubmission::Spreadsheet->new( infile => $x1 )->parse;
	my $x2_data = Bio::ENA::DataSubmission::Spreadsheet->new( infile => $x2 )->parse;

	return ( $x1_data, $x2_data );
}
