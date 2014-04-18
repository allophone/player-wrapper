use strict;
use warnings;
use feature ':5.10'; # loads all features available in perl 5.10
use utf8; # → ju:z ju: tʰi: ɛf eɪt!

use Flex;
use DH::Util;
use DH::File;

use ExWord::Doc;
use ExWord::General::PhenFiles;

use Player::Audacity;
use Player::VLC;

use File::Basename;
use DH::GuiWin;

my $Glob;

sub showhelp { 
  eval 'require DH::Util';
  print DH::Util::console( <<HELP );
Example:
   phongo /home/detlev/windrive/f/PhonPhen/transcr/tub/tub_cc01.fodt
   
  -a allow to use video file for audio
HELP

  my $src = Flex::canonAbsPath($0);
  DH::Util::quickopen( $src, {bat=>'s', show=>1} );
  exit();
}

sub init {
  if ($Glob->{initdone}) {return;}
  eval 'use DH::ForUtil::Getopts';
  
  my $opts = $Glob->{opts} = {};
  # options as above. Values in %opt
  DH::ForUtil::Getopts::getopts('ah', $opts);  
  
  $Glob->{video_for_audio_ok} = $opts->{a} if $opts->{a};
  
  showhelp() if $opts->{h};
  $Glob->{initdone}=1;
}

  init();

  my $tablefile = shift;
  if (!$tablefile) { showhelp()};
  
  $tablefile = Flex::canonAbsPath($tablefile);

  my $doc = ExWord::Doc->new(tableFile=>$tablefile);
  my $pfo = ExWord::General::PhenFiles->new(doc=>$doc);
  my $descr = $pfo->srcDescrRec;
  
  print "\n";
  
  #my $dumper = DH::Util::oneline_dumper();
  #csay $dumper->s($descr);
  
  my $audio = $descr->{audio};
  my $video = $descr->{video};
  
  if (!$audio && $Glob->{video_for_audio_ok}) {
    $audio = $video;
  }
  
  if ($audio) {
    printf "Open '%s' in Audacity\n", $audio;
    my $player = Player::Audacity->new;
    $player->initializeCommand($audio);
    $player->prepareForFile;
  }
  else {
    print "No audio file found.\n";
  }

  if ($video) {
    printf "Open '%s' in VLC\n", $video;
    my $player = Player::VLC->new;
    $player->initializeCommand($video);
    $player->prepareForFile;
  }
  else {
    print "No video file found.\n";
  }
  
  startInLibre($tablefile);
  
  my $win = DH::GuiWin->currentTerminalWin;
  $win->setforegroundwindow if $win;
  print
    $win
      ? "Reactivating ".$win->title." \n\n"
      : "No terminal window -> not reactivating terminal\n\n";

sub startInLibre { my ($file) = @_;
  my $base = basename $file;
  my $title = qr{^ \Q$base\E \s+ \- \s+ LibreOffice\s+Writer}x;
  my $win   = DH::GuiWin->findfirstviewablelike($title);
  if ($win) {
    printf "LibreOffice document already open. Title='%s'\n",
      $win->title;
    return;
  }
  DH::File::start_link($tablefile, {in=>'word'});
  DH::GuiWin->wait_for_window($title, {verbose=>1, maxwait=>20});
}