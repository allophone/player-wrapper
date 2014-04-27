use strict;
use Test::More tests => 1;
use feature ':5.10'; # loads all features available in perl 5.10
use utf8; # → ju:z ju: tʰi: ɛf eɪt!

my $mod;
BEGIN { $mod = require './prolog.pl'; }

  my $player = $mod->new;

  diag("--- Open file and check ---\n");

  my $samplesdir = Player::Util::proj_dir() . '/samples';
  my $file = "$samplesdir/det_empty.wav";

  $player->initializeCommand($file);
  $player->prepareForFile;

  my $label = $player->currentlyActiveShortLabel;
  my $label_should_be = $mod->shortLabelFromFile($file);
  
  is($label, $label_should_be, "correct label after loading");

