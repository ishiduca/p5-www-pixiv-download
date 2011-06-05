package WWW::Pixiv::Download;

use strict;
use Carp;
use LWP::UserAgent;
use Web::Scraper;
use URI;
use File::Basename;

our $VERSION = '0.0.5';

my $home   = 'http://www.pixiv.net';
my $login  = "${home}/login.php";
my $index  = "${home}/index.php";
my $mypage = "${home}/mypage.php";
my $illust_top = "${home}/member_illust.php";

my $default_over_write = 0; # can not over write

sub new {
    my $class = shift;
    my %args  = @_;
    $args{user_agent} ||= &{sub {
        my $ua = LWP::UserAgent->new( cookie_jar => {} );
        push @{ $ua->requests_redirectable }, 'POST';
        $ua->add_handler(request_prepare => sub {
            my($request, $ua, $h) = @_;
            $request->header('Referer' => $args{referer}) if $args{referer};
        });
        $ua;
    }};
    $args{over_write} ||= $default_over_write;
    bless \%args, $class;
}

sub _default_cb {
    my($self, $file_path) = @_;

    if (-e $file_path && ! $self->{over_write}) {
        warn qq(--> no download: "${file_path}" already exists.\n) if $self->{look};
        return;
    }
    open my $fh, '>', $file_path or die qq(! failed: can not open "${file_path}" $!\n);
    binmode $fh;

    return sub {
        my($chunk, $res, $proto) = @_;
        print $fh $chunk;
    };
}

sub _save_content {
    my($self, $img_src, $args) = @_;

    my $path_name = $args->{path_name} || './';
    my $file_name = $args->{file_name} || basename $img_src;
    $path_name = "${path_name}/" unless $path_name =~ m{/$};
    $file_name =~ s/\?.*//;

    my $content_cb = ref $args->{cb} ne 'CODE'
                   ? $self->_default_cb(my $file_path = "${path_name}${file_name}") # "undef", if same file already.
                   : $args->{cb};

    return if ! $content_cb; # if $content_db is "undef", exists the same file already.

    my $res = $self->{user_agent}->get($img_src,
        ':content_cb' => $content_cb,
    );
    Carp::croak '! failed: download error ' . $res->status_line . "\n" if $res->is_error;
    warn qq(--> success: download ") . $res->base . qq(" ==> ") . $file_path . qq("\n) if $self->{look} and $file_path;

}

sub download {
    my($self, $illust_id, $args) = @_;

    my $info = $self->{info};
    unless ($self->{referer} =~ /$illust_id/ and
        $info->{contents}->{url} =~ /$illust_id/ and
        $info->{img_src}         =~ /$illust_id/) {
        $info = $self->prepare_download($illust_id);
    }

    if ($args->{mode} eq 'medium' or $args->{mode} eq 'm') {
        $self->_save_content($info->{img_src}, $args);
    } else {
        my $contents = $info->{contents};
        if ($contents->{type} eq 'manga') { # over write off
            delete $args->{file_name};
        }
        if ($args->{manga_pages}) {
            for my $page (@{$args->{manga_pages}}) {
                my $img_src = $contents->{img_srcs}->[$page];
                $self->_save_content($img_src, $args);
            }
        } else {
            for my $img_src (@{$contents->{img_srcs}}) {
                $self->_save_content($img_src, $args);
            }
        }
    }

    $self;
}

sub prepare_download {
    my($self, $illust_id) = @_;

    Carp::croak qq(! failed: not found "illust_id".\n) unless $illust_id;

    $self->login if ! $self->{master_user_id};

    my $uri = URI->new( $illust_top );
    $uri->query_form(
        mode      => 'medium',
        illust_id => $illust_id,
    );

    my $res = $self->{user_agent}->get($uri);
    Carp::croak qq(! failed: can not fetch "). $uri . '" '
        . $res->status_line . "\n" unless $res->is_success;
    Carp::croak qq(! failed: referer error ?\n) if $uri ne URI->new($res->base);

    $self->{referer} = ($res->base)->as_string;
    warn qq(--> success: fetch "). $self->{referer}. qq("\n) if $self->{look};

    my $scraper = scraper {
        process '//h3[1]', 'title' => 'TEXT';
        process '//p[@class="works_caption"]', 'description' => 'HTML';
        process '//a[@class="avatar_m"]', 'author_name' => '@title';
        process '//a[@class="avatar_m"]', 'author_url'  => [ '@href', sub {
            return $home . $_;
        } ];
        process '//div[@class="works_display"]/a[1]', 'contents_url' => [ '@href', sub {
            return join '/', $home, $_;
        } ];
        process '//div[@class="works_display"]/a[1]/img[1]', 'img_src' => '@src';
    };

    $self->{info} = $self->_new_infomation($scraper->scrape($res->decoded_content));
}

sub _new_infomation {
    my($self, $info_old) = @_;
    my $info = {
        homepage_url => $self->{referer},
        title        => $info_old->{title},
        description  => $info_old->{description},
        img_src      => $info_old->{img_src},
    };

    my($contents_type, @contents_srcs);
    my $res = $self->{user_agent}->get( $info_old->{contents_url} );
    Carp::croak qq(! failed: ") . $res->status_line . qq("\n) if $res->is_error;
    warn qq(--> success: fetch ") . ($res->base)->as_string . qq("\n) if $self->{look};

    if ($info_old->{contents_url} =~ /mode=big/) {
        my $scraper = scraper {
            process '//img[1]', 'img_src' => '@src';
        };
        push @contents_srcs, $scraper->scrape($res->decoded_content)->{img_src};
        $contents_type = 'illust';
    } else {
        my $html = $res->decoded_content;
        while ($html =~ m!unshift\('(http://([^\']+)?)'!g) {
            my $href = $1;
            my($img_name, $img_path) = fileparse $href;
            $img_name =~ s/_/_big_/;

            my $uri = URI->new("${img_path}${img_name}");
            $res = $self->{user_agent}->head($uri);
            if ($res->status_line =~ /404/) {
                $uri = URI->new($href);
            } elsif ($res->is_error) {
                Carp::croak '! faild: '. $res->status_line . " \n";
            }

            push @contents_srcs, $uri->as_string;
        }
        $contents_type = 'manga';
    }

    $info->{author} = {
        name => $info_old->{author_name},
        url  => $info_old->{author_url},
    };

    $info->{contents} = {
        url      => $info_old->{contents_url},
        type     => $contents_type,
        img_srcs => \@contents_srcs,
    };

    $info;
}

sub user_agent {
    my $self = shift;
    my $ua = shift || return $self->{user_agent};
    Carp::croak "! usage: $self->ua(\$LWP_LIKE_OBJECT)" unless eval { $ua->isa('LWP::UserAgent') };
    $self->{user_agent} = $ua;
}

sub _get_master_user_id {
    my $html = shift;
    my $scraper = scraper {
        process '//div[@class="ui-layout-west"]/div[1]/a', 'profile_to' => '@href';
    };

    my $href = $scraper->scrape($html)->{profile_to};
    $href =~ /=(\d+?)$/ and $1 or undef; 
}

sub master_user_id {
    my $self = shift;
    $self->login unless $self->{master_user_id};
    $self->{master_user_id};
}

sub login {
    my $self = shift;
    my %args = @_;

    $self->{master_user_id} = undef;

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
        $self->{master_user_id} = undef;
        Carp::croak qq(! failed: login error). $res->status_line . "\n";
    } elsif ($res->base ne $mypage) {
        $self->{master_user_id} = undef;
        Carp::croak qq(! failed: wrong "pixiv_id" or "password". ) . $res->base . " now\n";
    }

    $self->{referer}  = ($res->base)->as_string;
    $self->{master_user_id} = _get_master_user_id( $res->decoded_content );

    warn qq(--> success: logged in "). $self->{referer}. qq("\n) if $self->{look};

    $res;
}

1;

__END__

=head1 NAME

WWW::Pixiv::Download - Download pictures from www.pixiv.net

=head1 SYNOPSIS

  use WWW::Pixiv::Download;

  my $client = WWW::Pixiv::Download->new(
      pixiv_id => 'your pixiv id',
      pass     => 'your pixiv password',
  );

  my $illust_id = 'NNNNNNNN';
  $client->download($illust_id);

=head1 DESCRIPTION

WWW::Pixiv::Download is a module to login, get informations of the works and
download picture files from PIXIV.

=head1 METHODS

=over 4

=item B<new>

  $client = WWW::Pixiv::Download->new(%options);

Creates a WWW::Pixiv::Download instance. %options can take the following parameters

=item pixiv_id, pass

These parameters are required to login.

=item over_write, look

These parameters are set as needed.
set "over_write" as "1", to allow overwrite picture files.
set "look" as "1", to warn the progress of any client's working.

=item B<login>

  $response = $client->login(%options);

Login from out of state. and return L<HTTP::Response> object.
maybe $response->base eq "http://www.pixiv.net/mypage.php"

=item B<download>

  $client->download($illust_id);

  or

  $client->download($illust_id, {
      path_name => 'foo/bar',       # local path to save file
      file_name => 'illust_id.jpg', # file name  to save
  });
  # add mode => "medium", then download mediume size

  or

  $client->download($illust_id, {
      cb => \&callback,
  });

Download the picture files. the first parameter is passed to pixiv url.
if that contents is "manga", then download all original size picture files of here.
\&callback details SEE ALSO L<LWP::UserAgent> ':content_cb'.

=item B<prepare_download>

  $inf = $client->prepare_download($illust_id);
  # if Dumper $inf;
  $inf = {
      homepage_url => 'http://www.pixiv.net/member_illust.php?mode=medium&illust_id=$illust_id,
      title        => works title,
      descrption   => works description,
      img_src      => 'http://.../img/usename/image_m.jpg,
      author       => {
          url  => 'http://www.pixi.net/member.php?id=nnnn',
          name => user name,
      },
      contents => {
          type     => (illust|manga),
          url      => 'http://www.pixiv.net/member_illust.php?mode=(big|manga)&illust_id=$illust_id,
          img_srcs => [
              'http://.../img/username/image.jpg', ...
          ],
      },
  };

Returns a hash reference of the information about the works.

=back

=head1 AUTHOR

ishiduca E<lt>ishiduca@gmail.com<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Web::Scraper>
L<http://www.pixiv.net/>

=cut
