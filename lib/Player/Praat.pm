package Player::Praat;
use strict;
use warnings;
use feature ':5.10'; # loads all features available in perl 5.10
use utf8; # → ju:z ju: tʰi: ɛf eɪt!

use parent 'Player::Base';
use parent 'Player::PraatUtil';

use Time::HiRes qw( gettimeofday tv_interval );
use List::Util qw( max );

use DH::ForUtil::Time;
use DH::GuiWin;

### Construction

sub build { my ($self) = @_;
  # file locations
  
  my $dir = Player::Util::praat_script_dir();
  Player::Util::createDir($dir) if ! -e $dir;
  $self->{pra_scriptDir} = $dir;

  return $self;
}

sub DESTROY { my ($self) = @_;}

### accessors

sub verbose { $_[0]->{verbose} }

### gateway to praat
sub pra_scriptDir { $_[0]->{pra_scriptDir} }

## helpers for innermost layer

## innermost layer

sub update {1} # dummy

### information retrieval through inner-layer command

sub currentlyActiveShortLabel { my ($self) = @_;

  my $win = DH::GuiWin->findfirstviewablelike( '\d+\.\s+LongSound' );
  return if !$win;
  
  my $title = $win->title;
  return if $title !~ /\d+\.\s+LongSound\s+/;
  
  return $';
}

### various audacity-only 2nd layer commands

### computed player behaviour

sub shortLabelFromFile { my ($self, $file) = @_;
  my ($name, $path, $ext) 
    = File::Basename::fileparse($file, '\..*');
  return $name;
}

### manage connected files (i.e. files with audacity window)

## helpers for connecting/activating files (by GUI interaction)
sub pra_existingWindowForFile { my ($self, $file) = @_;
  my $label = $self->shortLabelFromFile($file);
  my $title   = '\d+\.\s+LongSound\s+'.$label;
  my $prawin  = DH::GuiWin->findfirstviewablelike("\^$title\$");
  return $prawin;
}

sub pra_newEmptyWindow { my ($self) = @_;
  $self->pra_activeItemToForeground;
  
  my $i=0;
  my $resp;
  while ($i++<10) {
    $resp = $self->pra_menuCommand('New');
    return 1 if $resp && $resp !~ /Failed/;
  }
  return;
}

#sub pra_scriptForCommand { my ($self, $core) = @_;

#sub pra_writePraatScript { my ($self, $namecore, $body) = @_;}

sub pra_executeScriptInObjectsWindow { my ($self, $script) = @_;
  return if !Flex::onWin();

  $script =~ s{\/}{\\}g;

  my ($objwin, $openwin, $editwin);
  my $objtitle = '^Praat Objects$';
  my $scr2 = $script;
  $scr2 =~ s{\/}{\\\\}g;
  my $edittitle = "^Script.*${scr2}";
  $edittitle = "^Script\\s+";

  my $delay = 0.5;

  $editwin = DH::GuiWin->findfirstviewablelike($edittitle);
  if (!$editwin) {

    my $objwin = DH::GuiWin->findfirstviewablelike(
      $objtitle ,
      {verbose=>1, maxwait=>10, viewable=>1}
    );
    return if !$objwin;
    $objwin->sendto('%po');
    Player::Util::sleep($delay);

    my $openwin = DH::GuiWin->wait_for_window(
      '^Open$' ,
      {verbose=>1, maxwait=>10, viewable=>1}
    );
  
    return if !$openwin;
    $openwin->sendto("${script}~");
    Player::Util::sleep($delay);

  }

  $editwin = DH::GuiWin->wait_for_window(
    $edittitle  ,
    {verbose=>1, maxwait=>10, viewable=>1}
  );
  
  return if !$editwin;
  
  $editwin->sendto('^r');
  Player::Util::sleep($delay);
  
  $editwin->setforegroundwindow;
  Player::Util::sleep($delay);
  
  $editwin->sendto('^w');
  Player::Util::sleep($delay);
  
  return 1;
}

sub pra_newWindowForFile { my ($self, $file) = @_;
  my $dir     = $self->pra_scriptDir;
  my $script  = $self->pra_writeLoadScript($file);

  $self->pra_executeScriptInObjectsWindow($script);
  
  # new window takes focus => need to restore later
  $self->storeRefocus;
  
  my $wait = 999;
  printf "Waiting $wait sec Praat opening long sound.\n\n";

  my $win;
  my $elapsed=0;
  # Keep polling
  while (1) {
    $win  = $self->pra_existingWindowForFile($file);

    #my $elapsed = $self->pra_timeElapsed;
    #printf "%s sec since Open command.\n", $elapsed++;

    if (!$win) {
      printf 
        "No response yet to Open command after %d/%dsec.\n", 
          $elapsed, $wait;
    }
    else {
      printf "Found window: %s\n", $win->title;
      last;
    }
    sleep(1);
    last if ++$elapsed>$wait;
  }

  return $win;
}

### play state management for current file

## layer 2 commands: based on layer 1
# Select part of a track range
# track range can be number $i (meaning [$i..$i] or arrayref
sub pra_selectRegion{  my ($self, $trackRange, $start, $end) = @_;
  if (!ref $trackRange) {
    my $i = $trackRange//0;
    $trackRange = [$i, $i];
  }
  my ($tr0, $tr1) = @$trackRange;
  
  $self->pra_doCommand(
    "Select: "
    . "Mode=Range "
    . "FirstTrack=$tr0 LastTrack=$tr1 "
    . "StartTime=$start EndTime=$end"
  );
}

## layer 3 commands: based on layer 1 and 2
sub playRange { my ($self, $t0, $t1, $opt) = @_;
  my $dir = $self->pra_scriptDir;
  my $script = $self->pra_writePlayScript($t0, $t1);
  
  my $title = '^\d+\.\s+LongSound\s+';
  my $win = $opt->{win} || DH::GuiWin->findfirstviewablelike($title);
  return if !$win;
  
  $win->sendto('^{F12}');
  return 1;
}

## selection retrieval

### complete setup for activation of file

## module specific helpers

## locate current stage

sub stageFromLabelRequest { my ($self) = @_;
  my $activeLabel = $self->currentlyActiveShortLabel;

  if ( !$activeLabel ) {
    # file not active, might be connected
    return 3;
  }
  
  # Found an active file
  $self->{knownActiveLabel} = $activeLabel;
  my $targetLabel = $self->targetLabel;
  
  if ( ($activeLabel//'') ne ($targetLabel//'') ) {
    # file not active, might be connected
    return 3;
  }

  # correct file is connected and active
  return 6;
  
}

## establish process

sub exeFile { Player::Util::praat_exe() }

sub startProcess { my ($self) = @_;

  # start the process
  my $com = exeFile();
  if (!Flex::onWin() ) {
    $com = "nohup $com > ~/.nohup/praat.txt \&";
  }
  else {
    $com = qq{start "Start Perl" "$com"};
  }
  print "\nExecuting Command:\n  $com\n";
  system($com);

  # find the picture window, to minimize it
  # so it's not in the way
  my $title = 'Praat Picture';
  print "\nWaiting for window: $title\n";
  my $pictWindow = DH::GuiWin->wait_for_window(
    "^${title}\$" ,
    {maxwait=>10, viewable=>1, verbose=>1} ,
  );
  
  if ($pictWindow) {
   $self->storeRefocus;
    my $s = Flex::onWin() ? '%{SPACE}n' : '%{SPC}n';
    sleep(1);
    $pictWindow->sendto($s);;
    sleep(1);
  }

  # find the object window to focus it
  $title = 'Praat Objects';
  print "\nWaiting for window: $title\n";
  my $mainWindow = DH::GuiWin->wait_for_window(
    "^${title}\$" ,
    {maxwait=>10, viewable=>1, verbose=>1} ,
  );
  
  if ($mainWindow) {
    $self->storeRefocus;
    $mainWindow->setforegroundwindow;
  }
  return $mainWindow && 1;
 
}

## connect to process
sub connectToProcess { my ($self) = @_; 
  my $main = DH::GuiWin->findfirstviewablelike('^Praat Objects$');
  return $main && 1;
}

## activate file when file connection unknown / false / true

sub activateFileIfConnected { shift->activateConnectedFile(@_) }

sub activateNonConnectedFile { my ($self, $file) = @_;
  $file //= $self->targetFile;
  $self->{knownActiveLabel} = undef;
  
  my $win  = $self->pra_newWindowForFile($file);
  return if !$win;
  #$win->setforegroundwindow;
  return 1;
}

sub activateConnectedFile { my ($self, $file) = @_;
  $file    //= $self->targetFile;
  my $win    = $self->pra_existingWindowForFile($file);
  return if !$win;
  
  $self->{knownActiveLabel} = undef;

  $self->storeRefocus;
  $win->setforegroundwindow;
  return 1;
}

### play management with arbitrary file

sub playRangeForFile { my ($self, $file, $t0, $t1, $opt) = @_;
  if (! -e $file) {
    print STDERR "File not found: '$file'\n";
    return;
  }

  # refocusChoice can be set in $self of two different options
  # (for backwards compatibility)
  $self->{refocusChoice} //= $opt->{refocusChoice} // $opt->{refocus};
  
  $self->initializeCommand($file);

  my $ok = $self->prepareForFile;

  if (!$ok) {
    my $file = $self->targetFile;
    print "Failed to activate file '$file' - give up!\n";
    return;
  }
  
  # send stop command, in case playback is running
  #$self->pra_menuCommandWithCheck("Stop");

  $self->playRange($t0, $t1);

  $self->doRefocus;
  $self->cleanupAfterCommand;
}


### utilities

#sub pra_activeItemWindow { my ($self) = @_;
#   my $name = $self->currentlyActiveShortLabel;
#   
#   if (!$name) {
#     print "No current window - don't activate\n#";
#     return;
#   }
# 
#   my $win = DH::GuiWin->findfirstviewablelike("\^$name\$");
#   my $res =
#     $win
#       ? 'Found window named '.$name
#       : 'Did NOT find window named '.$name;
#   print "$res\n#";
#   
#   return $win;
# }
# 
# sub pra_activeItemToForeground { my ($self) = @_;
#   my $win = $self->pra_activeItemWindow;
#   return unless $win;
#   
#   $self->storeRefocus;
#   $win->setforegroundwindow;
#
# }
# 
### to be removed from primary interface

### utilities that are currently not needed

### demo & testing
sub demoFile {
  my $file;
  $file = 'f:/phonmedia/boc/boc_e01.wav';
  $file = Player::Util::flexname($file);
}

sub testreqs {
  my @mods = qw();
  foreach (@mods) {eval "use $_"};
}

sub test201info {'get labels'}
sub test201 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  $class->testreqs;
  my $self = $class->new;
  my $file = $self->demoFile;
  $self->initializeCommand($file);
  $self->prepareForFile;
d::dd;  
  $self->pra_saveProject;

  my $ranges = $self->pra_getLabelsFromSavedProject;
  print $self->dump($ranges);
}

sub test202info {'get selection'}
sub test202 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  $class->testreqs;
  my $self = $class->new;
  my $file = $self->demoFile;
  $self->initializeCommand($file);
  $self->prepareForFile;
d::dd;  
  my @sel = $self->pra_getSelectionFormatted;

  print $self->dump(\@sel);
}

sub test203info {'save project for the first time'}
sub test203 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  $class->testreqs;
  my $self = $class->new;

  my $file = $self->demoFile;
  $self->initializeCommand($file);
  $self->prepareForFile;

  $self->pra_saveProjectFirstTime;
  
}


use DH::Testkit;
sub main {
  print __PACKAGE__ . " meldet sich!\n";
  return __PACKAGE__->test1 if @ARGV==0;
  DH::Testkit::selectTest(__PACKAGE__);
}

if ($0 eq __FILE__) {main();}

1;
