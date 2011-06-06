#!/usr/bin/env perl -s
use strict;
use warnings;
use Config::Pit;
use Time::HiRes qw(sleep);
use URI qw(query_form);
use Path::Class qw(dir);
use File::Basename qw(basename);
use JSON;
use WWW::Pixiv::Download;
use Encode;
use Email::Send;
use Email::MIME::CreateHTML;
use Email::Send::Gmail;


our($t);

my $home = 'http://www.pixiv.net';
my $bkm  = "${home}/bookmark_new_illust.php";

my $parent_dir   = join '/', $ENV{HOME}, "Desktop/Image/Medium";
my $log_dir_name = '.log';
my $log_dir      = "${parent_dir}/${log_dir_name}";

my $page_start   = 1;
my $page_max     = 4;


my $config = pit_get('www.pixiv.net', require => {
    pixiv_id => '', pass => '',
});
die qq(! failed: can not get "pixiv_id" and "pass"\n) if ! %$config;

my $client = WWW::Pixiv::Download->new(
    pixiv_id => $config->{pixiv_id},
    pass     => $config->{pass},
    look     => $t ? 1 : 0,
);

my $res = $client->login;
my $ua  = $client->user_agent;


my @mail_bodys = ();
my %objects    = ();
for my $page ($page_start..$page_max) {
    my $uri = URI->new( $bkm );
    $uri->query_form( p => $page );

    $res = $ua->get($uri);
    die '! failed: '. $res->status_line . qq(: can not access ") . $uri->as_string . qq(" $!\n) if $res->is_error;

    my $html = $res->decoded_content;
    while ($html =~ m|<li class="image"><a href=".+?illust_id=(\d+?)"|g) {
        my $info = $client->prepare_download(my $illust_id = $1);
        my $dir  = join '/', $parent_dir, $info->{author}->{name}, $info->{title};
        my $file_name  = basename $info->{img_src};
        my $local_path = "${dir}/${file_name}";
        my $log        = "${log_dir}/${illust_id}";

        if (-e $log) {
            &send_gmail( join('', @mail_bodys), \%objects );
            #&unlinks(); # some term to save ? ex 10 days.
            warn qq(! "${local_path}" already exists.\n) if $t;
            exit 0;
        }

        &record_illust_id_and_informations($log, encode_json $info);

        &save_illust($dir, $illust_id);

        push @mail_bodys, &build_mail_body($illust_id, $info);
        $objects{ $illust_id } = $local_path;
        sleep 2.5;
    }
}
&send_gmail( join('', @mail_bodys), \%objects );
#&unlinks();
exit 0;

sub build_mail_body {
    my($illust_id, $info) = @_;

    my $author_name   = $info->{author}->{name};
    my $author_url    = $info->{author}->{url};
    my $title         = $info->{title};
    my $description   = $info->{description} || '';
    my $title_top_url = $info->{homepage_url};
(my $_mail_body_ =<<"MAILBODY") =~ tr/\n//d;
<div style="padding-bottom:3em;">
<div>
<h2 style="display:inline;">
<a href="${author_url}" target="_blank">${author_name}</a></h2> &gt;
 <h3 style="display:inline;"><a href="${title_top_url}" target="_blank">${title}</a></h3>
</div>
<a href="${title_top_url}" target="_blank"><img src="cid:${illust_id}" /></a>
<p>${description}</p>
</div>
MAILBODY
;

$_mail_body_;
}

sub save_illust {
    my($dir, $illust_id) = @_;
    unless (-e $dir) {
        warn qq(--> directory not found, "${dir}"\n) if $t;
        dir($dir)->mkpath;
        warn qq(--> success: mkdir "${dir}"\n) if -e $dir and $t;
    }
    
    $client->download($illust_id ,{
        mode      => 'm',
        path_name => $dir,
    });
}

sub record_illust_id_and_informations {
    my($log, $inf_txt) = @_;
    unless (-e $log_dir) {
        warn qq(--> directory not found, "${log_dir}" to save log\n) if $t;
        dir($log_dir)->mkpath;
        warn qq(--> success: mkdir "${log_dir}"\n) if -e $log_dir and $t; 
    }

    open my $fh, '>', $log or die qq(can not open "${log}" $!\n);
    flock $fh, 2;
    print $fh "$inf_txt\n";
    close $fh;
}

sub send_gmail {
    my($html, $objects) = @_;
    
    return undef if $html eq '';

    my $email = Email::MIME->create_html(
        header => [
            From    => 'ishiduca@gmail.com',
            To      => 'ishiduca@gmail.com',
            Subject => encode('MIME-Header-ISO_2022_JP', "pixiv favorite update"),
        ],
        body_attributes => {
            content_type => 'text/html',
            charset      => 'UTF-8',
        },
        body       => qq(<!doctype html><body>${html}</body>),
        embed      => 0,
        inline_css => 0,
        objects    => $objects,
    );

    my $sender = Email::Send->new({
        mailer       => 'Gmail',
        mailer_args  =>[
            username => 'ishiduca@gmail.com',
            password => 'quav0la',
        ],
    });

    eval { $sender->send($email); };
    die "Error sending email: $@" if $@;

	warn qq(send mail...\n) if $t;
}
