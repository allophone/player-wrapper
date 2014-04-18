use strict;
use warnings;
use feature ':5.10'; # loads all features available in perl 5.10
use utf8; # → ju:z ju: tʰi: ɛf eɪt!

use DH::ForUtil::Getopts;

use Player::State::State;
use Player::Util;

use ExWord::Audio::PlaySelFromTable;

my $Glob;

sub showhelp { 
  eval 'require DH::Util';
  print DH::Util::console( <<HELP );
Example
  perl play.pl 'key1=val1; key2=val2;...' 'key3=val3;...' ...
  
  Possible key-value pairs:
  stcid     = #S#00100
  start_s   = 60
  length_s  = [7.766]
  refocus   = doc
  tablefile = F:/PhonPhen/transcr/sha/sha_nep.fodt
  player    = vlc
    ...and a few more
  
  Option:
   -r   : replay last command
          possible params replace existing ones
          refocus always set to 'term'
          
          Example: perl play.pl -r player=praat
  
HELP

  my $src = Flex::canonAbsPath($0);
  eval 'use DH::Util';
  DH::Util::quickopen( $src, {bat=>'s', show=>1} );
  exit();
}

sub init {
  if ($Glob->{initdone}) {return;}
  my $opts = $Glob->{opts} = {};
  # options as above. Values in %opt
  DH::ForUtil::Getopts::getopts('rh', $opts);  
  showhelp() if $opts->{h};
  $Glob->{initdone}=1;
}

  init();
  
  my $s = join(';', @ARGV);

  if (!$s && !$Glob->{opts}{r}) {
  $s = 'stcid=62     ; start_s=499.5648 ; length_s=[1.0493] ; refocus=term  ; tablefile=/home/detlev/windrive/f/PhonPhen/transcr/edm/edm_01_subtitle.fodt ; player=video';
  
  $s = 'stcid=267    ; start_s=1061.629 ; length_s=[3.064] ; player=video ; refocus=term ; tablefile=/home/detlev/windrive/f/PhonPhen/transcr/ly/ly_001_subtitles.fodt';
  }

  printf "\n%s\n", '-'x60;
  print "s='$s'\n";

  # current command as hash
  my $hash = Player::Util::resolvedParamHash($s);

  if ($Glob->{opts}{r}) {
    my $basehash = Player::State::State->previousCommandHash();
    die "previous command not found" if !$basehash;
    $hash = Player::Util::modifyBaseHash( $basehash, $hash );
  }

  # play according to this command
  Player::Util::processPlayCommand($hash);
  
  Player::State::State->createCommandFile($hash) if !$Glob->{opts}{r};

  printf "%s\n", '-'x60;

