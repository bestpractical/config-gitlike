package Config::GitLike::Cascaded;

use strict;
use warnings;

use Any::Moose;
use Cwd;
use File::Spec;

extends 'Config::GitLike';

=head1 NAME

Config::GitLike::Cascaded - git-like config file parsing with cascaded inheritance

=head1 SYNOPSIS

B<Stop!> Do not pass go! Go directly to L<Config::GitLike|Config::GitLike> and read that
instead. This is a minor variation on that which changes how the configuration
loading works. Everything else is exactly the same. Just swap in
C<Config::GitLike::Cascaded> where it reads C<Config::GitLike>.

=head1 DESCRIPTION

The only difference between this module and C<Config::GitLike> as that
when it's loading the configuration file in the current directory, it
keeps walking the directory tree even if it finds a config file,
whereas C<Config::GitLike> will stop after finding the first.

This allows us to have interesting cascading configuration inheritance.

=head1 METHODS

This module overrides this method from C<Config::GitLike>:

=head2 load_dirs

Load the configuration files in the directory tree, starting with the root
directory and walking up to the current working directory. (No error is thrown
if no config files are found.)

Returns nothing of note.

=cut

sub load_dirs {
    my $self = shift;
    my $path = shift;
    my($vol, $dirs, undef) = File::Spec->splitpath( $path, 1 );
    my @dirs = File::Spec->splitdir( $dirs );
    for my $i ( 1 .. $#dirs ) {
        my $path = File::Spec->catpath( $vol, File::Spec->catdir(@dirs[0..$i]), $self->dir_file );
        $self->load_file( $path ) if -e $path;
    }
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

__END__

=head1 SEE ALSO

L<Config::GitLike|Config::GitLike>

=head1 LICENSE

You may modify and/or redistribute this software under the same terms
as Perl 5.8.8.

=head1 COPYRIGHT

Copyright 2009 Best Practical Solutions, LLC

=head1 AUTHORS

Alex Vandiver <alexmv@bestpractical.com>,
Christine Spang <spang@bestpractical.com>
