use strict;
use Test::More tests => 1;
use feature ':5.10'; # loads all features available in perl 5.10

use utf8; # → ju:z ju: tʰi: ɛf eɪt!

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


sub interval { my ($i) = @_;
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

  my $mod = shift || 'Audacity';
  $mod = {
    a => 'Audacity' ,
    v => 'VLC' ,
    p => 'Praat' ,
    m => 'Mplayer' ,
  }->{$mod}//$mod;
  
  $mod = "Player::$mod";
  
  my $player = $mod->new;

  diag("--- Play some intervals ---\n");

  use Flex;
  use DH::Util;
  
  my $file = Flex::path('F:/phon/detlev/det_count.wav');
  for my $i (qw(3 1 4 1 5 9 3)) {
    my ($t0, $t1) = interval($i);
    $player->playRangeForFile($file, $t0, $t1);
    DH::Util::sleep( $t1-$t0+0.1 );
  }


