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

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 METHODS

=cut

=head2 set_multiple $name

Mark the key string C<$name> as containing multiple values.

Returns nothing.

=cut

sub set_multiple {
    my $self = shift;
    my ($name, $mult) = @_, 1;
    $self->multiple->{$name} = $mult;
}

=head2 is_multiple $name

Return a true value if the key string C<$name> contains multiple values; false
otherwise.

=cut

sub is_multiple {
    my $self = shift;
    my $name = shift;
    return $self->multiple->{$name};
}

=head2 load

Load the global, local, and directory configuration file with the filename
C<confname> into the C<data> attribute (if they exist).

Returns the contents of the C<data> attribute after all configs have been
loaded.

=cut

sub load {
    my $self = shift;
    my $path = shift || Cwd::cwd;
    $self->data({});
    $self->load_global;
    $self->load_user;
    $self->load_dirs( $path );
    return $self->data;
}

=head2 dir_file

Return a string representing the path to a configuration file with the
name C<confname> in the current working directory (or a directory higher
on the directory tree).

Override this method in a subclass if the directory file has a name
other than C<confname> or is contained in, for example, a subdirectory
(such as with C<./.git/config> versus C<~/.gitconfig>).

=cut

sub dir_file {
    my $self = shift;
    return "." . $self->confname;
}

=head2 load_dirs

Load the configuration file in the current working directory into the C<data>
attribute or, if there is no config matching C<dir_file> in the current working
directory, walk up the directory tree until one is found. (No error is thrown
if none is found.)

Returns nothing of note.

=cut

sub load_dirs {
    my $self = shift;
    my $path = shift;
    my($vol, $dirs, undef) = File::Spec->splitpath( $path, 1 );
    my @dirs = File::Spec->splitdir( $dirs );
    while (@dirs) {
        my $path = File::Spec->catpath( $vol, File::Spec->catdir(@dirs), $self->dir_file );
        if (-f $path) {
            $self->load_file( $path );
            last;
        }
        pop @dirs;
    }
}

=head2 global_file

Return a string representing the path to a system-wide configuration file with
name C<confname> (the L<Config::GitLike> object's C<confname> attribute).

Override this method in a subclass if the global file has a different name
than C<confname> or is contained in a directory other than C</etc>.

=cut

sub global_file {
    my $self = shift;
    return "/etc/" . $self->confname;
}

=head2 load_global

If a global configuration file with the name C<confname> exists, load
its configuration variables into the C<data> attribute.

Returns the current contents of the C<data> attribute after the
file has been loaded, or undef if no global config file is found.

=cut

sub load_global {
    my $self = shift;
    return unless -f $self->global_file;
    return $self->load_file( $self->global_file );
}

=head2 user_file

Return a string representing the path to a configuration file
in the current user's home directory with filename C<confname>.

Override this method in a subclass if the user directory file
does not have the same name as the global config file.

=cut

sub user_file {
    my $self = shift;
    return File::Spec->catfile( File::HomeDir->my_home, "." . $self->confname );
}

=head2 load_user

If a configuration file with the name C<confname> exists in the current
user's home directory, load its config variables into the C<data>
attribute.

Returns the current contents of the C<data> attribute after the file
has been loaded, or undef if no global config file is found.

=cut

sub load_user {
    my $self = shift;
    return unless -f $self->user_file;
    return $self->load_file( $self->user_file );
}

=head2 load_file $filename

Takes a string containing the path to a file, opens it if it exists, loads its
config variables into the C<data> attribute, and returns the current contents
of the C<data> attribute (a hashref).

=cut

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

=head2 parse_content( content => $str, callback => $sub, error => $sub )

Takes arguments consisting of C<content>, a string of the content of the
configuration file to be parsed, C<callback>, a submethod to run on information
retrieved from the config file (headers, subheaders, and key/value pairs), and
C<error>, a submethod to run on malformed content.

Returns undef on success and C<error($content)> on failure.

C<callback> is called like:

    callback(section => $str, offset => $num, length => $num, name => $str, value => $str)

C<name> and C<value> may be omitted if the callback is not being called on a
key/value pair, or if it is being called on a key with no value.

C<error> is called like:

    error( content => $content, offset => $offset )

=cut

sub parse_content {
    my $self = shift;
    my %args = (
        content  => "",
        callback => sub {},
        error    => sub {},
        @_,
    );
    my $c = $args{content};
    my $length = length $c;

    my($section, $prev) = (undef, '');
    while (1) {
        # drop leading blank lines
        $c =~ s/\A\s*//im;

        my $offset = $length - length($c);
        # drop lines that start with a comment
        if ($c =~ s/\A[#;].*?$//im) {
            next;
        # [sub]section headers of the format [section "subsection"] (with
        # unlimited whitespace between). variable definitions may directly
        # follow the section header, on the same line!
        } elsif ($c =~ s/\A\[([0-9a-z.-]+)(?:[\t ]*"(.*?)")?\]//im) {
            $section = lc $1;
            $section .= ".$2" if defined $2;
            $args{callback}->(
                section    => $section,
                offset     => $offset,
                length     => ($length - length($c)) - $offset,
            );
        # keys followed by a unlimited whitespace and (optionally) a comment
        # (no value)
        } elsif ($c =~ s/\A([0-9a-z-]+)[\t ]*([#;].*)?$//im) {
            $args{callback}->(
                section    => $section,
                name       => $1,
                offset     => $offset,
                length     => ($length - length($c)) - $offset,
            );
        # key/value pairs (this particular regex matches only the key part and
        # the =, with unlimited whitespace around the =)
        } elsif ($c =~ s/\A([0-9a-z-]+)[\t ]*=[\t ]*//im) {
            my $name = $1;
            my $value = "";
            while (1) {
                # concatenate whitespace
                if ($c =~ s/\A[\t ]+//im) {
                    $value .= ' ';
                # line continuation (\ character proceeded by new line)
                } elsif ($c =~ s/\A\\\r?\n//im) {
                    next;
                # comment
                } elsif ($c =~ s/\A([#;].*?)?$//im) {
                    last;
                # escaped quote characters are part of the value
                } elsif ($c =~ s/\A\\(['"])//im) {
                    $value .= $1;
                # escaped newline in config is translated to actual newline
                } elsif ($c =~ s/\A\\n//im) {
                    $value .= "\n";
                # escaped tab in config is translated to actual tab
                } elsif ($c =~ s/\A\\t//im) {
                    $value .= "\t";
                # escaped backspace in config is translated to actual backspace
                } elsif ($c =~ s/\A\\b//im) {
                    $value .= "\b";
                # quote-delimited value (possibly containing escape codes)
                } elsif ($c =~ s/\A"([^"\\]*(?:(?:\\\n|\\[tbn"\\])[^"\\]*)*)"//im) {
                    my $v = $1;
                    # remove all continuations (\ followed by a newline)
                    $v =~ s/\\\n//g;
                    # swap escaped newlines with actual newlines
                    $v =~ s/\\n/\n/g;
                    # swap escaped tabs with actual tabs
                    $v =~ s/\\t/\t/g;
                    # swap escaped backspaces with actual backspaces
                    $v =~ s/\\b/\b/g;
                    # swap escaped \ with actual \
                    $v =~ s/\\\\/\\/g;
                    $value .= $v;
                # valid value (no escape codes)
                } elsif ($c =~ s/\A([^\t \\\n]+)//im) {
                    $value .= $1;
                # unparseable
                } else {
                    # Note that $args{content} is the _original_
                    # content, not the nibbled $c, which is the
                    # remaining unparsed content
                    return $args{error}->(
                        content => $args{content},
                        offset =>  $offset,
                    );
                }
            }
            $args{callback}->(
                section    => $section,
                name       => $name,
                value      => $value,
                offset     => $offset,
                length     => ($length - length($c)) - $offset,
            );
        # end of content string; all done now
        } elsif (not length $c) {
            last;
        # unparseable
        } else {
            # Note that $args{content} is the _original_ content, not
            # the nibbled $c, which is the remaining unparsed content
            return $args{error}->(
                content => $args{content},
                offset  => $offset,
            );
        }
    }
}

sub define {
    my $self = shift;
    my %args = (
        section => undef,
        name    => undef,
        value   => undef,
        @_,
    );
    return unless defined $args{name};
    $args{name} = lc $args{name};
    my $key = join(".", grep {defined} @args{qw/section name/});
    if ($self->is_multiple($key)) {
        push @{$self->data->{$key} ||= []}, $args{value};
    } else {
        $self->data->{$key} = $args{value};
    }
}

=head2 cast( value => 'foo', as => 'int' )

Return C<value> cast into the type specified by C<as>.

Valid values for C<as> are C<bool> or C<int>. For C<bool>, C<true>, C<yes>,
C<on>, C<1>, and undef are translated into a true value; anything else is
false.

For C<int>s, if C<value> ends in C<k>, C<m>, or C<g>, it will be multiplied by
1024, 1048576, and 1073741824, respectively, before being returned.

If C<as> is unspecified, C<value> is returned unchanged.

XXX TODO

=cut

sub cast {
    my $self = shift;
    my %args = (
        value => undef,
        as    => undef, # bool, int, or num
        @_,
    );
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

=head2 get( key => 'foo', as => 'int', filter => qr/regex$/ )

Retrieve the config value associated with C<key> cast as an C<as>.

The C<key> option is required (will return undef if unspecified); the C<as>
option is not (will return a string by default).

If C<key> doesn't exist in the config, undef is returned. Dies with
the exception "Multiple values" if the given key has more than one
value associated with it. (Use C<get_all to retrieve multiple values.)

Loads the configuration file with name $confname if it hasn't yet been
loaded. Note that if you've run any C<set> calls to the loaded
configuration files since the last time they were loaded, you MUST
call C<load> again before getting, or the returned configuration data
may not match the configuration variables on-disk.

TODO implement filter (multiple values)

=cut

sub get {
    my $self = shift;
    my %args = (
        key => undef,
        as  => undef,
        @_,
    );
    $self->load unless $self->is_loaded;
    return undef unless exists $self->data->{$args{key}};
    my $v = $self->data->{$args{key}};
    if (ref $v) {
        die "Multiple values";
    } else {
        return $self->cast( value => $v, as => $args{as} );
    }
}

=head2 get_all( key => 'foo', filter => qr/regex$/, as => 'bool' )

Like C<get>, but does not fail if the number of values for the key is not
exactly one.

Returns a list of values, cast as C<as> if C<as> is specified.

TODO implement filter

=cut

sub get_all {
    my $self = shift;
    my %args = (
        key => undef,
        as  => undef,
        @_,
    );
    $self->load unless $self->is_loaded;
    return undef unless exists $self->data->{$args{key}};
    my $v = $self->data->{$args{key}};
    my @v = ref $v ? @{$v} : ($v);
    return map {$self->cast( value => $v, as => $args{as} )} @v;
}

=head2 dump

Print all configuration data, sorted in ASCII order, in the form:

    section.key=value
    section2.key=value

This is similar to the output of C<git config --list>.

=cut

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

=head2 format_section 'section.subsection'

Return a formatted string representing how section headers should be printed in
the config file.

=cut

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
    my %args = (
        key   => undef,
        value => undef,
        bare  => undef,
        @_,
    );
    my $quote = $args{value} =~ /(^\s|;|#|\s$)/ ? '"' : '';
    $args{value} =~ s/\\/\\\\/g;
    $args{value} =~ s/"/\\"/g;
    $args{value} =~ s/\t/\\t/g;
    $args{value} =~ s/\n/\\n/g;
    my $ret = "$args{key} = $quote$args{value}$quote";
    $ret = "\t$ret\n" unless $args{bare};
    return $ret;
}

=head2 set( key => "section.foo", value => "bar", filename => File::Spec->catfile(qw/home user/, "." . $config->confname, filter => qr/regex/ )

Sets the key C<foo> in the configuration section C<section> to the value C<bar> in the
given filename. It's necessary to specify the filename since the C<confname> attribute
is not unambiguous enough to determine where to write to. (There may be multiple config
files in different directories which inherit.)

To unset a key, pass in C<key> but not C<value>.

Returns nothing.

TODO The filter arg is for multiple value support (see value_regex in git help config
for details).

=cut

sub set {
    my $self = shift;
    my (%args) = (
        key      => undef,
        value    => undef,
        filename => undef,
        filter   => undef,
        @_
    );

    die "No key given\n" unless defined $args{key};

    $args{multiple} = $self->is_multiple($args{key})
        unless defined $args{multiple};

    $args{key} =~ /^(?:(.*)\.)?(.*)$/;
    my($section, $key) = ($1, $2);
    die "No section given in key $args{key}\n" unless defined $section;

    unless (-f $args{filename}) {
        die "No occurrence of $args{key} found to unset in $args{filename}\n"
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
            return unless lc($got{section}) eq lc($section);
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
        die "Multiple occurrences of non-multiple key?"
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
            die "No occurrence of $args{key} found to unset in $args{filename}\n"
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

1;

__END__

=head1 LICENSE

You may modify and/or redistribute this software under the same terms
as Perl 5.8.8.

=head1 COPYRIGHT

Copyright 2009 Best Practical Solutions, LLC

=head1 AUTHOR

Alex Vandiver <alexmv@bestpractical.com>
