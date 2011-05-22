package WWW::Pixiv::Download;

use strict;
use Carp;
use LWP::UserAgent;
use Web::Scraper;
use URI;
use File::Basename;

my $home   = 'http://www.pixiv.net';
my $login  = "${home}/login.php";
my $index  = "${home}/index.php";
my $mypage = "${home}/mypage.php";
my $illust_top = "${home}/member_illust.php";

my $default_over_write = 0; # over write ok

sub new {
    my $class = shift;
    my %args  = @_;
    my $ua = LWP::UserAgent->new( cookie_jar => {} );
    push @{ $ua->requests_redirectable }, 'POST';
    $args{user_agent} = $ua;
    $args{over_write} ||= $default_over_write;
    bless \%args, $class;
}

sub _save_content {
    my($self, $img_src, $args) = @_;

    if (ref $args->{cb} eq 'CODE') {
        my $res = $self->{user_agent}->get($img_src,
            'Referer'     => $self->{referer},
            ':content_cb' => $args->{cb},
        );
        Carp::croak '! failed: download error '. $res->status_line . "\n" if $res->is_error;
    } else {
        my $path_name = $args->{path_name} || './';
        my $file_name = $args->{file_name} || basename $img_src;
        $path_name =~ m|/$| or $path_name = "$path_name/";
        $file_name =~ s/\?.*//;
        my $file_path = "${path_name}${file_name}";
        if (-e $file_path && ! $self->{over_write}) {
            warn qq(--> no download: "${file_path}" already exists.\n);
        } else {
            my $res = $self->{user_agent}->get($img_src,
                'Referer'       => $self->{referer},
                ':content_file' => $file_path,
            );
            Carp::croak '! failed: download error '. $res->status_line . "\n" if $res->is_error;
            warn qq(--> success: download ") . $res->base . qq(" ==> ") . $file_path . qq("\n) if $self->{look};
        }
    }
}

sub download {
    my($self, $illust_id, $args) = @_;

    my $scraped_response = $self->{scraped_response};
    unless ($self->{referer} =~ /$illust_id/ and
        $scraped_response->{to_bigImg_href} =~ /$illust_id/ and
        $scraped_response->{img_src}        =~ /$illust_id/) {
        $scraped_response = $self->prepare_download($illust_id);
    }

    if ($args->{mode} eq 'medium' or $args->{mode} eq 'm') {
        $self->_save_content($scraped_response->{img_src}, $args);
    } else {
        my $uri = "${home}/" . $scraped_response->{to_bigImg_href};
        my $res = $self->{user_agent}->get( $uri, 'Referer' => $self->{referer});
        Carp::croak qq(! failed: ) . $res->status_line . qq(\n) if $res->is_error;
        $self->{referer} = $res->base;
        warn qq(--> success: access ") . $self->{referer} . qq("\n) if $self->{look};

        if ($self->{referer} =~ /mode=big/) {
            my $scraper = scraper {
                process '//img[1]', 'img_src' => '@src';
            };
            $self->_save_content($scraper->scrape($res->decoded_content)->{img_src}, $args);
        } else {
            my $content = $res->decoded_content;
            while ($content =~ m!unshift\('(http://([^\']+)?)'!g) {
				delete $args->{file_name}; # over write off
                $self->_save_content($1, $args);
            }
        }
    }

    $self;
}

sub prepare_download {
    my($self, $illust_id) = @_;

    Carp::croak qq(failed: not found "illust_id".\n) unless $illust_id;

    $self->login if $self->{logged_in} ne '1';

    my $uri = URI->new( $illust_top );
    $uri->query_form(
        mode => 'medium',
        illust_id => $illust_id,
    );

    my $res = $self->{user_agent}->get($uri, 'Referer' => $self->{referer});
    Carp::croak qq(! failed: can not access "). $uri . '" '
        . $res->status_line . "\n" unless $res->is_success;
    Carp::croak qq(! failed: referer error ?\n) if $uri ne URI->new($res->base);

    $self->{referer} = $res->base;
    warn qq(--> success: access "). $self->{referer}. qq("\n) if $self->{look};

    my $scraper = scraper {
        process '//h3[1]', 'title' => 'TEXT';
        process '//p[@class="works_caption"]', 'description' => 'HTML';
        process '//a[@class="avatar_m"]', 'author_name' => '@title';
        process '//a[@class="avatar_m"]', 'author_url'  => '@href';
        process '//div[@class="works_display"]/a[1]', 'to_bigImg_href' => '@href';
        process '//div[@class="works_display"]/a[1]/img[1]', 'img_src' => '@src';
    };

    $self->{scraped_response} = $scraper->scrape($res->decoded_content);
}

sub login {
    my $self = shift;
    my %args = @_;

    $self->{pixiv_id} = $args{pixiv_id} if $args{pixiv_id};
    $self->{pass}     = $args{pass}     if $args{pass};

    Carp::croak qq(! failed: not found "pixiv_id".\n) unless $self->{pixiv_id};
    Carp::croak qq(! failed: not found "pass".\n)     unless $self->{pass};

    my $res = $self->{user_agent}->post($login, {
        pixiv_id => $self->{pixiv_id},
        pass     => $self->{pass},
        mode     => 'login',
    });

    if ($res->is_error) {
        $self->{logged_in} = '0';
        Carp::croak qq(! failed: login error). $res->status_line . "\n";
    } elsif ($res->base ne $mypage) {
        $self->{logged_in} = '0';
        Carp::croak qq(! failed: wrong "pixiv_id" or "password". ) . $res->base . " now\n";
    }

    $self->{logged_in} = '1';
    $self->{referer}   = $res->base;

    warn qq(--> success: logged in "). $self->{referer}. qq("\n) if $self->{look};

    $res;
}

1;
