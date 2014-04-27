use strict;
use Test::More tests => 1;
use feature ':5.10'; # loads all features available in perl 5.10
use utf8; # → ju:z ju: tʰi: ɛf eɪt!

my ($dir, $player);

BEGIN { 
  $dir = $0;
  $dir =~ s{[^\\\/]+$}{};
  ($player) = require "${dir}prolog.pl"; 
}

  diag("--- Open file and check ---\n");

  # get a test audio file
  my $samplesdir = Player::Util::proj_dir() . '/samples';
  my $file = "$samplesdir/det_empty.wav";

  $player->initializeCommand($file); # set parameters in object
  $player->prepareForFile;           # player and file ready for command

  # try to move active window to top-left corner
  $player->moveActiveWindow('0x0');

  # compare short label calculated and reported by player
  my $label_should_be = $player->shortLabelFromFile($file);
  my $label           = $player->currentlyActiveShortLabel;
  is($label, $label_should_be, "correct label after loading");

  @ARGV = ($player);
  require "${dir}epilog.pl";
