#!/usr/bin/perl

use strict;
use warnings;
use lib 'lib';
use Config::GitLike::Cascaded;

my $config = Config::GitLike::Cascaded->new(confname => "mytest");
$config->load;

$config->dump;
