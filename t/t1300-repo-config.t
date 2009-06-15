use strict;
use warnings;

use File::Copy;
use Test::More tests => 101;
use Test::Exception;
use File::Spec;
use File::Temp;
use lib 't/lib';
use TestConfig;

# Tests whose expected behaviour has been modified from that of the
# original git-config test suite are marked with comments.
#
# Additional tests that were not pulled from the git-config test-suite
# are also marked.

sub slurp {
    my $file = shift;
    local ($/);
    open( my $fh, $file ) or die "Unable to open file ${file}: $!";
    return <$fh>;
}

sub burp {
    my ( $file_name, $content, $append ) = @_;
    my $mode = $append ? '>>' : '>';

    open( my $fh, $mode, $file_name )
        || die "can't open ${file_name}: $!";
    print $fh $content;
}

# create an empty test directory in /tmp
my $config_dir = File::Temp->newdir( CLEANUP => !$ENV{CONFIG_GITLIKE_DEBUG} );
my $config_dirname = $config_dir->dirname;
my $config_filename = File::Spec->catfile( $config_dirname, 'config' );

diag "config file is: $config_filename" if $ENV{TEST_VERBOSE};

my $config
    = TestConfig->new( confname => 'config', tmpdir => $config_dirname );
$config->load;

diag('Test git config in different settings') if $ENV{TEST_VERBOSE};

$config->set(
    key      => 'core.penguin',
    value    => 'little blue',
    filename => $config_filename
);

my $expect = <<'EOF'
[core]
	penguin = little blue
EOF
    ;

is( slurp($config_filename), $expect, 'initial' );

$config->set(
    key      => 'Core.Movie',
    value    => 'BadPhysics',
    filename => $config_filename
);

$expect = <<'EOF'
[core]
	penguin = little blue
	Movie = BadPhysics
EOF
    ;

is( slurp($config_filename), $expect, 'mixed case' );

$config->set(
    key      => 'Cores.WhatEver',
    value    => 'Second',
    filename => $config_filename
);

$expect = <<'EOF'
[core]
	penguin = little blue
	Movie = BadPhysics
[Cores]
	WhatEver = Second
EOF
    ;

is( slurp($config_filename), $expect, 'similar section' );

$config->set(
    key      => 'CORE.UPPERCASE',
    value    => 'true',
    filename => $config_filename
);

$expect = <<'EOF'
[core]
	penguin = little blue
	Movie = BadPhysics
	UPPERCASE = true
[Cores]
	WhatEver = Second
EOF
    ;

is( slurp($config_filename), $expect, 'similar section' );

# set returns nothing on success
lives_ok {
    $config->set(
        key      => 'core.penguin',
        value    => 'kingpin',
        filter   => '!blue',
        filename => $config_filename
    );
}
'replace with non-match';

lives_ok {
    $config->set(
        key      => 'core.penguin',
        value    => 'very blue',
        filter   => '!kingpin',
        filename => $config_filename
    );
}
'replace with non-match';

$expect = <<'EOF'
[core]
	penguin = very blue
	Movie = BadPhysics
	UPPERCASE = true
	penguin = kingpin
[Cores]
	WhatEver = Second
EOF
    ;

is( slurp($config_filename), $expect, 'non-match result' );

burp(
    $config_filename,
    '[alpha]
bar = foo
[beta]
baz = multiple \
lines
'
);

lives_ok { $config->set( key => 'beta.baz', filename => $config_filename ) }
'unset with cont. lines';

$expect = <<'EOF'
[alpha]
bar = foo
[beta]
EOF
    ;

is( slurp($config_filename), $expect, 'unset with cont. lines is correct' );

burp(
    $config_filename,
    '[beta] ; silly comment # another comment
noIndent= sillyValue ; \'nother silly comment

# empty line
		; comment
haha = hello
	haha = bello
[nextSection] noNewline = ouch
'
);

my $config2_filename = File::Spec->catfile( $config_dir, '.config2' );

copy( $config_filename, $config2_filename )
    or die "File cannot be copied: $!";

$config->set(
    key      => 'beta.haha',
    filename => $config_filename,
    multiple => 1
);
$expect = <<'EOF'
[beta] ; silly comment # another comment
noIndent= sillyValue ; 'nother silly comment

# empty line
		; comment
[nextSection] noNewline = ouch
EOF
    ;

is( slurp($config_filename), $expect, 'multiple unset is correct' );

copy( $config2_filename, $config_filename )
    or die "File cannot be copied: $!";

unlink $config2_filename;

lives_ok {
    $config->set(
        key         => 'beta.haha',
        value       => 'gamma',
        multiple    => 1,
        replace_all => 1,
        filename    => $config_filename
    );
}
'replace all';

$expect = <<'EOF'
[beta] ; silly comment # another comment
noIndent= sillyValue ; 'nother silly comment

# empty line
		; comment
	haha = gamma
[nextSection] noNewline = ouch
EOF
    ;

is( slurp($config_filename), $expect, 'all replaced' );

$config->set(
    key      => 'beta.haha',
    value    => 'alpha',
    filename => $config_filename
);

$expect = <<'EOF'
[beta] ; silly comment # another comment
noIndent= sillyValue ; 'nother silly comment

# empty line
		; comment
	haha = alpha
[nextSection] noNewline = ouch
EOF
    ;

is( slurp($config_filename), $expect, 'really mean test' );

$config->set(
    key      => 'nextsection.nonewline',
    value    => 'wow',
    filename => $config_filename
);

# NOTE: git moves the definition of the variable without a newline
# to the next line;
# let's not do that since we do substring replacement rather than
# reformatting
$expect = <<'EOF'
[beta] ; silly comment # another comment
noIndent= sillyValue ; 'nother silly comment

# empty line
		; comment
	haha = alpha
[nextSection] nonewline = wow
EOF
    ;

is( slurp($config_filename), $expect, 'really really mean test' );

$config->load;
is( $config->get( key => 'beta.haha' ), 'alpha', 'get value' );

# unset beta.haha (unset accomplished by value = undef)
$config->set( key => 'beta.haha', filename => $config_filename );

$expect = <<'EOF'
[beta] ; silly comment # another comment
noIndent= sillyValue ; 'nother silly comment

# empty line
		; comment
[nextSection] nonewline = wow
EOF
    ;

is( slurp($config_filename), $expect, 'unset' );

$config->set(
    key      => 'nextsection.NoNewLine',
    value    => 'wow2 for me',
    filter   => qr/for me$/,
    filename => $config_filename
);

$expect = <<'EOF'
[beta] ; silly comment # another comment
noIndent= sillyValue ; 'nother silly comment

# empty line
		; comment
[nextSection] nonewline = wow
	NoNewLine = wow2 for me
EOF
    ;

is( slurp($config_filename), $expect, 'multivar' );

$config->load;
lives_ok {
    $config->get(
        key    => 'nextsection.nonewline',
        filter => '!for'
    );
}
'non-match';

lives_and {
    is( $config->get(
            key    => 'nextsection.nonewline',
            filter => '!for'
        ),
        'wow'
    );
}
'non-match value';

# must use get_all to get multiple values
throws_ok { $config->get( key => 'nextsection.nonewline' ) }
qr/multiple values/i, 'ambiguous get';

is_deeply(
    scalar $config->get_all( key => 'nextsection.nonewline' ),
    [ 'wow', 'wow2 for me' ],
    'get multivar'
);

$config->set(
    key      => 'nextsection.nonewline',
    value    => 'wow3',
    filter   => qr/wow$/,
    filename => $config_filename
);

$expect = <<'EOF'
[beta] ; silly comment # another comment
noIndent= sillyValue ; 'nother silly comment

# empty line
		; comment
[nextSection] nonewline = wow3
	NoNewLine = wow2 for me
EOF
    ;

is( slurp($config_filename), $expect, 'multivar replace' );

$config->load;
throws_ok {
    $config->set(
        key      => 'nextsection.nonewline',
        filename => $config_filename
    );
}
qr/Multiple occurrences of non-multiple key/i, 'ambiguous unset';

throws_ok {
    $config->set(
        key      => 'somesection.nonewline',
        filename => $config_filename
    );
}
qr/No occurrence of somesection.nonewline found to unset/i, 'invalid unset';

lives_ok {
    $config->set(
        key      => 'nextsection.nonewline',
        filter   => qr/wow3$/,
        filename => $config_filename
    );
}
"multivar unset doesn't crash";

$expect = <<'EOF'
[beta] ; silly comment # another comment
noIndent= sillyValue ; 'nother silly comment

# empty line
		; comment
[nextSection]
	NoNewLine = wow2 for me
EOF
    ;

is( slurp($config_filename), $expect, 'multivar unset' );

# ADDITIONAL TESTS (7): our rules for valid keys are
# much more permissive than git's
throws_ok {
    $config->set(
        key      => "inval.key=foo",
        value    => 'blabla',
        filename => $config_filename
    );
}
qr/invalid key/i, 'invalid key containing = char';

throws_ok {
    $config->set(
        key      => 'inval.  key',
        value    => 'blabla',
        filename => $config_filename
    );
}
qr/invalid key/i, 'invalid key starting with whitespace';

throws_ok {
    $config->set(
        key      => 'inval.key  ',
        value    => 'blabla',
        filename => $config_filename
    );
}
qr/invalid key/i, 'invalid key ending with whitespace';

throws_ok {
    $config->set(
        key      => "inval.key\n2",
        value    => 'blabla',
        filename => $config_filename
    );
}
qr/invalid key/i, 'invalid key containing newline';

lives_ok {
    $config->set(
        key => 'valid."http://example.com/"',
        value => 'true',
        filename => $config_filename,
    );
}
'can have . char in key if quoted';

lives_and {
    $config->load;
    is( $config->get( key => 'valid."http://example.com/"' ), 'true' );
}
'URL key value is correct';

# kill this section just to not have to modify all the following tests
lives_ok {
    $config->remove_section( section => 'valid', filename => $config_filename );
    $config->load;
}
'remove URL key section';

lives_ok {
    $config->set(
        key      => '123456.a123',
        value    => '987',
        filename => $config_filename
    );
}
'correct key';

lives_ok {
    $config->set(
        key      => 'Version.1.2.3eX.Alpha',
        value    => 'beta',
        filename => $config_filename
    );
}
'correct key';

$expect = <<'EOF'
[beta] ; silly comment # another comment
noIndent= sillyValue ; 'nother silly comment

# empty line
		; comment
[nextSection]
	NoNewLine = wow2 for me
[123456]
	a123 = 987
[Version "1.2.3eX"]
	Alpha = beta
EOF
    ;

is( slurp($config_filename), $expect, 'hierarchical section value' );

$expect = <<'EOF'
123456.a123=987
beta.noindent=sillyValue
nextsection.nonewline=wow2 for me
version.1.2.3eX.alpha=beta
EOF
    ;

$config->load;
is( $config->dump, $expect, 'working dump' );

### ADDITIONAL TEST for dump

my %results = $config->dump;
is_deeply(
    \%results,
    {   '123456.a123'           => '987',
        'beta.noindent'         => 'sillyValue',
        'nextsection.nonewline' => 'wow2 for me',
        'version.1.2.3eX.alpha' => 'beta'
    },
    'dump works in array context'
);

$expect = { 'beta.noindent', 'sillyValue', 'nextsection.nonewline',
    'wow2 for me' };

# test get_regexp

lives_and { is_deeply( scalar $config->get_regexp( key => 'in' ), $expect ) }
'--get-regexp';

$config->set(
    key      => 'nextsection.nonewline',
    value    => 'wow4 for you',
    filename => $config_filename,
    multiple => 1
);

$config->load;

$expect = [ 'wow2 for me', 'wow4 for you' ];

$config->load;
is_deeply( scalar $config->get_all( key => 'nextsection.nonewline' ),
    $expect, '--add' );

burp(
    $config_filename,
    '[novalue]
	variable
[emptyvalue]
	variable =
'
);

$config->load;
lives_and {
    is( $config->get( key => 'novalue.variable', filter => qr/^$/ ), undef );
}
'get variable with no value';

lives_and {
    is( $config->get( key => 'emptyvalue.variable', filter => qr/^$/ ), '' );
}
'get variable with empty value';

# more get_regexp

lives_and {
    is_deeply( scalar $config->get_regexp( key => 'novalue' ),
        { 'novalue.variable' => undef } );
}
'get_regexp variable with no value';

lives_and {
    is_deeply( scalar $config->get_regexp( key => qr/emptyvalue/ ),
        { 'emptyvalue.variable' => '' } );
}
'get_regexp variable with empty value';

# should evaluate to a true value
ok( $config->get( key => 'novalue.variable', as => 'bool' ),
    'get bool variable with no value' );

# should evaluate to a false value
ok( !$config->get( key => 'emptyvalue.variable', as => 'bool' ),
    'get bool variable with empty value' );

# testing alternate subsection notation
burp(
    $config_filename,
    '[a.b]
	c = d
'
);

$config->set( key => 'a.x', value => 'y', filename => $config_filename );

$expect = <<'EOF'
[a.b]
	c = d
[a]
	x = y
EOF
    ;

is( slurp($config_filename), $expect,
    'new section is partial match of another' );

$config->set( key => 'b.x', value => 'y', filename => $config_filename );
$config->set( key => 'a.b', value => 'c', filename => $config_filename );
$config->load;

$expect = <<'EOF'
[a.b]
	c = d
[a]
	x = y
	b = c
[b]
	x = y
EOF
    ;

is( slurp($config_filename), $expect,
    'new variable inserts into proper section' );

# testing rename_section

# NOTE: added comment after [branch "1 234 blabl/a"] to check that our
# implementation doesn't blow away trailing text after a rename like
# git-config currently does
burp(
    $config_filename,
    '# Hallo
	#Bello
[branch "eins"]
	x = 1
[branch.eins]
	y = 1
	[branch "1 234 blabl/a"] ; comment
weird
'
);

lives_ok {
    $config->rename_section(
        from     => 'branch.eins',
        to       => 'branch.zwei',
        filename => $config_filename
    );
}
'rename_section lives';

$expect = <<'EOF'
# Hallo
	#Bello
[branch "zwei"]
	x = 1
[branch "zwei"]
	y = 1
	[branch "1 234 blabl/a"] ; comment
weird
EOF
    ;

is( slurp($config_filename), $expect, 'rename succeeded' );

throws_ok {
    $config->rename_section(
        from     => 'branch."world domination"',
        to       => 'branch.drei',
        filename => $config_filename
    );
}
qr/no such section/i, 'rename non-existing section';

is( slurp($config_filename), $expect,
    'rename non-existing section changes nothing' );

lives_ok {
    $config->rename_section(
        from     => 'branch."1 234 blabl/a"',
        to       => 'branch.drei',
        filename => $config_filename
    );
}
'rename another section';

# NOTE: differs from current git behaviour, because the way that git handles
# renames / variable replacement is buggy (git would write [branch "drei"]
# without the leading tab, and then clobber anything that followed)
$expect = <<'EOF'
# Hallo
	#Bello
[branch "zwei"]
	x = 1
[branch "zwei"]
	y = 1
	[branch "drei"] ; comment
weird
EOF
    ;

is( slurp($config_filename), $expect, 'rename succeeded' );

# [branch "vier"] doesn't get interpreted as a real section
# header because the variable definition before it means
# that all the way to the end of that line is a part of
# a's value
burp(
    $config_filename,
    '[branch "zwei"] a = 1 [branch "vier"]
', 1
);

lives_ok {
    $config->remove_section(
        section  => 'branch.zwei',
        filename => $config_filename
    );
}
'remove section';

# we kill leading whitespace on section removes because it makes
# the implementation easier (can just kill all the way up to
# the following section or the end of the file)
$expect = <<'EOF'
# Hallo
	#Bello
[branch "drei"] ; comment
weird
EOF
    ;

is( slurp($config_filename), $expect, 'section was removed properly' );

unlink $config_filename;

$expect = <<'EOF'
[gitcvs]
	enabled = true
	dbname = %Ggitcvs2.%a.%m.sqlite
[gitcvs "ext"]
	dbname = %Ggitcvs1.%a.%m.sqlite
EOF
    ;

$config->set(
    key      => 'gitcvs.enabled',
    value    => 'true',
    filename => $config_filename
);
$config->set(
    key      => 'gitcvs.ext.dbname',
    value    => '%Ggitcvs1.%a.%m.sqlite',
    filename => $config_filename
);
$config->set(
    key      => 'gitcvs.dbname',
    value    => '%Ggitcvs2.%a.%m.sqlite',
    filename => $config_filename
);
is( slurp($config_filename), $expect, 'section ending' );

# testing int casting

$config->set(
    key      => 'kilo.gram',
    value    => '1k',
    filename => $config_filename
);
$config->set(
    key      => 'mega.ton',
    value    => '1m',
    filename => $config_filename
);
$config->load;
is( $config->get( key => 'kilo.gram', as => 'int' ),
    1024, 'numbers: int k interp' );
is( $config->get( key => 'mega.ton', as => 'int' ),
    1048576, 'numbers: int m interp' );

# units that aren't k/m/g should throw an error

$config->set(
    key      => 'aninvalid.unit',
    value    => '1auto',
    filename => $config_filename
);
$config->load;
throws_ok { $config->get( key => 'aninvalid.unit', as => 'int' ) }
qr/invalid unit/i, 'invalid unit';

my %pairs
    = qw( true1 01 true2 -1 true3 YeS true4 true false1 000 false3 nO false4 FALSE);
$pairs{false2} = '';

for my $key ( keys %pairs ) {
    $config->set(
        key      => "bool.$key",
        value    => $pairs{$key},
        filename => $config_filename
    );
}
$config->load;

my @results = ();

for my $i ( 1 .. 4 ) {
    push( @results,
        $config->get( key => "bool.true$i",  as => 'bool' ),
        $config->get( key => "bool.false$i", as => 'bool' ) );
}

my $b = 1;

while (@results) {
    if ($b) {
        ok( shift @results, 'correct true bool from get' );
    } else {
        ok( !shift @results, 'correct false bool from get' );
    }
    $b = !$b;
}

$config->set(
    key      => 'bool.nobool',
    value    => 'foobar',
    filename => $config_filename
);
$config->load;
throws_ok { $config->get( key => 'bool.nobool', as => 'bool' ) }
qr/invalid bool/i, 'invalid bool (get)';

# test casting with set
throws_ok {
    $config->set(
        key      => 'bool.nobool',
        value    => 'foobar',
        as       => 'bool',
        filename => $config_filename
    );
}
qr/invalid bool/i, 'invalid bool (set)';

unlink $config_filename;

for my $key ( keys %pairs ) {
    $config->set(
        key      => "bool.$key",
        value    => $pairs{$key},
        filename => $config_filename,
        as       => 'bool'
    );
}
$config->load;

@results = ();

for my $i ( 1 .. 4 ) {
    push( @results,
        $config->get( key => "bool.true$i" ),
        $config->get( key => "bool.false$i" ) );
}

$b = 1;

while (@results) {
    if ($b) {
        is( shift @results, 'true', 'correct true bool from set' );
    } else {
        is( shift @results, 'false', 'correct false bool from set' );
    }
    $b = !$b;
}

unlink $config_filename;

$expect = <<'EOF'
[int]
	val1 = 1
	val2 = -1
	val3 = 5242880
EOF
    ;

$config->set(
    key      => 'int.val1',
    value    => '01',
    filename => $config_filename,
    as       => 'int'
);
$config->set(
    key      => 'int.val2',
    value    => '-1',
    filename => $config_filename,
    as       => 'int'
);
$config->set(
    key      => 'int.val3',
    value    => '5m',
    filename => $config_filename,
    as       => 'int'
);

is( slurp($config_filename), $expect, 'set --int' );

unlink $config_filename;

burp(
    $config_filename,
    '[bool]
    true1 = on
    true2 = yes
    false1 = off
    false2 = no
[int]
    int1 = 00
    int2 = 01
    int3 = -01
'
);

$config->load;
is( $config->get( key => 'bool.true1', as => 'bool-or-int', human => 1 ),
    'true', 'get bool-or-int' );
is( $config->get( key => 'bool.true2', as => 'bool-or-int', human => 1 ),
    'true', 'get bool-or-int' );
is( $config->get( key => 'bool.false1', as => 'bool-or-int', human => 1 ),
    'false', 'get bool-or-int' );
is( $config->get( key => 'bool.false2', as => 'bool-or-int', human => 1 ),
    'false', 'get bool-or-int' );
is( $config->get( key => 'int.int1', as => 'bool-or-int' ),
    0, 'get bool-or-int' );
is( $config->get( key => 'int.int2', as => 'bool-or-int' ),
    1, 'get bool-or-int' );
is( $config->get( key => 'int.int3', as => 'bool-or-int' ),
    -1, 'get bool-or-int' );

unlink $config_filename;

$expect = <<'EOF'
[bool]
	true1 = true
	false1 = false
	true2 = true
	false2 = false
[int]
	int1 = 0
	int2 = 1
	int3 = -1
EOF
    ;

$config->set(
    key      => 'bool.true1',
    value    => 'true',
    as       => 'bool-or-int',
    filename => $config_filename
);
$config->set(
    key      => 'bool.false1',
    value    => 'false',
    as       => 'bool-or-int',
    filename => $config_filename
);
$config->set(
    key      => 'bool.true2',
    value    => 'yes',
    as       => 'bool-or-int',
    filename => $config_filename
);
$config->set(
    key      => 'bool.false2',
    value    => 'no',
    as       => 'bool-or-int',
    filename => $config_filename
);
$config->set(
    key      => 'int.int1',
    value    => '0',
    as       => 'bool-or-int',
    filename => $config_filename
);
$config->set(
    key      => 'int.int2',
    value    => '1',
    as       => 'bool-or-int',
    filename => $config_filename
);
$config->set(
    key      => 'int.int3',
    value    => '-1',
    as       => 'bool-or-int',
    filename => $config_filename
);

is( slurp($config_filename), $expect, 'set bool-or-int' );

unlink $config_filename;

$config->set(
    key      => 'quote.leading',
    value    => ' test',
    filename => $config_filename
);
$config->set(
    key      => 'quote.ending',
    value    => 'test ',
    filename => $config_filename
);
$config->set(
    key      => 'quote.semicolon',
    value    => 'test;test',
    filename => $config_filename
);
$config->set(
    key      => 'quote.hash',
    value    => 'test#test',
    filename => $config_filename
);

$expect = <<'EOF'
[quote]
	leading = " test"
	ending = "test "
	semicolon = "test;test"
	hash = "test#test"
EOF
    ;

is( slurp($config_filename), $expect, 'quoting' );

throws_ok {
    $config->set(
        key      => "key.with\nnewline",
        value    => '123',
        filename => $config_filename
    );
}
qr/invalid key/, 'key with newline';

lives_ok {
    $config->set(
        key      => 'key.sub',
        value    => "value.with\nnewline",
        filename => $config_filename
    );
}
'value with newline';

burp(
    $config_filename,
    '[section]
	; comment \
	continued = cont\
inued
	noncont   = not continued ; \
	quotecont = "cont;\
inued"
'
);

$expect = <<'EOF'
section.continued=continued
section.noncont=not continued
section.quotecont=cont;inued
EOF
    ;

$config->load;
is( $config->dump, $expect, 'value continued on next line' );

# testing symlinked configuration
symlink File::Spec->catfile( $config_dir, 'notyet' ),
    File::Spec->catfile( $config_dir, 'myconfig' );

my $myconfig = TestConfig->new(
    confname => 'myconfig',
    tmpdir   => $config_dirname
);
$myconfig->set(
    key      => 'test.frotz',
    value    => 'nitfol',
    filename => File::Spec->catfile( $config_dir, 'myconfig' )
);
my $notyet = TestConfig->new(
    confname => 'notyet',
    tmpdir   => $config_dirname
);
$notyet->set(
    key      => 'test.xyzzy',
    value    => 'rezrov',
    filename => File::Spec->catfile( $config_dir, 'notyet' )
);
$notyet->load;
is( $notyet->get( key => 'test.frotz' ),
    'nitfol', 'can get 1st val from symlink' );
is( $notyet->get( key => 'test.xyzzy' ),
    'rezrov', 'can get 2nd val from symlink' );

### ADDITIONAL TESTS (not from the git test suite, just things that I didn't
### see tests for and think should be tested)

# weird yet valid edge case
burp(
    $config_filename,
    '# foo
[section] [section2] a = 1
b = 2
'
);

$config->load;

$expect = <<'EOF'
section2.a=1
section2.b=2
EOF
    ;

is( $config->dump, $expect, 'section headers are valid w/out newline' );

burp(
    $config_filename,
    '# foo
[section]
	b = off
	b = on
	exact = 0
	inexact = 01
	delicieux = true
'
);

$config->load;

is_deeply(
    scalar $config->get_regexp( key => 'x', as => 'bool' ),
    {   'section.exact'     => 0,
        'section.inexact'   => 1,
        'section.delicieux' => 1
    },
    'get_regexp casting works'
);

is_deeply(
    scalar $config->get_regexp( key => 'x', filter => '!0' ),
    { 'section.delicieux' => 'true' },
    'get_regexp filter works'
);

is_deeply( scalar $config->get_all( key => 'section.b', filter => 'f' ),
    ['off'], 'get_all filter works' );

is_deeply(
    scalar $config->get_all( key => 'section.b', as => 'bool' ),
    [ 0, 1 ],
    'get_all casting works'
);

# we don't strip the quotes on this, right?
$config->set(
    key => 'test.foo',
    value => '"ssh" for "kernel.org"',
    filename => $config_filename,
);
$config->load;
is( $config->get( key => 'test.foo' ), '"ssh" for "kernel.org"',
    "don't strip quotes contained in value" );

$config->set(
    key => 'test.foo',
    value => '1.542',
    filename => $config_filename,
);
$config->load;

# test difference between int/num casting, since git config doesn't
# do num
is( $config->get( key => 'test.foo', as => 'int' ), 1,
    'int casting truncates');
is( $config->get( key => 'test.foo', as => 'num' ), 1.542,
    'num casting doesn\'t truncate');
