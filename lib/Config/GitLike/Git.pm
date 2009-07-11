package Config::GitLike::Git;
use Any::Moose;

extends 'Config::GitLike';

has 'confname' => (
    default => 'git',
);

sub dir_file {
    my $self = shift;
    return ".git/config";
}

sub user_file {
    my $self = shift;
    return
        File::Spec->catfile( $ENV{'HOME'}, ".gitconfig" );
}

sub global_file {
    my $self = shift;
    return "/etc/gitconfig";
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;

__END__

=head1 NAME

Config::GitLike::Git - load Git configuration files

=head1 DESCRIPTION

This is a modification of L<Config::GitLike> to look at the same
locations that Git writes to.

=head1 METHODS

This module overrides these methods from C<Config::GitLike>:

=head2 dir_file

The per-directory configuration file is F<.git/config>

=head2 user_file

The per-user configuration file is F<~/.gitconfig>

=head2 global_file

The per-host configuration file is F</etc/gitconfig>

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
