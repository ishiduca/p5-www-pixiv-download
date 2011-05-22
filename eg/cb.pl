#!/usr/bin/env perl -s
use strict;
use warnings;
use WWW::Pixiv::Download;
use Config::Pit;

my $usage = "usage: $0 illust_id\n";
our($h);

$h and warn $usage and exit 0;
@ARGV or die $usage;

my $illust_id = $ARGV[0];
my $config = pit_get('www.pixiv.net', require => {
    pixiv_id => '', pass => '',
});
die qq(! failed: pit_get\n) if ! %$config;

my $client = WWW::Pixiv::Download->new(
    pixiv_id => $config->{pixiv_id},
    pass     => $config->{pass},
    look     => 1,
);

$client->download($illust_id, {
    mode => 'medium',
    cb   => \&cb
});

my $wfh;
sub cb {
    my ($chunk, $res, $proto) = @_;

    unless ($wfh) {
        open $wfh, '>', "${illust_id}.jpg" or die "${illust_id}.jpg $!\n";
        binmode $wfh;
    }

    print $wfh $chunk;
}
