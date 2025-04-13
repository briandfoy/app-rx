use v5.30;

package Local::Util;
use experimental qw(signatures);

use Test::More;

sub sanity  ( $this ) {
	subtest 'sanity' => sub {
		use_ok $this->class;
		can_ok $this->class, 'run';
		}
	}

sub class   ( $class ) { 'App::rx'        }
sub program ( $class ) { 'blib/script/rx' }

sub run_command ( $class, %hash ) {
	state $rc = require IPC::Open3;
	state $rc2 = require Symbol;

	my @command = ( $^X, $class->program, exists $hash{args} ? $hash{args}->@* : () );

	my $pid = IPC::Open3::open3(
		my $input_fh,
		my $output_fh,
		my $error_fh = Symbol::gensym(),
		@command
		);

	if( $hash{input} ) {
		print { $input_fh } $hash{input};
		}
	close $input_fh;

	my $output = do { local $/; <$output_fh> };
	my $error  = do { local $/; <$error_fh> };

	waitpid $pid, 0;
	my $exit = $? >> 8;

	return {
	    command => \@command,
		output  => $output,
		error   => $error,
		'exit'  => $exit,
		};
	}

__PACKAGE__;
