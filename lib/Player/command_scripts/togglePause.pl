use strict;
use warnings;
use feature ':5.10'; # loads all features available in perl 5.10
use utf8; # → ju:z ju: tʰi: ɛf eɪt!

use Player::VLC;

  my $self = Player::VLC->new(verbose=>1);
  $self->ensureCommunication;
  
  my $file = $self->demoFile;
  $self->activateFile($file);
  
  $self->togglePause;
