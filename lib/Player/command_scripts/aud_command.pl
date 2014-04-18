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

  use Player::Audacity;
  my $aud = Player::Audacity->new;
  $aud->initializeCommand;
  my $ok = $aud->prepareForFile;
  
  exit unless $ok;

  my $com = shift @ARGV;
  
  my @resp =
    $com
      ? $aud->aud_menuCommand( ucfirst($com) )
      : $aud->playCurrentSelection;
  
  print "Result:\n";
  for (@resp) {print "  $_\n"}

