use strict;
use warnings;
use feature ':5.10'; # loads all features available in perl 5.10
use utf8; # → ju:z ju: tʰi: ɛf eɪt!

use DH::ForUtil::Quickopen;

  my ($player) = @ARGV;
  $player->endProcess unless $player->extra->{keep};

  my $file = $player->logFile;
  if ($file) {
    DH::ForUtil::Quickopen::quickopen($file);
    DH::ForUtil::Quickopen::showquickopen;
  }

  1;