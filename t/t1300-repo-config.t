use strict;
use warnings;

use File::Copy;
use Test::More tests => 65;
use Test::Exception;
use File::Spec;
use File::Temp;
use lib 't/lib';
use TestConfig;

sub slurp {
    my $file = shift;
    local( $/ ) ;
    open( my $fh, $file ) or die "Unable to open file ${file}: $!";
    return <$fh>;
}

sub burp {
    my $file_name = shift;
    open( my $fh, ">$file_name" ) ||
        die "can't open ${file_name}: $!";
    print $fh @_;
}

# create an empty test directory in /tmp
my $config_dir = File::Temp->newdir(CLEANUP => !$ENV{CONFIG_GITLIKE_DEBUG});
my $config_dirname = $config_dir->dirname;
my $config_filename = File::Spec->catfile($config_dirname, 'config');

diag "config file is: $config_filename";

my $config = TestConfig->new(confname => 'config', tmpdir => $config_dirname);
$config->load;

diag('Test git config in different settings');

$config->set(key => 'core.penguin', value => 'little blue', filename =>
    $config_filename);

my $expect = <<'EOF'
[core]
	penguin = little blue
EOF
;

is(slurp($config_filename), $expect, 'initial');

$config->set(key => 'Core.Movie', value => 'BadPhysics', filename =>
    $config_filename);

$expect = <<'EOF'
[core]
	penguin = little blue
	Movie = BadPhysics
EOF
;

is(slurp($config_filename), $expect, 'mixed case');

$config->set(key => 'Cores.WhatEver', value => 'Second', filename =>
    $config_filename);

$expect = <<'EOF'
[core]
	penguin = little blue
	Movie = BadPhysics
[Cores]
	WhatEver = Second
EOF
;

is(slurp($config_filename), $expect, 'similar section');

$config->set(key => 'CORE.UPPERCASE', value => 'true', filename =>
    $config_filename);

$expect = <<'EOF'
[core]
	penguin = little blue
	Movie = BadPhysics
	UPPERCASE = true
[Cores]
	WhatEver = Second
EOF
;

is(slurp($config_filename), $expect, 'similar section');

# set returns nothing on success
lives_ok { $config->set(key => 'core.penguin', value => 'kingpin', filter => qr/!blue/,
    filename => $config_filename) } 'replace with non-match';

lives_ok { $config->set(key => 'core.penguin', value => 'very blue', filter =>
    qr/!kingpin/, filename => $config_filename) } 'replace with non-match';

TODO: {
    local $TODO = 'Multiple values are not yet implemented.';

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

    is(slurp($config_filename), $expect, 'non-match result');
}

burp($config_filename,
'[alpha]
bar = foo
[beta]
baz = multiple \
lines
');

lives_ok { $config->set(key => 'beta.baz', filename => $config_filename) }
    'unset with cont. lines';

$expect = <<'EOF'
[alpha]
bar = foo
[beta]
EOF
;

is(slurp($config_filename), $expect, 'unset with cont. lines is correct');

burp($config_filename,
'[beta] ; silly comment # another comment
noIndent= sillyValue ; \'nother silly comment

		; comment
haha = hello
	haha = bello
[nextSection] noNewline = ouch
');
# my $config2_filename = File::Spec->catfile($config_dir, '.config2');
#
# copy($config_filename, $config2_filename) or die "File cannot be copied: $!";

# XXX TODO unset-all not implemented yet in Config::GitLike interface
# test_expect_success 'multiple unset' \
# 	'git config --unset-all beta.haha'
#
# $expect = <<'EOF'
# [beta] ; silly comment # another comment
# noIndent= sillyValue ; 'nother silly comment
#
# 		; comment
# [nextSection] noNewline = ouch
# EOF
#
#
# is(slurp($config_filename), $expect, 'multiple unset is correct');

# copy($config2_filename, $config_filename) or die "File cannot be copied: $!";

# XXX TODO I don't think replace/replace-all works either (what's it supposed to do?)
# test_expect_success '--replace-all missing value' '
# 	test_must_fail git config --replace-all beta.haha &&
# 	test_cmp .git/config2 .git/config
# '
#
# unlink $config2_filename;
#
# test_expect_success '--replace-all' \
# 	'git config --replace-all beta.haha gamma'
#
# $expect = <<'EOF'
# [beta] ; silly comment # another comment
# noIndent= sillyValue ; 'nother silly comment
#
# 		; comment
# 	haha = gamma
# [nextSection] noNewline = ouch
# EOF
#
# is(slurp($config_filename), $expect, 'all replaced');

# XXX remove this burp after fixing the replace/unset all stuff above (just
# using it to bootstrap the rest of the tests)
burp($config_filename,
'[beta] ; silly comment # another comment
noIndent= sillyValue ; \'nother silly comment

		; comment
	haha = gamma
[nextSection] noNewline = ouch
');

$config->set(key => 'beta.haha', value => 'alpha', filename => $config_filename);

$expect = <<'EOF'
[beta] ; silly comment # another comment
noIndent= sillyValue ; 'nother silly comment

		; comment
	haha = alpha
[nextSection] noNewline = ouch
EOF
;

is(slurp($config_filename), $expect, 'really mean test');

TODO: {
    local $TODO = "cannot handle replacing value after section w/o newline yet";

    $config->set(key => 'nextsection.nonewline', value => 'wow', filename => $config_filename);

    $expect = <<'EOF'
[beta] ; silly comment # another comment
noIndent= sillyValue ; 'nother silly comment

		; comment
	haha = alpha
[nextSection]
	nonewline = wow
EOF
    ;

    is(slurp($config_filename), $expect, 'really really mean test');
}

# XXX remove this burp after un-TODOing the above block
burp($config_filename,
'[beta] ; silly comment # another comment
noIndent= sillyValue ; \'nother silly comment

		; comment
	haha = alpha
[nextSection]
	nonewline = wow
');

$config->load;
is($config->get(key => 'beta.haha'), 'alpha', 'get value');

# unset beta.haha (unset accomplished by value = undef)
$config->set(key => 'beta.haha', filename => $config_filename);

$expect = <<'EOF'
[beta] ; silly comment # another comment
noIndent= sillyValue ; 'nother silly comment

		; comment
[nextSection]
	nonewline = wow
EOF
;

is(slurp($config_filename), $expect, 'unset');

TODO: {
    local $TODO = "multivar not yet implemented";

    $config->set(key => 'nextsection.NoNewLine', value => 'wow2 for me', filter =>
        qr/for me$/, filename => $config_filename);

    $expect = <<'EOF'
[beta] ; silly comment # another comment
noIndent= sillyValue ; 'nother silly comment

		; comment
[nextSection]
	nonewline = wow
	NoNewLine = wow2 for me
EOF
    ;

    is(slurp($config_filename), $expect, 'multivar');

    $config->load;
    lives_ok { $config->get(key => 'nextsection.nonewline', filter => qr/!for/) }
        'non-match';

    is($config->get(key => 'nextsection.nonewline', filter => qr/!for/), 'wow',
        'non-match value');

    # must use get_all to get multiple values
    throws_ok { $config->get( key => 'nextsection.nonewline' ) }
        qr/multiple values/i, 'ambiguous get';

    is($config->get_all(key => 'nextsection.nonewline'), ['wow', 'wow2 for me'],
        'get multivar');

    $config->set(key => 'nextsection.nonewline', value => 'wow3', filter => qr/wow$/,
        filename => $config_filename);

    $expect = <<'EOF'
noIndent= sillyValue ; 'nother silly comment

        ; comment
[nextSection]
    nonewline = wow3
    NoNewLine = wow2 for me
EOF
    ;

    is(slurp($config_filename), $expect, 'multivar replace');

    $config->load;
    throws_ok { $config->set(key => 'nextsection.nonewline',
            filename => $config_filename) }
        qr/ambiguous unset/i, 'ambiguous unset';

    throws_ok { $config->set(key => 'somesection.nonewline',
            filename => $config_filename) }
        qr/No occurrence of somesection.nonewline found to unset/i,
        'invalid unset';

    lives_ok { $config->set(key => 'nextsection.nonewline',
            filter => qr/wow3$/, filename => $config_filename) }
        "multivar unset doesn't crash";

    $expect = <<'EOF'
noIndent= sillyValue ; 'nother silly comment

		; comment
[nextSection]
	NoNewLine = wow2 for me
EOF
    ;

    is(slurp($config_filename), $expect, 'multivar unset');
}

throws_ok { $config->set(key => 'inval.2key', value => 'blabla', filename =>
        $config_filename) } qr/invalid key/i, 'invalid key';

lives_ok { $config->set(key => '123456.a123', value => '987', filename =>
        $config_filename) } 'correct key';

lives_ok { $config->set(key => 'Version.1.2.3eX.Alpha', value => 'beta', filename =>
        $config_filename) } 'correct key';

$expect = <<'EOF'
[beta] ; silly comment # another comment
noIndent= sillyValue ; 'nother silly comment

		; comment
[nextSection]
	NoNewLine = wow2 for me
[123456]
	a123 = 987
[Version "1.2.3eX"]
	Alpha = beta
EOF
;

is(slurp($config_filename), $expect, 'hierarchical section value');

$expect = <<'EOF'
123456.a123=987
beta.noindent=sillyValue
nextsection.nonewline=wow2 for me
version.1.2.3eX.alpha=beta
EOF
;

$config->load;
is($config->dump, $expect, 'working dump');

TODO: {
    local $TODO = 'get_regexp is not implemented';

    $expect = <<'EOF'
beta.noindent sillyValue
nextsection.nonewline wow2 for me
EOF
    ;

    lives_and { is($config->get_regexp( 'in' ), $expect) } '--get-regexp';
}

TODO: {
    local $TODO = 'cannot set multiple values yet';

    $config->set(key => 'nextsection.nonewline', value => 'wow4 for you',
        filename => $config_filename);

    $expect = <<'EOF'
wow2 for me
wow4 for you
EOF
    ;

    $config->load;
    is($config->get_all(key => 'nextsection.nonewline'), $expect, '--add');
}

burp($config_filename,
'[novalue]
	variable
[emptyvalue]
	variable =
');

$config->load;
lives_and { is($config->get( key => 'novalue.variable', filter => qr/^$/ ),
        undef) } 'get variable with no value';

lives_and { is($config->get( key => 'emptyvalue.variable', filter => qr/^$/ ),
    '') } 'get variable with empty value';

TODO: {
    local $TODO = "get_regexp is not implemented";
    # TODO perhaps regexps could just be supported by the get interface

    lives_and { is($config->get_regexp( qr/novalue/ ), '') }
        'get_regexp variable with no value';

    lives_and { is($config->get_regexp( qr/novalue/ ), '') }
        'get_regexp variable with empty value';
}

# should evaluate to a true value
ok($config->get( key => 'novalue.variable', as => 'bool' ),
    'get bool variable with no value');

# should evaluate to a false value
ok(!$config->get( key => 'emptyvalue.variable', as => 'bool' ),
    'get bool variable with empty value');

# testing alternate subsection notation
burp($config_filename,
'[a.b]
	c = d
');

$config->set(key => 'a.x', value => 'y', filename => $config_filename);

$expect = <<'EOF'
[a.b]
	c = d
[a]
	x = y
EOF
;

is(slurp($config_filename), $expect, 'new section is partial match of another');

$config->set(key => 'b.x', value => 'y', filename => $config_filename);
$config->set(key => 'a.b', value => 'c', filename => $config_filename);
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

is(slurp($config_filename), $expect, 'new variable inserts into proper section');

TODO: {
    local $TODO = 'rename_section is not yet implemented';

    lives_ok { $config->rename_section( from => 'branch.eins', to =>
            'branch.zwei', filename => $config_filename ) }
        'rename_section lives';

    $expect = <<'EOF'
[branch "zwei"]
    x = 1
[branch "zwei"]
    y = 1
    [branch "1 234 blabl/a"]
weird
EOF
    ;
    is(slurp($config_filename), $expect, 'rename succeeded');

    throws_ok { $config->rename_section( from => 'branch."world domination"', to =>
        'branch.drei', filename => $config_filename ) } \
        qr/rename non-existing section/, 'rename non-existing section';

    is(slurp($config_filename), $expect,
        'rename non-existing section changes nothing');

    lives_ok { $config->rename_section( from => 'branch."1 234 blaba/a"', to =>
            'branch.drei', filename => $config_filename ) }
        'rename another section';

    $expect = <<'EOF'
[branch "zwei"]
	x = 1
[branch "zwei"]
	y = 1
[branch "drei"]
weird
EOF
    ;

    is(slurp($config_filename), $expect, 'rename succeeded');
}

TODO: {
    local $TODO = 'remove section is not yet implemented';

    burp($config_filename,
'[branch "zwei"] a = 1 [branch "vier"]
');

    lives_ok { $config->remove_section( section => 'branch.zwei',
            filename => $config_filename ) } 'remove section';

    $expect = <<'EOF'
[branch "drei"]
weird
EOF
    ;

    is(slurp($config_filename), $expect, 'section was removed properly');

}

unlink $config_filename;

$expect = <<'EOF'
[gitcvs]
	enabled = true
	dbname = %Ggitcvs2.%a.%m.sqlite
[gitcvs "ext"]
	dbname = %Ggitcvs1.%a.%m.sqlite
EOF
;

$config->set( key => 'gitcvs.enabled', value => 'true',
    filename => $config_filename );
$config->set( key => 'gitcvs.ext.dbname', value => '%Ggitcvs1.%a.%m.sqlite',
    filename => $config_filename);
$config->set( key => 'gitcvs.dbname', value => '%Ggitcvs2.%a.%m.sqlite',
    filename => $config_filename );
is(slurp($config_filename), $expect, 'section ending');

# testing int casting

$config->set( key => 'kilo.gram', value => '1k', filename => $config_filename );
$config->set( key => 'mega.ton', value => '1m', filename => $config_filename );
$config->load;
is($config->get( key => 'kilo.gram', as => 'int' ), 1024,
    'numbers: int k interp');
is($config->get( key => 'mega.ton', as => 'int' ), 1048576,
    'numbers: int m interp');

# units that aren't k/m/g should throw an error

$config->set( key => 'aninvalid.unit', value => '1auto', filename => $config_filename );
$config->load;
throws_ok { $config->get( key => 'aninvalid.unit', as => 'int' ) }
    qr/invalid unit/i, 'invalid unit';

my %pairs = qw( true1 01 true2 -1 true3 YeS true4 true false1 000 false3 nO false4 FALSE);
$pairs{false2} = '';

for my $key (keys %pairs) {
    $config->set( key => "bool.$key", value => $pairs{$key},
        filename => $config_filename );
}
$config->load;

my @results = ();

for my $i (1..4) {
    push(@results, $config->get( key => "bool.true$i", as => 'bool' ) eq 1,
        $config->get( key => "bool.false$i", as => 'bool' ) eq 1);
}

my $b = 1;

@results = reverse @results;
while (@results) {
    if ($b) {
        ok(pop @results, 'bool');
    } else {
        ok(!pop @results, 'bool');
    }
    $b = !$b;
}

$config->set( key => 'bool.nobool', value => 'foobar',
        filename => $config_filename );
$config->load;
throws_ok { $config->get( key => 'bool.nobool', as => 'bool' ) }
    qr/invalid bool/i, 'invalid bool (get)';

# TODO currently the interface doesn't support casting for set. does that make sense?
# test_expect_success 'invalid bool (set)' '
#
# 	test_must_fail git config --bool bool.nobool foobar'
#
# unlink $config_filename;
#
# $expect = <<'EOF'
# [bool]
# 	true1 = true
# 	true2 = true
# 	true3 = true
# 	true4 = true
# 	false1 = false
# 	false2 = false
# 	false3 = false
# 	false4 = false
# EOF
#
# test_expect_success 'set --bool' '
#
# 	git config --bool bool.true1 01 &&
# 	git config --bool bool.true2 -1 &&
# 	git config --bool bool.true3 YeS &&
# 	git config --bool bool.true4 true &&
# 	git config --bool bool.false1 000 &&
# 	git config --bool bool.false2 "" &&
# 	git config --bool bool.false3 nO &&
# 	git config --bool bool.false4 FALSE &&
# 	cmp expect .git/config'
#
# unlink $config_filename;
#
# $expect = <<'EOF'
# [int]
# 	val1 = 1
# 	val2 = -1
# 	val3 = 5242880
# EOF
#
# test_expect_success 'set --int' '
#
# 	git config --int int.val1 01 &&
# 	git config --int int.val2 -1 &&
# 	git config --int int.val3 5m &&
# 	cmp expect .git/config'
#
# unlink $config_filename;
#
# $expect = <<'EOF'
# [bool]
# 	true1 = true
# 	true2 = true
# 	false1 = false
# 	false2 = false
# [int]
# 	int1 = 0
# 	int2 = 1
# 	int3 = -1
# EOF
#
# TODO interface doesn't support bool-or-int (does it want to?)
# test_expect_success 'get --bool-or-int' '
# 	(
# 		echo "[bool]"
# 		echo true1
# 		echo true2 = true
# 		echo false = false
# 		echo "[int]"
# 		echo int1 = 0
# 		echo int2 = 1
# 		echo int3 = -1
# 	) >>.git/config &&
# 	test $(git config --bool-or-int bool.true1) = true &&
# 	test $(git config --bool-or-int bool.true2) = true &&
# 	test $(git config --bool-or-int bool.false) = false &&
# 	test $(git config --bool-or-int int.int1) = 0 &&
# 	test $(git config --bool-or-int int.int2) = 1 &&
# 	test $(git config --bool-or-int int.int3) = -1
#
# '
#
# unlink $config_filename;
# $expect = <<'EOF'
# [bool]
# 	true1 = true
# 	false1 = false
# 	true2 = true
# 	false2 = false
# [int]
# 	int1 = 0
# 	int2 = 1
# 	int3 = -1
# EOF
#
# test_expect_success 'set --bool-or-int' '
# 	git config --bool-or-int bool.true1 true &&
# 	git config --bool-or-int bool.false1 false &&
# 	git config --bool-or-int bool.true2 yes &&
# 	git config --bool-or-int bool.false2 no &&
# 	git config --bool-or-int int.int1 0 &&
# 	git config --bool-or-int int.int2 1 &&
# 	git config --bool-or-int int.int3 -1 &&
# 	test_cmp expect .git/config
# '

unlink $config_filename;

$config->set(key => 'quote.leading', value => ' test', filename =>
    $config_filename);
$config->set(key => 'quote.ending', value => 'test ', filename =>
    $config_filename);
$config->set(key => 'quote.semicolon', value => 'test;test', filename =>
    $config_filename);
$config->set(key => 'quote.hash', value => 'test#test', filename =>
    $config_filename);

$expect = <<'EOF'
[quote]
	leading = " test"
	ending = "test "
	semicolon = "test;test"
	hash = "test#test"
EOF
;

is(slurp($config_filename), $expect, 'quoting');

throws_ok { $config->set( key => "key.with\nnewline", value => '123',
        filename => $config_filename ) } qr/invalid key/, 'key with newline';

lives_ok { $config->set( key => 'key.sub', value => "value.with\nnewline",
        filename => $config_filename ) } 'value with newline';

burp($config_filename,
'[section]
	; comment \
	continued = cont\
inued
	noncont   = not continued ; \
	quotecont = "cont;\
inued"
');

$expect = <<'EOF'
section.continued=continued
section.noncont=not continued
section.quotecont=cont;inued
EOF
;

$config->load;
is($config->dump, $expect, 'value continued on next line');

# TODO NUL-byte termination is not supported by the current interface and I'm
# not sure it would be useful to do so
# burp($config_filename,
# '[section "sub=section"]
# 	val1 = foo=bar
# 	val2 = foo\nbar
# 	val3 = \n\n
# 	val4 =
# 	val5
# ');

# $expect = <<'EOF'
# section.sub=section.val1
# foo=barQsection.sub=section.val2
# foo
# barQsection.sub=section.val3
#
#
# Qsection.sub=section.val4
# Qsection.sub=section.val5Q
# EOF
#
#
# -- kill the tests or implement the null flag
#git config --null --list | perl -pe 'y/\000/Q/' > result
#echo >>result
#
#is(slurp($result), $expect, '--null --list');
#
#git config --null --get-regexp 'val[0-9]' | perl -pe 'y/\000/Q/' > result
#echo >>result
#
#is(slurp($result), $expect, '--null --get-regexp');

# testing symlinked configuration
symlink File::Spec->catfile($config_dir, 'notyet'),
    File::Spec->catfile($config_dir, 'myconfig');

my $myconfig = TestConfig->new(confname => 'myconfig',
    tmpdir => $config_dirname);
$myconfig->set( key => 'test.frotz', value => 'nitfol',
    filename => File::Spec->catfile($config_dir, 'myconfig'));
my $notyet = TestConfig->new(confname => 'notyet',
    tmpdir => $config_dirname);
$notyet->set ( key => 'test.xyzzy', value => 'rezrov',
    filename => File::Spec->catfile($config_dir, 'notyet'));
$notyet->load;
is($notyet->get(key => 'test.frotz'), 'nitfol',
    'can get 1st val from symlink');
is($notyet->get(key => 'test.xyzzy'), 'rezrov',
    'can get 2nd val from symlink');
