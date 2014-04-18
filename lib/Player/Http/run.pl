use Flex;

use Carp::Always;

use HTTP::Server::Simple;
use Player::PsEntry;

use warnings;
use strict;

use DH::File;

use IO::Handle;
STDOUT->autoflush(1);
STDERR->autoflush(1);

  # call Dhs::PsEntry::server_init so that options are known
  # here I use $opt->{p} for the port

  my $opt = Player::PsEntry::server_init();
  my $default_port = 8092;
  my $port = $opt->{p} || $default_port;
  if ($port<100) {$port+=$default_port;}
  my $server = Player::PsEntry->new($port);

  # open pages depending on options
  open_page($opt, $port);
  
  # optionally do some loading at start

  $server->run();


sub open_page { my ($opt, $port) = @_;

  foreach my $q ('b') {
    my $page;
    if (!$opt->{$q}) {next;}
    
    if ($q eq 'b') {
      $page = '/';
    }
    
    my $urlhost = 'http://localhost';
    my $urlport = $port == 80 ? '' : sprintf(":%d",$port);
    my $url  = "$urlhost$urlport$page";
    DH::File::start_link($url);
  }
}
