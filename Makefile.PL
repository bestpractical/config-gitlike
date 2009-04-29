use inc::Module::Install;
license('perl');
all_from('lib/Config/Gitlike.pm');


requires 'Any::Moose';
requires 'Regexp::Common';
requires 'File::HomeDir';

sign();
WriteAll();
