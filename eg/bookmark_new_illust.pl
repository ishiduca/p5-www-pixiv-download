#!/usr/bin/env perl
use strict;
use warnings;
use Config::Pit;
use Data::Dumper;
use URI;
use Path::Class;
use File::Basename;
use WWW::Pixiv::Download;

my $home = 'http://www.pixiv.net';
my $bkm  = "${home}/bookmark_new_illust.php";

my $parent_dir = join '/', $ENV{HOME}, "Desktop/Image/Medium";
my $page_start = 1;
my $page_max   = 2;

my $config = pit_get('www.pixiv.net', require => {
    pixiv_id => '', pass => '',
});
die qq(! failed: can not get "pixiv_id" and "pass"\n) if ! %$config;

my $client = WWW::Pixiv::Download->new(
    pixiv_id => $config->{pixiv_id},
    pass     => $config->{pass},
    look     => 1,
);

my $res = $client->login;
my $ua  = $client->{user_agent};

for my $page ($page_start..$page_max) {
    my $uri = URI->new( $bkm );
    $uri->query_form(
        p => $page,
    );

    $res = $ua->get($uri,
        'Referer' => $res->base,
    );
    die qq(! failed: can not access "${bkm}" $!\n) if $res->is_error;
    warn $res->base . " now\n";

    my $html = $res->decoded_content;
    while ($html =~ m|<li class="image"><a href=".+?illust_id=(\d+?)"|g) {
        my $info = $client->prepare_download($1);
        my $dir  = join '/', $parent_dir, $info->{author_name}, $info->{title};
        my $img_src    = $info->{img_src};
        my $file_name  = basename $img_src;
        my $local_path = "${dir}/${file_name}";

        die qq(! "${local_path}" already exists.\n) if -e $local_path;

        unless (-e $dir) {
            warn qq(--> not found directory "${dir}"\n);
            dir($dir)->mkpath;
            warn qq(--> success: mkdir "${dir}"\n) if -e $dir;
        }
        
        $client->download($1 ,{
            mode => 'm',
            path_name => $dir,
        });
    }
}

exit 0;