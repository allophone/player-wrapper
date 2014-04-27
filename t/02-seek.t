use strict;
use feature ':5.10'; # loads all features available in perl 5.10
use utf8; # → ju:z ju: tʰi: ɛf eɪt!
use Test::More tests => 11;

my ($dir, $player, $file);

BEGIN { 
  $dir = $0;
  $dir =~ s{[^\\\/]+$}{};
  ($player) = require "${dir}prolog.pl"; 
}


  diag("--- Open file, seek, and check ---\n");

  # get a test audio file
  my $samplesdir = Player::Util::proj_dir() . '/samples';
  $file = "$samplesdir/det_count.wav";
  $file = "$samplesdir/det_countvid.avi";

  $player->initializeCommand($file); # set parameters in object
  $player->prepareForFile;           # player and file ready for command

  # try to move active window to top-left corner
  $player->{refocusChoice} = 'term';
  $player->moveActiveWindow('0x0');


  # compare short label calculated and reported by player
  my $label_should_be = $player->shortLabelFromFile($file);
  my $label           = $player->currentlyActiveShortLabel;
  is($label, $label_should_be, "correct label after loading");
  
  # if selection commands too quickly after opening window
  # Audacity gets maximized for unknown reason
  sleep(1) if $player->isa('Player::Audacity');
  
  my @shuffle = qw(9 4 3 2 8 7 1 10 5 6);
  for my $i (@shuffle) {
    # get interval to play
    my ($t0, $t1) = interval_countvid($i);
    my $t0s = $player->previousSeekable($t0);
    
    # seek to and query position
    $player->seek($t0s);
  
    my $pos = $player->position;
    my $msg = sprintf
      "sought to %7.3f, reported %7.3f, dt=%7.3f" ,
      $t0s, $pos, $t0s-$pos;
    
    ok( abs($t0s-$pos)<0.5 , $msg );
    $player->logln($msg);
    Player::Util::sleep(0.01);
  }

  @ARGV = ($player);
  require "${dir}epilog.pl";
