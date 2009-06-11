use inc::Module::Install;
license('perl');
version('1.0');
all_from('lib/Config/GitLike.pm');


requires 'Any::Moose';
requires 'Regexp::Common';
requires 'File::HomeDir';
build_requires 'Test::More';
build_requires 'Test::Exception';
build_requires 'File::Spec';
build_requires 'File::Temp';
extra_tests();
sign();
WriteAll();
