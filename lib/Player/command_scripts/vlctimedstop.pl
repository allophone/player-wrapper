use strict;
use warnings;
use feature ':5.10'; # loads all features available in perl 5.10
use utf8; # → ju:z ju: tʰi: ɛf eɪt!

#use DH::ForUtil::Time;

use Player::VLC;
use Player::Util;

sub showhelp { 
  print <<HELP;
Example:
  perl vlctimedstop 'to=105.5; seektime=101; finalseek=103'
  
  to <t>       : time in [s] at which playback stops
  
  seektime <t> : optionally inform script of time previously
                 sought to improve stop time accuracy
  
  finalseek <t>: optionally tell script to seek specific
                 position at end
  
HELP

  my $src = Flex::canonAbsPath($0);
  require DH::ForUtil::Quickopen;
  DH::ForUtil::Quickopen::quickopen( $src, {bat=>'s', show=>1} );
  exit();
}

  if ( grep { $_ eq '-h'} @ARGV ) {
    showhelp();
  }

  my $paramHash = Player::Util::paramHashFromStrings(@ARGV);

  my ($to, $seektime, $finalseek);
  
  if ( ($ARGV[0]//'') !~ /=/ ) {
    $to = shift @ARGV;
  }

  $to         //= $paramHash->{to};
  $seektime   //= $paramHash->{seektime};
  $finalseek  //= $paramHash->{finalseek};

  my %par;
  $par{verbose} = 0;
  for (qw(host port)) {
    $par{$_} = $paramHash->{$_} if $paramHash->{$_};
  }
  my $vlc = Player::VLC->new(%par);
  $vlc->ensureCommunication;

  
  for ($to, $seektime, $finalseek) {
    next if !$_;
    if (/:/) { $_ = Player::Util::hhmmssmmm2ss($_);}
  }
  
  if (!defined $to) {
    my $status = $vlc->vlc_status;
    $to = $status->{length};
  }
  
  if ($vlc->vlc_state ne 'playing') {
    $vlc->togglePause;
  }
  
  $vlc->vlc_timedStop(
    $to, 
    {seektime=>$seektime, finalseek=>$finalseek} ,
  );
