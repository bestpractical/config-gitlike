package Config::GitLike;

use strict;
use warnings;
use File::Spec;
use Cwd;
use File::HomeDir;
use Regexp::Common;
use Any::Moose;
use 5.008;


has 'confname' => (
    is => 'rw',
    required => 1,
    isa => 'Str',
);

has 'data' => (
    is => 'rw',
    predicate => 'is_loaded',
    isa => 'HashRef',
);

has 'multiple' => (
    is => 'rw',
    isa => 'HashRef',
    default => sub { +{} },
);


=head1 NAME

Config::GitLike

=cut


sub set_multiple {
    my $self = shift;
    my ($name, $mult) = @_, 1;
    $self->multiple->{$name} = $mult;
}

sub is_multiple {
    my $self = shift;
    my $name = shift;
    return $self->multiple->{$name};
}

sub load {
    my $self = shift;
    $self->data({});
    $self->load_global;
    $self->load_user;
    $self->load_dirs;
    return $self->data;
}

sub dir_file {
    my $self = shift;
    return "." . $self->confname;
}

sub load_dirs {
    my $self = shift;
    my($vol, $dirs, undef) = File::Spec->splitpath( Cwd::cwd, 1 );
    my @dirs = File::Spec->splitdir( $dirs );
    while (@dirs) {
        my $path = File::Spec->catpath( $vol, File::Spec->catdir(@dirs), $self->dir_file );
        if (-e $path) {
            $self->load_file( $path );
            last;
        }
    }
}

sub global_file {
    my $self = shift;
    return "/etc/" . $self->confname;
}

sub load_global {
    my $self = shift;
    return unless -e $self->global_file;
    return $self->load_file( $self->global_file );
}

sub user_file {
    my $self = shift;
    return File::Spec->catfile( File::HomeDir->my_home, "." . $self->confname );
}

sub load_user {
    my $self = shift;
    return unless -e $self->user_file;
    return $self->load_file( $self->user_file );
}

sub load_file {
    my $self = shift;
    my ($filename) = @_;
    open(my $fh, "<", $filename) or return;
    my $c = do {local $/; <$fh>};
    close $fh;

    my($section, $prev) = (undef, '');
    while (1) {
        $c =~ s/\A\s*//im;

        if ($c =~ s/\A[#;].*?$//im) {
            next;
        } elsif ($c =~ s/\A\[([0-9a-z.-]+)(?:[\t ]*"(.*?)")?\]//im) {
            $section = lc $1;
            $section .= ".$2" if defined $2;
        } elsif ($c =~ s/\A([0-9a-z-]+)[\t ]*([#;].*)?$//im) {
            $self->define(
                section    => $section,
                name       => $1,
            );
        } elsif ($c =~ s/\A([0-9a-z-]+)[\t ]*=[\t ]*//im) {
            my $name = $1;
            my $value = "";
            while (1) {
                if ($c =~ s/\A[\t ]+//im) {
                    $value .= ' ';
                } elsif ($c =~ s/\A\\\r?\n//im) {
                    next;
                } elsif ($c =~ s/\A([#;].*?)?$//im) {
                    last;
                } elsif ($c =~ s/\A\\(['"])//im) {
                    $value .= $1;
                } elsif ($c =~ s/\A\\n//im) {
                    $value .= "\n";
                } elsif ($c =~ s/\A\\t//im) {
                    $value .= "\t";
                } elsif ($c =~ s/\A\\b//im) {
                    $value .= "\b";
                } elsif ($c =~ s/\A"([^"\\]*(?:(?:\\\n|\\[tbn"\\])[^"\\]*)*)"//im) {
                    my $v = $1;
                    $v =~ s/\\\n//g;
                    $v =~ s/\\n/\n/g;
                    $v =~ s/\\t/\t/g;
                    $v =~ s/\\b/\b/g;
                    $v =~ s/\\\\/\\/g;
                    $value .= $v;
                } elsif ($c =~ s/\A([^\t \\\n]+)//im) {
                    $value .= $1;
                } else {
                    die "Bad config file $filename, near:\n$c";
                }
            }
            $self->define(
                section    => $section,
                name       => $name,
                value      => $value,
            );
        } elsif (not length $c) {
            last;
        } else {
            die "Bad config file $filename, near:\n$c";
        }
    }
}

sub define {
    my $self = shift;
    my %args = @_;
    $args{name} = lc $args{name};
    my $key = join(".", grep {defined} @args{qw/section name/});
    if ($self->is_multiple($key)) {
        push @{$self->data->{$key} ||= []}, $args{value};
    } else {
        $self->data->{$key} = $args{value};
    }
}

sub cast {
    my $self = shift;
    my %args = @_;
    my $v = $args{value};
    return $v unless defined $args{as};
    if ($args{as} =~ /bool/i) {
        return 1 unless defined $v;
        return $v =~ /true|yes|on|1/;
    } elsif ($args{as} =~ /int|num/) {
        if ($v =~ s/([kmg])$//) {
            $v *= 1024 if $1 eq "k";
            $v *= 1024*1024 if $1 eq "m";
            $v *= 1024*1024*1024 if $1 eq "g";
        }
        return $v + 0;
    }
}

sub get {
    my $self = shift;
    my %args = @_;
    $self->load unless $self->is_loaded;
    return undef unless exists $self->data->{$args{key}};
    my $v = $self->data->{$args{key}};
    if (ref $v) {
        die "Multiple values";
    } else {
        return $self->cast( value => $v, as => $args{as} );
    }
}

sub get_all {
    my $self = shift;
    my %args = @_;
    $self->load unless $self->is_loaded;
    return undef unless exists $self->data->{$args{key}};
    my $v = $self->data->{$args{key}};
    my @v = ref $v ? @{$v} : ($v);
    return map {$self->cast( value => $v, as => $args{as} )} @v;
}

sub dump {
    my $self = shift;
    for my $key (sort keys %{$self->data}) {
        if (defined $self->data->{$key}) {
            print "$key=".$self->data->{$key}."\n";
        } else {
            print "$key\n";
        }
    }
}

=head1 LICENSE

You may modify and/or redistribute this software under the same terms as Perl 5.8.8.

=head1 COPYRIGHT

Copyright 2009 Best Practical Solutions, LLC

=head1 AUTHOR

Alex Vandiver <alexmv@bestpractical.com>

=cut

1;
