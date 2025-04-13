use utf8;
use strict;
use warnings;

use lib qw(t/lib);
use Test::More;

my $U = require Local::Util;

$U->sanity;

my $help_pattern    = qr/help/;
my $version_pattern = qr//;
my $no_args_error   = "No arguments!\n";

my @table = (
	map( { { label => $_, args => [$_], output => $help_pattern    } } qw(-h --help) ),
	map( { { label => $_, args => [$_], output => $version_pattern } } qw(-v --version) ),

	{
	label => '-h and -v',
	args => [qw(-h -v)],
	output => $help_pattern,
	},

	{
	label => '-h and --version',
	args => [qw(-h --version)],
	output => $help_pattern,
	},

	{
	label => '-v and -h',
	args => [qw(-v -h)],
	output => $help_pattern,
	},

	{
	label => '-v and --help',
	args => [qw(-v --help)],
	output => $help_pattern,
	},

	{
	label => '--version and --help',
	args => [qw(--version --help)],
	output => $help_pattern,
	},

	{
	label => 'no args',
	args  => [],
	error => $no_args_error,
	exit  => 2,
	},

	);

foreach my $row ( @table ) {
	subtest $row->{label} => sub {
		my $hash = $U->run_command(
			args => $row->{args},
			);
		# diag( explain $hash );
		isa_ok $hash, ref {};
		# diag join ' ', $hash->{command}->@*;
		is $hash->{'error'}, $row->{error} // '', "there was no error output";
		is $hash->{'exit'}, $row->{exit} // 0, "$row->{label} exits with 0";

		if( defined $row->{output} ) {
			like $hash->{'output'}, $row->{output}, "expected help message";
			}
		};
	}

done_testing();
