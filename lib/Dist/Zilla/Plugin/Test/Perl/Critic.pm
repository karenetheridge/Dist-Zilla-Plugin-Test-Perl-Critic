use 5.008;
use strict;
use warnings;

package Dist::Zilla::Plugin::Test::Perl::Critic;
# ABSTRACT: Tests to check your code against best practices
our $VERSION = '3.006';
use Moose;

use Moose::Util::TypeConstraints qw(
    role_type
);
use Dist::Zilla::File::InMemory;
use Sub::Exporter::ForMethods 'method_installer';
use Data::Section 0.004 { installer => method_installer }, '-setup';
use Data::Dumper ();
use namespace::autoclean;
use Path::Tiny qw( path );

# and when the time comes, treat them like templates
with (
    'Dist::Zilla::Role::FileFinderUser' => {
        default_finders => [],
    },
    'Dist::Zilla::Role::FileGatherer',
    'Dist::Zilla::Role::FileMunger',
    'Dist::Zilla::Role::TextTemplate',
    'Dist::Zilla::Role::PrereqSource',
);

has filename => (
    is => 'ro',
    default => 'xt/author/critic.t',
);

has _file => (
    is => 'ro',
    isa => role_type('Dist::Zilla::Role::File'),
    lazy => 1,
    default => sub {
        my $self = shift;
        return Dist::Zilla::File::InMemory->new(
            name => $self->filename,
            content => ${$self->section_data('test-perl-critic')},
        );
    },
);

sub mvp_aliases { {
    profile => 'critic_config',
} }

sub mvp_multivalue_args { qw(
    files
) }

has critic_config => (
    is      => 'ro',
    isa     => 'Str',
);

has embed_critic_config => (
    is      => 'ro',
    isa     => 'Bool',
    default => sub { 0; },
);

has verbose => (
    is => 'ro',
);

has files => (
    is => 'ro',
    isa => 'ArrayRef[Str]',
);

has all_files => (
    is => 'ro',
    lazy => 1,
    isa => 'Maybe[ArrayRef[Str]]',
    default => sub {
        my $self = shift;
        my $files = $self->files;
        return undef
            if !@{ $self->finder } && !$files;
        return [
          @{ $files || [] },
          (map $_->name, @{ $self->found_files }),
        ];
    },
);

sub gather_files {
    my $self = shift;
    $self->add_file( $self->_file );
}

sub register_prereqs {
    my $self = shift;

    $self->zilla->register_prereqs(
        {
            type  => 'requires',
            phase => 'develop',
        },
        'Test::Perl::Critic' => 0,

        # TODO also extract list of policies used in file $self->critic_config
    );
}

sub _dumper {
    my ($value) = @_;
    local $Data::Dumper::Indent = 1;
    local $Data::Dumper::Useqq = 1;
    local $Data::Dumper::Terse = 1;
    local $Data::Dumper::Sortkeys = 1;
    local $Data::Dumper::Trailingcomma = 1;
    my $dump = Data::Dumper::Dumper($value);
    $dump =~ s{\n\z}{};
    return $dump;
}

sub munge_file {
    my $self = shift;
    my ($file) = @_;

    return
        unless $file == $self->_file;

    my $options = {};
    my @conf;
    if (defined(my $verbose = $self->verbose)) {
        $options->{'-verbose'} = $verbose;
    }
    if ($self->embed_critic_config) {
        if (my $profile = $self->critic_config) {
            @conf = path($profile)->lines_utf8( { chomp => 1, });
        }
        else {
            @conf = path('.perlcriticrc')->lines_utf8( { chomp => 1, });
        }
    }
    elsif (my $profile = $self->critic_config) {
        $options->{'-profile'} = $profile;
    }
    elsif (grep $_->name eq 'perlcritic.rc', @{ $self->zilla->files }) {
        $options->{'-profile'} = 'perlcritic.rc';
    }

    $file->content(
        $self->fill_in_string(
            $file->content,
            {
                dist    => \($self->zilla),
                plugin  => \$self,
                dumper  => \\&_dumper,
                options => \$options,
                files   => \$self->all_files,
                conf    => \\@conf,
                embed_critic_config => 0 + $self->embed_critic_config,
            }
        )
    );
}

no Moose;
__PACKAGE__->meta->make_immutable;
1;
=pod

=for Pod::Coverage gather_files register_prereqs munge_file mvp_aliases

=for stopwords LICENCE

=head1 SYNOPSIS

In your F<dist.ini>:

    [Test::Perl::Critic]
    critic_config = perlcritic.rc ; default / relative to project root

=head1 DESCRIPTION

This will provide a F<xt/author/critic.t> file for use during the "test" and
"release" calls of C<dzil>. To use this, make the changes to F<dist.ini>
above and run one of the following:

    dzil test
    dzil release

During these runs, F<xt/author/critic.t> will use L<Test::Perl::Critic> to run
L<Perl::Critic> against your code and by report findings.

=head1 OPTIONS

=head2 filename

The file name of the test to generate. Defaults to F<xt/author/critic.t>.

=head2 critic_config

This plugin accepts the C<critic_config> option, which s
Specifies your own config file for L<Perl::Critic>. It defaults to
C<perlcritic.rc>, relative to the project root. If the file does not exist,
L<Perl::Critic> will use its defaults.

The option can also be configured using the C<profile> alias.

=head2 verbose

If configured, overrides the C<-verbose> option to L<Perl::Critic>.

=head2 files

If specified, will be used as the list of files to check. If neither C<files>
C<finder> is specified, L<Test::Perl::Critic>'s default behavior of checking
all files will be used.

=head2 finder

Can be specified to use a L<file finder|Dist::Zilla::Role::FileFinderUser/default_finders>
to select the files to check, rather than checking all files.

=cut

__DATA__
___[ test-perl-critic ]___
#!perl

use strict;
use warnings;
{{ $embed_critic_config ?
      "\n" . 'my @conf = <DATA>;'
    . "\n" . 'chomp @conf;'
    . "\n"
    : ''
}}
use Test::Perl::Critic{{ $embed_critic_config ? "\n" . '  q{-profile} => \@conf,' . "\n" : '' }}{{ %$options ? ' %{+' . $dumper->($options) . '}' : '' }};
all_critic_ok({{ $files ? '@{' . $dumper->($files) . '}' : '' }});{{ $embed_critic_config ?
      "\n" . '__DATA__'
    . "\n" . (join qq{\n}, @{$conf})
    : ''
}}
