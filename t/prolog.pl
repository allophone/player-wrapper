use strict;
use feature ':5.10'; # loads all features available in perl 5.10
use utf8; # -> ju:z ju: t?i: ?f e?t!

use DH::GuiWin;

use Player::Util;

use Player::Audacity;
use Player::VLC;
use Player::Praat;
use Player::Mplayer;

# http://www.perlmonks.org/?node_id=699317
# because it has already duplicated STDOUT, STDERR
binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

my $tb = Test::More->builder;
$tb->failure_output(\*STDERR);
$tb->todo_output(\*STDERR);
$tb->output(\*STDOUT);

sub interval_count { my ($i) = @_;
  $i//=1;
  state $times = {
    1 => [0.6610 , 0.6050] ,
    2 => [1.4270 , 0.4760] ,
    3 => [2.0240 , 0.6210] ,
    4 => [2.8069 , 0.4760] ,
    5 => [3.4990 , 0.6700] ,
    6 => [4.1282 , 0.6409] ,
    7 => [4.7580 , 0.6940] ,
    8 => [5.5560 , 0.5916] ,
    9 => [6.1780 , 0.6370] ,
   10 => [6.8630 , 0.4600] ,
  };
 
  my ($t0, $dt) = @{ $times->{$i} };
  return ($t0, $t0+$dt);
}

sub interval_countvid { my ($i) = @_;
  $i//=1;
  state $times = {
    1 => [1.2720 , 0.5350] ,
    2 => [1.8070 , 0.4460] ,
    3 => [2.2530 , 0.4940] ,
    4 => [2.8280 , 0.4060] ,
    5 => [3.2975 , 0.5000] ,
    6 => [3.8090 , 0.4210] ,
    7 => [4.2630 , 0.4780] ,
    8 => [4.8465 , 0.3767] ,
    9 => [5.2760 , 0.4620] ,
   10 => [5.7870 , 0.4130] ,
  };

  my ($t0, $dt) = @{ $times->{$i} };
  return ($t0, $t0+$dt);
}

sub extract_opt { my ($re, $vals) = @_;
  my (@extracted, @remaining);
  
  for (@$vals) {
    /$re/
      ? (push @extracted, $_)
      : (push @remaining, $_)
    ;
  }
  (return \@extracted, \@remaining);
}

=for me

  -s log to screen
  -T skip tests doesn't disturb visual effect
  -M muting mode for Mplayer
  -1, -2 ... : play interval $i only
  -k leave player running afterwards
  [amv] choose player

=cut


  my $args = [@ARGV];
  (my $showA  , $args) = extract_opt( qr/^\-s+$/  , $args );
  (my $testA  , $args) = extract_opt( qr/^\-T+$/  , $args );
  (my $muteA  , $args) = extract_opt( qr/^\-M+$/  , $args );
  (my $intA   , $args) = extract_opt( qr/^\-\d+$/  , $args );
  (my $keepA  , $args) = extract_opt( qr/^\-k+$/  , $args );
  (my $modA   , $args) = extract_opt( qr/^[amv]$/ , $args );

  my $mod = $modA->[0]//'a';
  $mod = {
    a => 'Audacity' ,
    v => 'VLC' ,
    p => 'Praat' ,
    m => 'Mplayer' ,
  }->{$mod}//$mod;
  
  $mod = "Player::$mod";
  my $player = $mod->new;
  
  # enter options into $player
  $player->setLogFile        if !$showA->[0];
  
  $player->extra->{keep}       = 1 if  $keepA->[0];
  
  if (defined (my $i=$intA->[0])) {
    $i =~ s{^\-}{};
    $player->extra->{i_interval} = $i;
  }
  
  $player->extra->{muting_mode}       = 1 if $muteA->[0];
  $player->extra->{skip_some_tests}   = 1 if $testA->[0];

  $player;
