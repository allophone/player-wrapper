use strict;
use warnings;
use feature ':5.10'; # loads all features available in perl 5.10
use utf8; # → ju:z ju: tʰi: ɛf eɪt!

use DH::ForUtil::Time;

use Player::VLC;

  my $self = Player::VLC->new(verbose=>1);
  $self->ensureCommunication;
  #$self->ensurePaused;

  while (1) {
    go();
    DH::ForUtil::Time::sleep(0.1);
  }

sub go {
  my $status = $self->vlc_status;
  my ($t, $l, $p) = @{$status}{qw(time length position)};
  my $fmt = "\%-10s%8.3f\n";
  printf  $fmt , 'position' , $p;
  printf  $fmt , 'length'   , $l;
  printf  $fmt , 'time'     , $t;
  printf  $fmt , 'l*p'      , $l*$p;

  $self->update;
}
