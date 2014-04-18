use strict;
use warnings;
use feature ':5.10'; # loads all features available in perl 5.10
use utf8; # → ju:z ju: tʰi: ɛf eɪt!

use Flex;
my $Glob;

sub showhelp { 
  eval 'require DH::Util';
  print DH::Util::console( <<HELP );
Dies ist meine Standardmethode, um dafür zu sorgen, dass mit der 
Option -h Hilfe angezeigt wird.
HELP

  my $src = Flex::canonAbsPath($0);
  DH::Util::quickopen( $src, {bat=>'s', show=>1} );
  exit();
}

sub init {
  if ($Glob->{initdone}) {return;}
  eval 'use DH::ForUtil::Getopts';
  
  my $opts = $Glob->{opts} = {};
  # options as above. Values in %opt
  DH::ForUtil::Getopts::getopts('h', $opts);  
  showhelp() if $opts->{h};
  $Glob->{initdone}=1;
}

  init();

  use Player::VLC;
  my $vlc = Player::VLC->new;
  $vlc->initializeCommand;
  my $ok = $vlc->prepareForFile;
  
  exit unless $ok;

  my $com = shift @ARGV;
  
  my $response =
    $com
      ? $vlc->vlc_command( lc($com) )
      : $vlc->togglePause;

  # show some info about new status
  my $status = $vlc->vlc_status;

  my @fields = qw(time length state);
  my @s = map { sprintf "%s: %s", $_, $status->{$_} } @fields;
  print "Result: ", join('; ', @s), "\n";
  
  #foreach (@fields) {
  #  printf "%-10s: %s\n", $_, $status->{$_}//'';
  #}
