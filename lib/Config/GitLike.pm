package Config::GitLike;

use strict;
use warnings;
use File::Spec;
use Cwd;
use File::HomeDir;
use Regexp::Common;
use Any::Moose;
use Fcntl qw/O_CREAT O_EXCL O_WRONLY/;
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

Config::GitLike - git-compatible config file parsing

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

    $self->parse_content(
        content  => $c,
        callback => sub {
            $self->define(@_);
        },
        error    => sub {
            die "Error parsing $filename, near:\n@_\n";
        },
    );
    return $self->data;
}


sub parse_content {
    my $self = shift;
    my %args = @_;
    my $c = $args{content};
    my $length = length $c;

    my($section, $prev) = (undef, '');
    while (1) {
        $c =~ s/\A\s*//im;

        my $offset = $length - length($c);
        if ($c =~ s/\A[#;].*?$//im) {
            next;
        } elsif ($c =~ s/\A\[([0-9a-z.-]+)(?:[\t ]*"(.*?)")?\]//im) {
            $section = lc $1;
            $section .= ".$2" if defined $2;
            $args{callback}->(
                section    => $section,
                offset     => $offset,
                length     => ($length - length($c)) - $offset,
            );
        } elsif ($c =~ s/\A([0-9a-z-]+)[\t ]*([#;].*)?$//im) {
            $args{callback}->(
                section    => $section,
                name       => $1,
                offset     => $offset,
                length     => ($length - length($c)) - $offset,
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
                    return $args{error}->($c);
                }
            }
            $args{callback}->(
                section    => $section,
                name       => $name,
                value      => $value,
                offset     => $offset,
                length     => ($length - length($c)) - $offset,
            );
        } elsif (not length $c) {
            last;
        } else {
            return $args{error}->($c);
        }
    }
}

sub define {
    my $self = shift;
    my %args = @_;
    return unless defined $args{name};
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

sub format_section {
    my $self = shift;
    my $section = shift;
    if ($section =~ /^(.*?)\.(.*)$/) {
        my ($section, $subsection) = ($1, $2);
        $subsection =~ s/(["\\])/\\$1/g;
        return qq|[$section "$subsection"]\n|;
    } else {
        return qq|[$section]\n|;
    }
}

sub format_definition {
    my $self = shift;
    my %args = @_;
    my $quote = $args{value} =~ /(^\s|;|#|\s$)/ ? '"' : '';
    $args{value} =~ s/\\/\\\\/g;
    $args{value} =~ s/"/\\"/g;
    $args{value} =~ s/\t/\\t/g;
    $args{value} =~ s/\n/\\n/g;
    my $ret = "$args{key} = $quote$args{value}$quote";
    $ret = "\t$ret\n" unless $args{bare};
    return $ret;
}

sub set {
    my $self = shift;
    my (%args) = (
        key      => undef,
        value    => undef,
        filename => undef,
        filter   => undef,
        @_
    );

    $args{multiple} = $self->is_multiple($args{key})
        unless defined $args{multiple};

    $args{key} =~ /^(?:(.*)\.)?(.*)$/;
    my($section, $key) = ($1, $2);
    die "No section given in key $args{key}\n" unless defined $section;

    unless (-e $args{filename}) {
        die "No occurrance of $args{key} found to unset in $args{filename}\n"
            unless defined $args{value};
        open(my $fh, ">", $args{filename})
            or die "Can't write to $args{filename}: $!\n";
        print $fh $self->format_section($section);
        print $fh $self->format_definition( key => $key, value => $args{value} );
        close $fh;
        return;
    }

    open(my $fh, "<", $args{filename}) or return;
    my $c = do {local $/; <$fh>};
    $c =~ s/\n*$/\n/; # Ensure it ends with a newline
    close $fh;

    my $new;
    my @replace;
    $self->parse_content(
        content  => $c,
        callback => sub {
            my %got = @_;
            return unless $got{section} eq $section;
            $new = $got{offset} + $got{length};
            return unless defined $got{name};
            push @replace, {offset => $got{offset}, length => $got{length}}
                if lc $key eq $got{name};
        },
        error    => sub {
            die "Error parsing $args{filename}, near:\n@_\n";
        },
    );

    if ($args{multiple}) {
        die "!!!"; # Unimplemented yet
    } else {
        die "Multiple occurrances of non-multiple key?"
            if @replace > 1;
        if (defined $args{value}) {
            if (@replace) {
                # Replacing an existing value
                substr(
                    $c,
                    $replace[0]{offset},
                    $replace[0]{length},
                    $self->format_definition(
                        key   => $key,
                        value => $args{value},
                        bare  => 1,
                    )
                );
            } elsif (defined $new) {
                # Adding a new value to the end of an existing block
                substr(
                    $c,
                    index($c, "\n", $new)+1,
                    0,
                    $self->format_definition(
                        key   => $key,
                        value => $args{value}
                    )
                );
            } else {
                # Adding a new section
                $c .= $self->format_section($section);
                $c .= $self->format_definition( key => $key, value => $args{value} );
            }
        } else {
            # Removing an existing value
            die "No occurrance of $args{key} found to unset in $args{filename}\n"
                unless @replace;

            my $start = rindex($c, "\n", $replace[0]{offset});
            substr(
                $c,
                $start,
                index($c, "\n", $replace[0]{offset}+$replace[0]{length})-$start,
                ""
            );
        }
    }

    sysopen($fh, "$args{filename}.lock", O_CREAT|O_EXCL|O_WRONLY)
        or die "Can't open $args{filename}.lock for writing: $!\n";
    syswrite($fh, $c);
    close($fh);

    rename("$args{filename}.lock", $args{filename})
        or die "Can't rename $args{filename}.lock to $args{filename}: $!\n";
}

=head1 LICENSE

You may modify and/or redistribute this software under the same terms
as Perl 5.8.8.

=head1 COPYRIGHT

Copyright 2009 Best Practical Solutions, LLC

=head1 AUTHOR

Alex Vandiver <alexmv@bestpractical.com>

=cut

1;
