use strict;
use feature ':5.10'; # loads all features available in perl 5.10
use utf8; # → ju:z ju: tʰi: ɛf eɪt!
use Test::More;

my ($dir, $player, $file);

BEGIN { 
  $dir = $0;
  $dir =~ s{[^\\\/]+$}{};
  ($player) = require "${dir}prolog.pl"; 
}


  diag("--- Open file, seek, and check ---\n");

  # get a test audio file
  my $samplesdir = Player::Util::proj_dir() . '/samples';
  $file = "$samplesdir/det_countvid.avi";

  $player->initializeCommand($file); # set parameters in object
  $player->prepareForFile;           # player and file ready for command

  # try to move active window to top-left corner
  $player->{refocusChoice} = 'term';
  $player->moveActiveWindow('0x0');

  # compare short label calculated and reported by player
  my $label_should_be = $player->shortLabelFromFile($file);
  my $label           = $player->currentlyActiveShortLabel;
  is($label, $label_should_be, "correct label after loading");
  
  my @shuffle = qw(5 4 3 2 1 10 9 8 7 6);
  if (my $i=$player->extra->{i_interval}) {
    @shuffle = ($i);
  }
  
  my $pau_opt = {pausing=>'pausing'};
  
  my $vol = 100;
  
  my $pos;
  
  for my $i (@shuffle) {
    # seek to and query position
    my ($t0, $t1) = interval_countvid($i);
    #$vol = $player->mpl_readValue('get_property volume', $pau_opt);
    #$vol = 80 if !$vol || $vol==0;
    
    #$player->mpl_doCommand('volume 0 1', {no_resp=>1});
    
    #my $pause_state = $player->mpl_readValue(
    #  'get_property pause', {pausing=>'pausing_keep_force'}
    #);
    #my $pausing = $pause_state eq 'yes' 
    #  ? 'pausing_keep' 
    #  : 'pausing_toggle';
      
    $player->seek($t0, {pausing=>'pausing'});
    
    
    if (0) {
      my $pos = $player->position;
      my $msg = sprintf
        "sought to %7.3f, reported %7.3f, dt=%7.3f" ,
        $t0, $pos, $t0-$pos;
      $player->logln($msg);
    }
    
    #$player->mpl_doCommand(
    #  "volume $vol 1" , {no_resp=>1, pausing=>'pausing_toggle'}
    #);
    $player->mpl_doCommand('pause', {no_resp=>1});
    Player::Util::sleep($t1-$t0);
    #$player->mpl_doCommand(
    #  "volume 0 1"    , {no_resp=>1, pausing=>'pausing'}
    #);
    #$player->mpl_doCommand('pause', {no_resp=>1});
    #$player->ensurePaused;
    $pos = $player->position({pausing=>'pausing'});
    if (1) {
      my $msg = sprintf
        "played until %7.3f, reported %7.3f, dt=%7.3f" ,
        $t1, $pos, $t1-$pos;
      $player->logln($msg);
    }
  }

  done_testing( 1+@shuffle );

  @ARGV = ($player);
  require "${dir}epilog.pl";
