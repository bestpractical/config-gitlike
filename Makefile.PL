use inc::Module::Install;
license('perl');
version_from('lib/Config/GitLike.pm');
all_from('lib/Config/GitLike.pm');


requires 'Any::Moose';
build_requires 'Test::More';
build_requires 'Test::Exception';
build_requires 'File::Spec';
build_requires 'File::Temp';
extra_tests();
sign();
WriteAll();
