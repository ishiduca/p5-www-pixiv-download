#!/usr/bin/env perl
use strict;
use warnings;
use Cache::Memcached::Fast;
use MIME::Base64;
use Config::Pit;
use WWW::Pixiv::Download;

@ARGV or die qq(usage: $0 illust_id\n);
my $illust_id = $ARGV[0];

my $cache = Cache::Memcached::Fast->new({
    servers => [ "localhost:11211" ],
});

my $config = pit_get('www.pixiv.net', require => {
    pixiv_id => '', pass => '',
});
die qq(! failed: can not pit_get\n) if ! %$config;

my $client = WWW::Pixiv::Download->new(
    pixiv_id   => $config->{pixiv_id},
    pass       => $config->{pass},
    look       => 1,
    over_write => 1,
);


my($buf, $stuffix);
$client->download($illust_id, {
    mode => 'm',
    cb   => sub {
        my($chunk, $res, $proto) = @_;
        unless ($stuffix) {
            $stuffix = $res->header('Content-Type');
            $stuffix =~ s|image/||;
        }
        local $/;
        $buf .= $chunk;
    },
});

$cache->set($illust_id,  encode_base64 $buf) or die $!;

test_print( $illust_id, "${illust_id}.${stuffix}");

sub test_print {
    my($illust_id, $filed_path) = @_;

    open my $fh, '>', $filed_path or die $!;
    binmode $fh;
    print $fh decode_base64 $cache->get($illust_id);
    close $fh;

    $cache->delete($illust_id);
}
