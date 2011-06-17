use strict;
use warnings;
use inc::Module::Install;

perl_version ('5.005');

all_from 'lib/WWW/Pixiv/Download.pm';

requires 'LWP::UserAgent';
requires 'Web::Scraper';
requires 'URI';
requires 'Sub::Retry';
requires 'File::Basename';

test_requires 'Test::More';

auto_include_deps;

tests_recursive;

WriteAll;
