use inc::Module::Install;
name('Config-GitLike');
all_from('lib/Config/GitLike.pm');
repository('http://github.com/bestpractical/config-gitlike');

perl_version '5.008';
requires 'Any::Moose';
build_requires 'Test::More';
build_requires 'Test::Exception';
build_requires 'File::Spec';
build_requires 'File::Temp';
extra_tests();
sign();
WriteAll();
