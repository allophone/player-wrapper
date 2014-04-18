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

  my $mod = shift || 'Audacity';
  $mod = {
    a => 'Audacity' ,
    v => 'VLC' ,
    p => 'Praat' ,
    m => 'Mplayer' ,
  }->{$mod}//$mod;
  
  $mod = "Player::$mod";
  