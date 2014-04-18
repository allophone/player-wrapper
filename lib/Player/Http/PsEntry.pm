package Player::PsEntry;
use strict 'vars';
use utf8; # → ju:z ju: tʰi: ɛf eɪt!

use HTTP::Server::Simple::Static;
use DH::HtmlUtil;

use Encode;
use ServerGlobals;

use DH::ForUtil::Getopts;
use DH::GuiWin;

# However, normally you will sub-class the 
# HTTP::Server::Simple::CGI module 
# (see the HTTP::Server::Simple::CGI manpage);
use base qw(HTTP::Server::Simple::CGI);

# strangely the 'my' line wasn't sufficient for $headers
# my ($headers, $setup);
use vars qw($headers $setup $login_object);
our $Glob = {};

sub server_init {
  my $opts = $Glob->{opts} = {};
  DH::ForUtil::Getopts::getopts('pbELD', $opts);
  return $opts;
}

### delegation and static pages

sub url_mapper {
  return $Glob->{mapper} //= Flex::new_url_mapper();
}

sub handle_request { my ($self, $cgi) = @_;
  ServerGlobals->store->cgi( $cgi );
  my $setup = ServerGlobals->store->setup;

  my $opts  = $Glob->{opts};
  my $path  = $setup->{path};
  my $path_handled = 1;

  if ($path eq '/favicon.ico') { 
    return dh_serve_static($self, $cgi, $opts) 
  }

  if ($opts->{E}) {
    # printf STDERR "\nlogin-object:\n%s\n"    , dhdump($login_object);
    printf STDERR "\ncgi:\n%s\n"    , dhdump($cgi   );
    printf STDERR "\nsetup:\n%s\n"  , dhdump($setup );
    printf STDERR "\nheaders:\n%s\n", dhdump(
      ServerGlobals->store->headers
    );
    d::dd('handle_request');
  }
    
  if (0) {}
  elsif ($path eq '/') {
    sendPageFromSub($cgi, {htmlsub=>\&homePageHtml});
  }

  elsif ($path =~ m{^/play/?$}) {
    my $com = $cgi->param('com');

    my $hash;
    if ($com) {
      $hash = Player::Util::resolvedParamHash($com);
    }
    else {
      $hash = param_hash($cgi);
    }
    
    # play according to this command
    
    {
      my $oldfh = select(STDERR);
      Player::Util::processPlayCommand($hash);
      Player::State::State->createCommandFile($hash) if !$Glob->{opts}{r};
      select($oldfh);
    }
    
    my $peeraddr = $setup->{peeraddr}//'';
    my $host =
      $peeraddr =~ m{^ ( \Q127.0.0.1\E | localhost |) $ }x
        ? 'localhost'
        : DH::Util::compid();
    
    my $port = $setup->{localport};
    $host .= ":$port" if $port && $port!=80;
    redirectTo("http://$host/");
  }

  else {
    # Now try the static paths
    my $mapper = url_mapper();
    
    # firefox percent-encodes spaces, 
    # this must be undone to find the file
    my $path_percent_decoded = DH::HtmlUtil::percent_decode($path);

    my $res       = $mapper->matchUrlPath($path_percent_decoded);

    if ($res) {
      my $root1       = $res->{targetroot_for_match};
      my $path1       = $res->{portion_following_match};
      $self->serve_static_root_path($cgi, $root1, $path1);
    }
    else {
      $path_handled = undef;   # no handler found
    }
  }
  
  if ($path_handled) {
  }

  else {
    # every remaining url will be served statically from 
    # my standard document root ('d:/html/');
    my $root = Flex::path('d:/html');
    $self->serve_static($cgi, $root);
  }
}

sub dh_serve_static { my ($self, $cgi, $opt) = @_;
  my $root = 
       $opt->{sourcedir} 
    || DH::Util::dhperlroot().'/lib/DH/Serve/static';
  $self->serve_static($cgi, $root);
}

=head2 serve_static_root_relpath($self, $cgi, $root, $relpath)

The normal operation of serve_static is as follows:

The total request url is split into:

  $url  = $base . $path  (with the '/' included in $path)

and $path can be retrieved from:

  $path = $setup->{path}

E.g.:

  $url  = http://localhost:8080/img/grapr/C0001.bmp
  $base = http://localhost:8080
  $path =                      /img/grapr/C0001.bmp

If a local file on disk should be served for this url, I can call:

   $self->serve_static($cgi, $root)

This will keep the $path-portion, but will append this path to some
local directory $root, i.e. serve the file:

   $file = $root . $path;

The problem with this approach is that the server can only rewrite
the $root-portion, but the local position of the file must always end
in the $path-portion that is used in the url.

I use this special routine to also change the $path portion for
an individual request. I have found that the server holds this
info in two environment variables:

  $ENV{PATH_INFO}
  $ENV{REQUEST_URI}

(not sure what the difference between the two is)
rewriting the path portion is possible by changing these two environment variables

=cut

sub serve_static_root_path { my ($self, $cgi, $root, $path)=@_;
  $ENV{PATH_INFO}   = $path;
  $ENV{REQUEST_URI} = $path;
  $self->serve_static($cgi,$root);
}

=for me

I hadn't understood that the $cgi object had methods to retrieve values like path and query params. I used a work-around to get these values. I noticed that the sub setup in superclass HTTP::Server::Simple::CGI has access to these values. 

I overrode this setup with the following method that calls SUPER::setup, but also keeps a copy of {@_} in a global variable $setup.

=cut

=for me

Example with Apache2

  DB<3> x $setup
0  HASH(0x9062950)
   'localname' => 'localhost'
   'localport' => 8080
   'method' => 'GET'
   'path' => '/cgi-bin/log.cgi'
   'peeraddr' => '127.0.0.1'
   'peername' => '127.0.0.1'
   'peerport' => 59303
   'protocol' => 'HTTP/1.1'
   'query_string' => 'form=loginout&com_choose=Choose+section&big=on&LOGSESSID=677bd1bbf18343bc87bb099097a83e58'
   'request_uri' => '/cgi-bin/log.cgi?form=loginout&com_choose=Choose+section&big=on&LOGSESSID=677bd1bbf18343bc87bb099097a83e58'
 
=cut

sub setup { my $self = shift;
  # keep a copy of the arguments (after class obj)
  ServerGlobals->store->setup( {@_} );
  
  # then call original method
  $self->SUPER::setup(@_);
}

=for me

with Apache2:

  DB<2> x $headers
0  HASH(0x9063160)
   'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
   'Accept-Charset' => 'ISO-8859-1,utf-8;q=0.7,*;q=0.7'
   'Accept-Encoding' => 'gzip, deflate'
   'Accept-Language' => 'en-us,en;q=0.5'
   'Cache-Control' => 'max-age=0'
   'Connection' => 'keep-alive'
   'Cookie' => 'LOGSESSID=677bd1bbf18343bc87bb099097a83e58'
   'Host' => 'localhost:8080'
   'Keep-Alive' => 115
   'Referer' => 'http://localhost:8080/cgi-bin/log.cgi?form=loginout&com_choose=Choose+section&big=on&LOGSESSID=677bd1bbf18343bc87bb099097a83e58'
   'User-Agent' => 'Mozilla/5.0 (X11; Linux i686; rv:2.0.1) Gecko/20100101 Firefox/4.0.1'

=cut

sub headers {
  my $self = shift;
  
  # keep a copy of the arguments (after class obj)
  ServerGlobals->store->headers( { @{ $_[0] } } );
  
  # Simulate situation where cookie is in environment variable 
  # for CGI::Session
  #  $headers->{HTTP_COOKIE} = $headers->{Cookie};
  
  # then call original method
  $self->SUPER::headers(@_);
}

### helper routines for building reponse

# http://www.w3.org/International/questions/qa-html-encoding-declarations#httpsummary
sub httpHeader { my ($par) = @_;
  my $env = $par->{env} || \%ENV;
  my $server_software = $env->{SERVER_SOFTWARE};
  
  if ( $server_software && $server_software =~ /^Apache/ ) {
    return httpHeaderApache($par);
  }
  
  my @extralines = @{ $par->{extralines}||[] };
  my $extra='';
  if ( @extralines ) {
    $extra = join("\n", '', @{ $par->{extralines} } );
  }
  my $statuscode = $par->{statuscode} || '200';
  my $status = {
    '302' => 'Found' ,
    '200' => 'OK' ,
  }->{$statuscode} || 'OK';

  my $len = $par->{len} || 0;
  my $s = <<HEADER;
HTTP/1.1 $statuscode $status$extra
Content-Type: text/html; charset=UTF-8
Content-Length: $len

HEADER

  return $s;
}

=for me

Example of header:

HTTP/1.1 200 OK
Date: Mon, 24 Mar 2014 18:47:17 GMT
Server: Apache/2.2.16
Vary: Host,Accept-Encoding
Last-Modified: Sat, 03 Aug 2013 11:25:11 GMT
ETag: "93b-4e309540fe4d1"
Accept-Ranges: bytes
Content-Length: 2363
Cache-Control: public, no-transform
Content-Type: text/html

=cut

sub unpack_header { my ($header) = @_;
  my @lines = split /\r?\n/ , $header;
  my (@pairs, $status);
  
  foreach (@lines) {
    # First line like: HTTP/1.1 200 OK
    if ( m{^HTTP/\d\.\d \s+ (\d+) }x ) {
      $status = $1;
      next;
    }
    
    # Remaining lines are key value pairs
    my @pair = m{^ ([\w\-]+) : \s* (.*?) $}x;
    next if !$pair[0];
    next if $pair[0]=~/content\-length/i;
    push @pairs , @pair;
  }
  return $status , [@pairs];
}

sub updateRequiring { my ($file) = @_;
  my $loadtimes = $Glob->{loadtimes}//={};
  my $loadtime  = $loadtimes->{$file};

  my $action = 'Loading';
  
  if (defined $loadtime) {
    my $modtime = $^T - (-M $file)*86400;
    # nothing to do if up-to-date
    return if ($modtime<$loadtime);
    
    $action = 'Reloading';
  }
  
  print STDERR "$action $file\n";
  do $file;
  
  $loadtimes->{$file} = time();
}

sub homePageHtml { my ($cgi) = @_;
  my $pm = Flex::dhlib() . '/Player/Gui.pm';
  updateRequiring($pm);
  
  my $pkg = __PACKAGE__;
  my $s='';
  $s .= initHtml({title=>'My Homepage'});
  $s .= Player::Gui->homePageBody();
  $s .= closeHtml();
  return $s;
}


sub initHtml { my ($opt) = @_;
  my $title = $opt->{title}//'Home Page';
  return <<HTML
<!DOCTYPE html PUBLIC
  "-//W3C//DTD XHTML 1.0 Strict//EN"
  "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns='http://www.w3.org/1999/xhtml'>

<head>
  <title>$title</title>
  <meta http-equiv="Content-Language" content="en" />
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
</head>

<body>
HTML
;
}    

sub closeHtml {
  return '
</body>
</html>
';
}    

### building response from sub

=for me

Example:

HTTP/1.1 301 Moved Permanently
Date: Mon, 24 Mar 2014 20:48:10 GMT
Server: Apache/2.2.16
Location: http://detlev.home.xs4all.nl/
Vary: Accept-Encoding
Content-Length: 237
Content-Type: text/html; charset=iso-8859-1


=cut


sub redirectTo { my ($dest) = @_;
  my $extralines = [
    "Location: $dest" ,
  ];
  my $header = httpHeader({
    statuscode => 302 ,
    extralines => $extralines ,
  });
  print $header;
}

sub sendPageFromSub { my ($cgi, $par) = @_;
  my ($header, $html) = getPageFromSub($cgi, $par);
  print $header;
  print $html;
}

sub getPageFromSub { my ($cgi, $par) = @_;
  my $env = $par->{env} || \%ENV;
  my $server_software = $env->{SERVER_SOFTWARE};
  
  my $htmlsub = $par->{htmlsub};
  $htmlsub = \&demoPageHtml if ref $htmlsub ne 'CODE';
  
  my $html = &$htmlsub($cgi);
  my $len = length($html);

  my $header;
  if ( $server_software && $server_software =~ /^Apache/ ) {
    $header = httpHeaderApache($par);
  }
  else {
    $header = httpHeader( { %{$par||{}}, len=>$len } );
    $header =~ s{\r*\n}{\r\n}g;
  }

  return ($header, $html);
}


### utilities

sub dhdump { my ($s) = @_;
  eval 'use DH::Util';
  my $dumper = DH::Util::oneline_dumper();
  print STDERR DH::Util::console( $dumper->s($s) );
}

sub param_hash { my ($cgi) = @_;
  my %hash;
  for ($cgi->param) {
    $hash{$_} = $cgi->param($_);
  }
  return \%hash;
}

### test and main

sub test1info {'unpack_header'}
sub test1 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  
  my $header = <<HEADER;
HTTP/1.1 200 OK
Content-Type: text/html; charset=UTF-8
Content-Length: 1234

HEADER
  my ($status, $list) = unpack_header($header);
  print dhdump($status, $list);
}

use DH::Testkit;
sub main {
  print __PACKAGE__ . " meldet sich!\n";
  return __PACKAGE__->test1 if @ARGV==0;
  DH::Testkit::selectTest(__PACKAGE__);
}

if ($0 eq __FILE__) {main();}

1;
