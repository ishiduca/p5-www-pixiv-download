#!/usr/bin/env perl -s
use strict;
use warnings;
use Config::Pit;
use WWW::Pixiv::Download;
use Path::Class;

my $usage = "usage: $0 illust_id\n";
our($h);

$h    and warn $usage and exit 0;
@ARGV or  die $usage;

my $config = pit_get('www.pixiv.net', require =>{
    pixiv_id => 'pixiv_id', pass => 'pass',
});
die qq(! failed: pit_get\n) if ! %$config; 

my $client = WWW::Pixiv::Download->new(
    pixiv_id   => $config->{pixiv_id},
    pass       => $config->{pass},
    #over_write => 1,
    look       => 1,
);

for my $illust_id (@ARGV) {
    &download( $illust_id );
}

exit 0;

sub download {
    my $illust_id = shift;

    my $info = $client->prepare_download($illust_id);
    my $path_name = join '/',
        $ENV{HOME}, 'Desktop/Image', $info->{author}->{name}, $info->{title};

    unless (-e $path_name) {
        warn qq(--> not found directory "${path_name}"\n);
        dir($path_name)->mkpath;
        warn qq(--> create new direcroty "${path_name}"\n);
    } elsif (-f $path_name) {
        die qq(! failed: "${path_name}" already exists.\n);
    }

    my %args = ( path_name => $path_name );

    $client->download($illust_id, \%args);

    $args{mode} = 'm';
    $client->download($illust_id, \%args);
}
