use strict;
use warnings;
use feature ':5.10'; # loads all features available in perl 5.10
use utf8; # → ju:z ju: tʰi: ɛf eɪt!

use DH::ForUtil::Time;

use Player::VLC;

  my $self = Player::VLC->new(verbose=>1);
  $self->ensureCommunication;
  $self->ensurePaused;

  my $dt = shift//1;
  
  my $t0 = $self->vlc_status->{time};
  my $t1 = int( $t0 + $dt + 0.5 );

  my $fmt = "%4s:%12s\n";
  print   "Move position:\n";
  printf $fmt, 'From', Player::Util::ss2hhmmssmmm($t0);
  printf $fmt, 'To'  , Player::Util::ss2hhmmssmmm($t1);
  printf $fmt, 'dt'  , Player::Util::ss2hhmmssmmm($t1-$t0) ;

  $self->seek($t1);
