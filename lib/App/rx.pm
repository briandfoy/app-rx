package App::rx;
use strict;

use warnings;
no warnings;

our $VERSION = '0.001_01';

=encoding utf8

=head1 NAME

App::rx - Apply an Rx specification to data files

=head1 SYNOPSIS

	use App::rx;

=head1 DESCRIPTION

=over 4

=item run( SPEC_FILE, FILES )

=cut

use v5.30;
use experimental qw(signatures);

run(@ARGV) unless caller;

use constant F_YAML => 'YAML';
use constant F_JSON => 'JSON';

use constant EX_SUCCESS  => 0;
use constant EX_ARGS     => 2;
use constant EX_BAD_SPEC => 4;
use constant EX_MISSING_DATA_RX => 8;

sub run ( $class, $spec_file, @files ) {
	state $rc = eval { require Data::Rx };
	return [ { file => $0, message =>  "This program needs the Data::Rx Perl module, but did not find it\nYou can install it with `cpan Data::Rx`", exit_code => EX_MISSING_DATA_RX } ]
		unless $rc;

	my @errors;

	my $spec = eval { $class->load_file($spec_file) };
	unless( defined $spec ) {
		my $at = $@;
		$at =~ s/\h+ at \h+ .*? Rx\.pm \h+ line \h+ \d+ .*//xs;
		return [ { file => $spec_file, message =>  "Could not load spec file <$spec_file>\n$at", exit_code => EX_BAD_SPEC } ];
		}

	my $rx = Data::Rx->new;
	my $schema = eval { $rx->make_schema($spec) };
	unless( defined $schema ) {
		my $at = $@;
		$at =~ s/\h+ at \h+ .*? Rx\.pm \h+ line \h+ \d+ .*//xs;
		return [ { file => $spec_file, message =>  "Could not load Rx schema from <$spec_file>\n$at", exit_code => EX_BAD_SPEC } ];
		}

	push @files, '-' unless @files;

	FILE: foreach my $file ( @files ) {
		my $input;
		if( $file eq '-' ) {
			$input = do { local $/; <STDIN> };
			}

		if( ! -e $file ) {
			push @errors, { file => $file, message => 'file does not exist' };
			next FILE;
			}
		elsif( ! -r $file ) {
			push @errors, { file => $file, message => 'file is not readable' };
			next FILE;
			}

		$input = eval { $class->load_file($file) } if $file ne '-';
		if( $@ ) {
			my $at = $@;
			$at =~ s/.*\K\h+ at \h+ .*? Rx\.pm \h+ line \h+ \d+ .*//xsi;
			return [ { file => $file, message =>  "Could not load data file <$spec_file>\n$at" } ];
			}


		unless( defined $input ) {
			push @errors, { file => $file, message => "file could not be read: $!" };
			next FILE;
			}

		my $result = eval { $schema->assert_valid($input) };
		push @errors, { file => $file, message => $@ } unless $result == 1;
		}

	return \@errors;
	}

sub load_file ($class, $file) {
	my $format = $class->detect_format($file);

	my $data = do {
		if( $format eq F_JSON ) {
			$class->json_load_file( $file );
			}
		elsif( $format eq F_YAML ) {
			require YAML;
			YAML::LoadFile( $file );
			}
		else { undef }
		};

	return $data;
	}

sub detect_format($class, $file) {
	my $format = do {
		local $_ = $file;
		if( /\.json/ ) { F_JSON }
		elsif( /\.ya?ml/ ) { F_YAML }
		};

	return $format if defined $format;

	return;
	}

sub json_load_file ($class, $file) {
	state $rc = require JSON;
	my $input = $class->slurp_raw( $file );
	JSON::decode_json( $input );
	}

sub slurp_raw ($class, $file) {
	do { local $/; open my $fh, '<:raw', $file; <$fh> };
	}

sub slurp_utf8 ($class, $file) {
	do { local $/; open my $fh, '<:encoding(UTF8)', $file; <$fh> };
	}

=back

=head1 TO DO


=head1 SEE ALSO


=head1 SOURCE AVAILABILITY

This source is in Github:

	http://github.com/briandfoy/app-rx

=head1 AUTHOR

brian d foy, C<< <briandfoy@pobox.com> >>

=head1 COPYRIGHT AND LICENSE

Copyright © 2024, brian d foy, All Rights Reserved.

You may redistribute this under the terms of the Artistic License 2.0.

=cut

1;