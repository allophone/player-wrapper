use strict;
use feature ':5.10'; # loads all features available in perl 5.10
use utf8; # → ju:z ju: tʰi: ɛf eɪt!
use Test::More;

my ($dir, $player, $file);

BEGIN { 
  $dir = $0;
  $dir =~ s{[^\\\/]+$}{};
  ($player) = require "${dir}prolog.pl"; 
}


  diag("--- Open file, seek, and check ---\n");

  # get a test audio file
  my $samplesdir = Player::Util::proj_dir() . '/samples';
  $file = "$samplesdir/det_countvid.avi";

  $player->initializeCommand($file); # set parameters in object
  $player->prepareForFile;           # player and file ready for command

  # if selection commands too quickly after opening window
  # Audacity gets maximized for unknown reason
  Player::Util::sleep(0.1)     if $player->is('Audacity');
  $player->{aud_noZoomSel} = 1 if $player->is('Audacity');

  # try to move active window to top-left corner
  $player->{refocusChoice} = 'term';
  $player->moveActiveWindow('0x0');

  # compare short label calculated and reported by player
  my $label_should_be = $player->shortLabelFromFile($file);
  my $label           = $player->currentlyActiveShortLabel;
  is($label, $label_should_be, "correct label after loading");

  $player->{mpl_rangeVolume}=100
    if $player->is('Mplayer') && $player->extra->{muting_mode};

  my @shuffle = qw(5 4 3 2 1 10 9 8 7 6);
  if (my $i=$player->extra->{i_interval}) {
    @shuffle = ($i);
  }

  for my $i (@shuffle) {
    # seek to and query position
    my ($t0, $t1) = interval_countvid($i);
    $player->playRange($t0, $t1, {same_process=>1});
    
    Player::Util::sleep($t1-$t0+0.01) if $player->is('Audacity');
    next if $player->extra->{skip_some_tests};

    my ($t0new, $t1new) =
      $player->is('Audacity')
        ? $player->aud_getSelection
        : (undef , $player->position);
    
    my $msg = sprintf
        "played until %7.3f, reported %7.3f, dt=%7.3f" ,
        $t1, $t1new, $t1-$t1new;

    ok( abs($t1-$t1new)<0.5 , $msg );
    
  }

  done_testing( 1+@shuffle );

  @ARGV = ($player);
  require "${dir}epilog.pl";
