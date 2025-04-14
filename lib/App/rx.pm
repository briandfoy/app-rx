package App::rx;
use strict;

use warnings;
no warnings;

our $VERSION = '0.001_01';

use v5.30;
use experimental qw(signatures);

use Getopt::Long;

use constant F_YAML => 'YAML';
use constant F_JSON => 'JSON';

use constant EX_SUCCESS  => 0;
use constant EX_ARGS     => 2;
use constant EX_BAD_SPEC => 4;
use constant EX_MISSING_DATA_RX => 8;

=encoding utf8

=head1 NAME

App::rx - Apply an Rx specification to data files

=head1 SYNOPSIS

	use App::rx;

=head1 DESCRIPTION

=over 4

=item run

=cut

sub run ( $class, @args ) {
	state $rc = do {
		require Getopt::Long;
		Getopt::Long::Configure( qw(no_ignore_case bundling) );
		};

	bless my $self = {}, $class;

	my( $opts, $spec ) = $self->getoptions_spec;
	my $ret = Getopt::Long::GetOptionsFromArray( \@args, @$spec );

	if( $opts->{help} ) {
		$self->output( $self->help_message );
		exit EX_SUCCESS;
		}

	if( $opts->{version} ) {
		$self->output( $self->version_message );
		exit EX_SUCCESS;
		}

	my( $spec_file, @files ) = @args;
	unless( defined $spec_file ) {
		$self->error_output( "No arguments!" );
		exit EX_ARGS;
		}

	my $schema;
	CHECK_SPEC: {
		my $result = $self->check_spec( $spec_file );
		my $had_errors = ref $result eq ref [];

		if( $opts->{check_spec_only} ) {
			$self->output( "Spec <$spec_file> " . ( $had_errors ? "has problems" : "compiles" ) );
			if( $had_errors ) {
				foreach my $hash ( $result->@* ) {
					$self->error_output( "* " . $hash->{message} );
					}
				}
			}

		exit( $had_errors ) if $opts->{check_spec_only};

		$schema = $result;
		}

	unless( @files ) {
		push @files, '-';
		}

	my $result = $self->check_files( $opts, $schema, @files );

	}

=item error_output( MESSAGES )

=cut

sub error_output ($self, @messages) {
	chomp(@messages);
	say STDERR join "\n", @messages;
	}

=item getoptions_spec

=cut

sub getoptions_spec ($self) {
	my $opts = {};

	return ($opts, [
		'h|help'       => \$opts->{help},
		'v|version'    => \$opts->{version},
		'V|verbose'    => \$opts->{verbose},
		'c|check-spec-only' => \$opts->{check_spec_only},
		'j|json'       => \$opts->{json},
		]),
	}

=item help_message

=cut

sub help_message ($class) {
	"This is the help message";
	}

=item output( MESSAGES )

=cut

sub output ($self, @messages) {
	chomp(@messages);
	say STDOUT join "\n", @messages;
	}

=item version_message

=cut

sub version_message ($class) {
	require File::Basename;
	sprintf "%s version %s", File::Basename::basename($0), $VERSION;
	}


=back

=head2 Instance methods

=over 4

=item check_files( SPEC_FILE, FILES )

Validate the list of C<FILES> with the Rx specifcation in C<SPEC_FILE>.

This returns an array ref of hash references. If there are no items in
that array ref, there was no error.

=cut


sub check_files ( $self, $opts, $schema, @files ) {
	my @errors;

	FILE: foreach my $file ( @files ) {
		say STDERR "===== $file";
		my $input;
		if( $file eq '-' ) {
			$self->error_output( "Waiting for input on standard input" );
			$input = do { local $/; <STDIN> };
			}
		else {
			if( ! -e $file ) {
				push @errors, { file => $file, message => 'file does not exist' };
				next FILE;
				}
			elsif( ! -r $file ) {
				push @errors, { file => $file, message => 'file is not readable' };
				next FILE;
				}

			$input = eval { $self->load_file($file) } if $file ne '-';
			if( $@ ) {
				my $at = $@;
				$at =~ s/.*\K\h+ at \h+ .*? Rx\.pm \h+ line \h+ \d+ .*//xsi;
				return [ { file => $file, message =>  "Could not load data file <$file>\n$at" } ];
				}
			}

		unless( defined $input ) {
			push @errors, { file => $file, message => "file could not be read: $!" };
			next FILE;
			}

		my $result = eval { $schema->assert_valid($input) };
		my $at = $@;

		next FILE unless eval { $at->can('failures') };

		foreach my $failure ( $at->failures ) {
			push @errors, { file => $file, message => $failure->error_string };
			}
		}

	return \@errors;
	}

=item check_spec( SPEC_FILE )

=cut

sub check_spec ( $self, $spec_file ) {
	state $rc = eval { require Data::Rx };
	return [ { file => $0, message =>  "This program needs the Data::Rx Perl module, but did not find it\nYou can install it with `cpan Data::Rx`", exit_code => EX_MISSING_DATA_RX } ]
		unless $rc;

	my @errors;

	my $spec = eval { $self->load_file($spec_file) };
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

	return $schema;
	}

=item detect_format( FILE )

Return a value to indicate the file type guessed by the file extension.

Later this might be more sophisticated.

=cut

sub detect_format($class, $file) {
	my $format = do {
		local $_ = $file;
		if( /\.json/ ) { F_JSON }
		elsif( /\.ya?ml/ ) { F_YAML }
		};

	return $format if defined $format;

	return;
	}

=item json_load_file( FILE )

Load a JSON file, decode it, and return the data structure.

This will throw an exception from the L<JSON> module if there is a
problem.

=cut

sub json_load_file ($class, $file) {
	state $rc = require JSON;
	my $input = $class->slurp_raw( $file );
	JSON::decode_json( $input );
	}

=item load_file( FILE )

Load the file and interpret its contents according to its file
type. This is the way you should load files in higher level code.
Most of the other subroutines merely support this subroutine.

This may throw an exception from the L<JSON> or L<YAML> modules if
the formats are bad.

=cut

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

=item slurp_raw( FILE )

Read all the contents of C<FILE> and return the raw octets.

=cut

sub slurp_raw ($class, $file) {
	do { local $/; open my $fh, '<:raw', $file; <$fh> };
	}

=item slurp_utf8( FILE )

Read all the contents of C<FILE> and decode those as UTF-8.

=cut

sub slurp_utf8 ($class, $file) {
	do { local $/; open my $fh, '<:encoding(UTF8)', $file; <$fh> };
	}

=back

=head1 TO DO

Lots of stuff. I'm just starting this.

=head1 SEE ALSO

=over 4

=item L<Data::Rx>

=item L<https://rx.codesimply.com>

=back

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
