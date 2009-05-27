package Config::GitLike::Cascaded;

use strict;
use warnings;

use Any::Moose;
use Cwd;
use File::Spec;

extends 'Config::GitLike';

sub load_dirs {
    my $self = shift;
    my $path = shift;
    my($vol, $dirs, undef) = File::Spec->splitpath( $path, 1 );
    my @dirs = File::Spec->splitdir( $dirs );
    while (@dirs) {
        my $path = File::Spec->catpath( $vol, File::Spec->catdir(@dirs), $self->dir_file );
        $self->load_file( $path ) if -e $path;
        pop @dirs;
    }
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
