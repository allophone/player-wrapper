package Player::Mplayer;
use strict;
use warnings;
use feature ':5.10'; # loads all features available in perl 5.10
use utf8; # → ju:z ju: tʰi: ɛf eɪt!

use parent 'Player::Base';

use Time::HiRes qw( gettimeofday tv_interval );
use List::Util qw( max );

use DH::ForUtil::Time;
use DH::GuiWin;
use File::Basename;

### Construction

sub build { my ($self) = @_;
  # file locations

  # define pipe names

  if ($^O eq 'MSWin32') {
    my $Name = 'Srv';
    $self->{mpl_toSrvName}    = '\\\\.\\pipe\\To'.$Name.'Pipe';
    $self->{mpl_fromSrvName}  = '\\\\.\\pipe\\From'.$Name.'Pipe';
  } 
  elsif ($^O eq 'linux') {
    my $UID = $<;
    $self->{mpl_toSrvName}    = '/tmp/mplayer_script_pipe.to.'.$UID;
    $self->{mpl_fromSrvName}  = '/tmp/mplayer_script_pipe.from.'.$UID;
  } 
  elsif ($^O eq 'darwin') {
     my $UID = $<;
     $self->{mpl_toSrvName}   = '/tmp/mplayer_script_pipe.to.'.$UID;
     $self->{mpl_fromSrvName} = '/tmp/mplayer_script_pipe.from.'.$UID;
  }

  return $self;
}

sub DESTROY { my ($self) = @_;
  Player::Util::sleep(0.1);
  $self->log( "Read responses before destroy...\n" );
  my @resp = $self->mpl_getResponses;
  for (@resp) { $self->log("  $_\n") }
  $self->mpl_closePipes;
}

### accessors

## miscellaneous properties

sub mpl_mutingMode  { defined $_[0]->{mpl_rangeVolume} }
sub mpl_rangeVolume {         $_[0]->{mpl_rangeVolume} }

## definition of communication channel
sub mpl_toSrvName   { $_[0]->{mpl_toSrvName} }
sub mpl_fromSrvName { $_[0]->{mpl_fromSrvName} }
sub mpl_toSrvFh     { $_[0]->{mpl_toSrvFh} }
sub mpl_fromSrvFh   { $_[0]->{mpl_fromSrvFh} }

## directories
sub mpl_screenshotDir { $_[0]->{mpl_screenshotDir} }
sub mpl_testEffectDir { $_[0]->{mpl_testEffectDir} }

### gateway to audacity

## helpers for innermost layer

# Subroutines for measuring how long a command takes to complete
sub mpl_startTiming{ my ($self) = @_;
  $self->{t0} = [gettimeofday];
}

sub mpl_stopTiming{ my ($self) = @_;
  my $elapsed = $self->mpl_timeElapsed;
  $self->log( "[Total time for command: $elapsed seconds.]\n" );
}

sub mpl_timeElapsed { my ($self) = @_;
  my $t0      = $self->{t0};
  return tv_interval ( $t0, [gettimeofday] );
}

#http://davesource.com/Solutions/20080924.Perl-Non-blocking-Read-On-Pipes-Or-Files.html
# An non-blocking filehandle read that returns an array of lines read
# Returns:  ($eof,@lines)
my %nonblockGetLines_last;
sub nonblockGetLines {	my ($fh,$timeout) = @_;

	$timeout //= 1;
  
	my $rfd = '';
	$nonblockGetLines_last{$fh} = ''
		unless defined $nonblockGetLines_last{$fh};

	vec($rfd,fileno($fh),1) = 1;
	return unless select($rfd, undef, undef, $timeout)>=0;
  
	# I'm not sure the following is necessary?
	return unless vec($rfd,fileno($fh),1);
	my $buf = '';
	my $n = sysread($fh,$buf,1024*1024);
  
	# If we're done, make sure to send the last unfinished line
	return (1,$nonblockGetLines_last{$fh}) unless $n;
  
	# Prepend the last unfinished line
	$buf = $nonblockGetLines_last{$fh}.$buf;

	# And save any newly unfinished lines
	$nonblockGetLines_last{$fh} =
		(substr($buf,-1) !~ /[\r\n]/ && $buf =~ s/([^\r\n]*)$//) ? $1 : '';
    
  return
    $buf ? (0,split(/\n/,$buf)) : (0);
}

## innermost layer

# Write a command to the pipe
sub mpl_sendCommand{ my ($self, $command) = @_;
   my $toSrvFh = $self->{mpl_toSrvFh};

   if ($^O eq 'MSWin32') {
      print $toSrvFh "$command

\r\n\0";
   } 
   else {
      # Don't explicitly send \0 on Linux 
      # or reads after the first one fail...
      print $toSrvFh "$command\n";
   }
   $self->log( "[Command: $command]\n" );
}

# Return an array of all responses
sub mpl_getResponses { my ($self) = @_;
  my $fh = $self->{mpl_fromSrvFh};
   
  my ($eof, @responses) = nonblockGetLines($fh);
  return @responses;
}

# Send (and time) a command, and print responses
sub mpl_doCommand{ my ($self, $command, $opt) = @_;
  # $opt->{pausing} may contain:
  #   'pausing', 'pausing_keep' or 'pausing_toggle'
  my $pau_prefix = $opt->{pausing} // 'pausing_keep';
  $pau_prefix .= ' ' if defined $pau_prefix;

  $self->mpl_startTiming();
  $self->mpl_sendCommand("${pau_prefix}$command");

  my @resps;
  @resps = $self->mpl_getResponses
                  unless $opt->{no_resp};
      
  map { $self->log( "  $_\n" ) } @resps 
                  unless $opt->{ignore_response};

  $self->mpl_stopTiming;
  $self->log("\n");
  return wantarray ? @resps : $resps[0];
}

# mplayer doesn't answer at all for commands w/o return values
# indicate this by option to avoid timeout
sub mpl_doVoidCommand{ my ($self, $command, $opt) = @_;
  $opt//={};
  $self->mpl_doCommand($command, {%$opt, no_resp=>1});
}

sub update {1} # dummy

# This reads values that have their own read command
#   like: $self->mpl_doCommand('get_time_pos')

# See mpl_readProperty for values that are read with the general
# 'get_property' command
#   like: $self->mpl_doCommand('get_property time_pos')

sub mpl_readValue{ my ($self, $name, $opt) = @_;
  
  # auto-prefix name with 'get_' if not there yet
  $name = "get_$name" if $name !~ /^get_/;
  
  my @resp = $self->mpl_doCommand($name, $opt);
  return
    @resp && $resp[0]=~/^ANS_\w+=/
      ? $'
      : undef;
}

sub mpl_readProperty { my ($self, $name, $opt) = @_;
  $self->mpl_readValue("get_property $name", $opt);
}

sub acceptsCommand { my ($self) = @_;
  # arbitrary command to check whehter mplayer listens
  $self->mpl_readProperty('path');
}

### information retrieval through inner-layer command

sub currentlyActiveShortLabel { my ($self) = @_;
  $self->mpl_readProperty('path');
}

### computed player behaviour

# For mplayer I can use the full path instead of some shortened label
# as this is reported by mplayer.

sub shortLabelFromFile { my ($self, $file) = @_;
  return $file;
}

### play state management for current file

sub togglePause { my ($self) = @_;
  $self->mpl_doVoidCommand('pause');
}

sub seek { my ($self, $t, $opt) = @_;
  $opt//={};

  $self->mpl_doCommand(
    "seek $t 2" ,
    {%$opt, no_resp=>1} ,
  );
}

sub position { my ($self, $opt) = @_;
  $self->mpl_readValue('get_time_pos', $opt);
}

sub length { my ($self, $opt) = @_;
  $self->mpl_readValue('get_time_length', $opt);
}

### complete setup for activation of file

## module specific helpers

sub mpl_createPipes{ my ($self) = @_;
  my $to    = $self->{mpl_toSrvName};
  my $from  = $self->{mpl_fromSrvName};
  
  for ($to, $from) {
    if (Flex::onWin()) {
      die "Don't know how to pipes under Windows yet\n";
    }
    else {
      `mkfifo $_`;
    }
  }

}

sub mpl_openPipes{ my ($self) = @_;

  my $toSrvFh   = $self->{mpl_toSrvFh};
  my $fromSrvFh = $self->{mpl_fromSrvFh};
  
  my $t_open = $toSrvFh   && tell($toSrvFh)  >=0;
  my $f_open = $fromSrvFh && tell($fromSrvFh)>=0;
  
  return 1 if $f_open && $t_open;
  
  close $toSrvFh    if $t_open;
  close $fromSrvFh  if $f_open;
  
  my $to    = $self->{mpl_toSrvName};
  my $from  = $self->{mpl_fromSrvName};
  return if ! -e $to;
  return if ! -e $from;

  open( $toSrvFh  , "+<$to"   ) or die "Could not open $to";
  open( $fromSrvFh, "+<$from" ) or die "Could not open $from";

  # The next 'magic incantation' causes TO_SRV to be flushed 
  # every time we write something to it.
  select((select($toSrvFh),$|=1)[0]);

  $self->{mpl_toSrvFh}   = $toSrvFh;
  $self->{mpl_fromSrvFh} = $fromSrvFh;

  return 1;
}

sub mpl_closePipes{ my ($self, $opt) = @_;

  my $toSrvFh   = $self->{mpl_toSrvFh};
  my $fromSrvFh = $self->{mpl_fromSrvFh};
  
  my $t_open = $toSrvFh   && tell($toSrvFh)  >=0;
  my $f_open = $fromSrvFh && tell($fromSrvFh)>=0;
  
  close $toSrvFh    if $t_open;
  close $fromSrvFh  if $f_open;
  
  $self->{mpl_toSrvFh}   = undef;
  $self->{mpl_fromSrvFh} = undef;
  
  if ($opt->{removePipes}) {
    my $to    = $self->{mpl_toSrvName};
    my $from  = $self->{mpl_fromSrvName};
    for ($to, $from) {
      unlink $_ if -e $_;
    }
  }

  return 1;
}

## layer 3 commands: based on layer 1 and 2

sub ensurePaused { my ($self) = @_;
  my $t = $self->mpl_readValue(
    'get_time_pos', {pausing=>'pausing'}
  );
  return defined $t;
}

sub vlc_timedStopInProcess { my ($self, $t1, $opt) = @_;
  # compute argument string
  my $hash = {%$opt, to=>$t1};
  for (qw(host port)) {
    my $val = $self->$_;
    $hash->{$_} = $val if $val;
  }
  my $s    = Player::Util::paramStringFromHash($hash);
  
  # get script
  my $dir  = Player::Util::player_dir();
  my $scr  = "$dir/command_scripts/vlctimedstop.pl";
  $scr =~ s{/}{\\}g if Flex::onWin();
  
  my $com =
    !Flex::onWin()
      ? "perl $scr '$s' \&"
      : "perl $scr '$s'";

  $self->log( "Run command: '$com'\n" );
  system($com);
}

sub mpl_timedStop { my ($self, $t1, $opt) = @_;

  my $t0          = $opt->{seektime};

  $self->log( "\n" );
  my $fmt = "%6s:%12s\n";
  $self->log(   "Timed stop started:\n" );
  $self->logf( $fmt, 'From', Player::Util::ss2hhmmssmmm($t0) );
  $self->logf( $fmt, 'To'  , Player::Util::ss2hhmmssmmm($t1) );
  $self->logf( $fmt, 'dt'  , Player::Util::ss2hhmmssmmm($t1-$t0) );
  $self->log( "\n" );
  
  my ($time);
  my $t0clock = [gettimeofday];
  
  while (1) {
    $time = $t0 + tv_interval($t0clock,[gettimeofday]);
    my $remaining = $t1-$time;
    
    my $timestr = Player::Util::ss2mmssmmm($time);
    # show status if time of status has changed
    my $line = 'mplayer running';
    $self->logf( "%s t=%s left: %8.3f\n",
      $line, $timestr, $remaining
    );
    
    # done when time exceeds end time
    last if $remaining<=0;

    # check whether key was pressed and stop if it was
    my $c = $opt->{allow_interrupt} && Player::Util::readkey();
    if ($c) {
      $self->log( "'$c' pressed - stop playing\n" );
      last;
    }
    
    # wait before checking again
    Player::Util::sleep($remaining>0.1 ? 0.1 : $remaining);

  }

  my $finalseek = $opt->{finalseek};

  my $pause_done;
  
  if (defined $finalseek) {
    $self->seek($finalseek, {pausing=>'pausing'});
    $pause_done ||= 1;
  }
  
  if ($self->mpl_mutingMode) {
    # in muting mode set volume to 0 at end of range
    $self->mpl_doVoidCommand(
      "volume 0 1", 
      {pausing=>'pausing'} ,
    );
    $pause_done ||= 1;
  }
  
  $self->ensurePaused if !$pause_done;
  
  $self->log( "play interval ended\n" );
}

sub playRange { my ($self, $t0, $t1, $opt) = @_;
  
  $self->logf( "play %8.3f-%8.3f\n", $t0, $t1 );

  # if start time not defined, start from current position
  if (!defined $t0) {
    $self->logln(
      "No start time defined - start from current position",
    );
    $self->ensurePaused;
  }
  else {
    $self->seek($t0, {pausing=>'pausing'});
  }

  my $vol = $self->mpl_rangeVolume;
  if (defined $vol) {
    # if volume needs to be set, start playback at the same time
    $self->mpl_doVoidCommand(
      "volume $vol 1", 
      {pausing=>'pausing_toggle'} ,
    );
  }
  else {
    $self->togglePause
  }

  # if end time $t1 is given and larger than $t0, 
  if ($t1>$t0) {

    my $finalseek = $self->videoFinalSeekTime($t0, $t1);
    my $opt1={
      seektime  => $t0, 
      (defined $finalseek ? (finalseek=>$finalseek) : ()) ,
    };

    my $same_process = 1|| Flex::onWin() || $opt->{same_process};
    $same_process
      ? $self->mpl_timedStop($t1, {%$opt1, allow_interrupt=>1})
      : $self->mpl_timedStopInProcess($t1, $opt);
  }
  return 1;
}

## locate current stage

sub stageFromLabelRequest { my ($self) = @_;
  my @resp = $self->mpl_doCommand('get_property path');
  
  if (!@resp) {
    # player didn't respond - assume not running
    return 1;
  }

  # filter path replies
  @resp = map { /^ANS_path=/ ? $' : () } @resp;
  
  # If player responds, but there is no path reply
  # assume it's running without a file connected
  
  # This situation happens in audacity, but I don't think
  # with mplayer this actually occurs
  
  # Consequence is the same as finding a different label than sought
  # i.e. don't know whether file is connected

  if (!@resp) {
    # file not active, might be connected
    return 3;
  }
  
  # Found an active file
  my $activeLabel = $self->{knownActiveLabel} = $resp[-1];
  my $targetLabel = $self->targetLabel;
  
  if ( ($activeLabel//'') ne ($targetLabel//'') ) {
    # file not active, might be connected
    return 3;
  }

  # correct file is connected and active
  return 6;
  
}

## establish process

sub exeFile { Player::Util::mplayer_exe() }

sub startProcess { my ($self, $par) = @_;
  my $file = $par->{with_file};
  
  if (!$file && ! -e $file) {
    $self->log( "Can't start mplayer without input file!\n" );
    return;
  }

  $self->mpl_closePipes({removePipes=>1});
  $self->mpl_createPipes;

  $self->mpl_openPipes;

  my $to    = $self->{mpl_toSrvName};
  my $from  = $self->{mpl_fromSrvName};

  my $exe = $self->exeFile;

  my $com;
  $com = join(' ',
    'nohup'                                   ,
    "'$exe' -slave -quiet -input file='$to'"  ,
    "'$file'"                                 ,
    "> '$from'"                               ,
    '&' ,
  );
  
  $self->log("\n");
  $self->log( "Executing Command:\n" );
  $self->log( "  $com\n\n" );
  system($com);
  
  # remove initial output after giving the process some time
  sleep(1);
  return if !$self->mpl_postLoadCheck($file);

  # seek to beginning and set volume
  $self->seek(0, {pausing=>'pausing'});
  $self->mpl_doVoidCommand('volume 100 1');
  
  return 1;
}

sub endProcess { $_[0]->mpl_doCommand('quit') }

sub mpl_postLoadCheck { my ($self, $file) = @_;
  
  # try 10 sec whether there is a response
  # and whether it contains a 'Playing ... ' line
  # afterwards get responses once more
  
  $self->mpl_startTiming;
  
  my ($playingFound, $finished);
  my $tmax = 10;
  
  my @resp;
  
  $self->log( "Wait for 'Playing' line...\n" );
  while (1) {
    my $elapsed = $self->mpl_timeElapsed;

    # Finish after this round if 'Playing' found previously
    # => one more round than needed for 'Playing'
    $finished = 
         $playingFound 
      || $elapsed >= $tmax;
    
    my @more = $self->mpl_getResponses;
    push @resp, @more;
    
    if (!$playingFound) {
      foreach (@more) {
        $playingFound ||= m{^\s* Playing\s+}x;
        last if $playingFound;
      }
    }
    
    $self->logf( "Elapsed %5.2f/%5.2f sec. Found: %s\n",
      $elapsed,
      $tmax,
      ($playingFound ? 'Yes' : 'No') ,
    );
    
    #last if $finished;
    last if $playingFound;
    Player::Util::sleep(0.1);
  }
  
  
  $self->logf( "Number of initial response lines: %d\n", 0+@resp );
  $self->log('  ');
  for (@resp) {
    $self->log("  $_\n");
  }
  
  return if !@resp;
  
  # try 10x whether active file is correct
  
  my $expect = "ANS_path=$file";
  $self->logln;
  $self->log( "Waiting for reponse '$expect'...\n" );
  my $nwait = 10;
  for my $i (0..$nwait) {
    my @resp = $self->mpl_doCommand(
      'get_property path', {pausing=>'pausing'}
    );
    
    if (@resp==1 && $resp[-1] eq $expect) {
      $self->log( "Correct reply found!\n" );
      return 1;
    }
    
    $self->logf( "Incorrect reply found after %d/%d sec:\n", 
      $i, $nwait
    );
    #for (@resp) { print "  $_\n"}
    
    sleep(1);
  }

  return 1;
}

## connect to process
sub connectToProcess { my ($self) = @_;
  $self->mpl_openPipes;
}

## activate file when file connection unknown / false / true

sub activateFileIfConnected { shift->activateConnectedFile(@_) }

sub activateNonConnectedFile { my ($self, $file) = @_;
  $file //= $self->targetFile;
  $self->{knownActiveLabel} = undef;
  $self->mpl_sendCommand("loadfile $file");
  Player::Util::sleep(1);
  return $self->mpl_postLoadCheck($file);
}

=for me

With mplayer I only use a single connected file which is always activated. So, effectively this routine only checks whether the file is connected.

=cut

sub isFileActive { my ($self, $file) = @_;
  my $targetLabel =
    $file
      ? $self->shortLabelFromFile($file)
      : $self->targetLabel;

  my $activeLabel = $self->currentlyActiveShortLabel;
  
  return 
         $activeLabel 
      && $targetLabel 
      && $activeLabel eq $targetLabel;
}

sub activateConnectedFile { my ($self, $file) = @_;
  $self->isFileActive($file);
}

### play management with arbitrary file

sub playRangeForFile { my ($self, $file, $t0, $t1, $opt) = @_;
  if (! -e $file) {
    print STDERR "File not found: '$file'\n";
    return;
  }
  
  # audacity has a different working dir
  # make sure file names are absolute
  if (! Flex::is_absolute($file) ) {
    $file = Flex::canonAbsPath($file);
  }

  # refocusChoice can be set in $self of two different options
  # (for backwards compatibility)
  $self->{refocusChoice} //= $opt->{refocusChoice} // $opt->{refocus};
  
  $self->initializeCommand($file);

  my $ok = $self->prepareForFile;

  if (!$ok) {
    my $file = $self->targetFile;
    $self->log( "Failed to activate file '$file' - give up!\n" );
    return;
  }
  
  # send stop command, in case playback is running
  #$self->mpl_menuCommandWithCheck("Stop");

  $self->playRange($t0, $t1);

  $self->doRefocus;
  $self->cleanupAfterCommand;
}


### utilities

sub mpl_activeItemWindow { my ($self) = @_;
  my $name = $self->currentlyActiveShortLabel;
  
  if (!$name) {
    $self->log( "No current window - don't activate\n" );
    return;
  }

  my $win = DH::GuiWin->findfirstviewablelike("\^$name\$");
  my $res =
    $win
      ? 'Found window named '.$name
      : 'Did NOT find window named '.$name;
  $self->log( "$res\n" );
  
  return $win;
}

sub mpl_activeItemToForeground { my ($self) = @_;
  my $win = $self->mpl_activeItemWindow;
  return unless $win;
  
  $self->storeRefocus;
  $win->setforegroundwindow;
  
}

### to be removed from primary interface

sub checkForProcess { my ($class, $regex) = @_;
  eval 'use Proc::ProcessTable';

  my $ptab = Proc::ProcessTable->new;
  $regex //= qr{/bin/audacity}x;

  foreach my $p ( @{$ptab->table} ){
    my $cmd = $p->cmndline;
    return $cmd if $cmd =~ /$regex/;
  }
}

### window management

sub activeWindowRegex { my ($self) = @_;
  # In Mplayer only video files have a window
  # and it doesn't have a name specific to the file
  my $curlabel = $self->currentlyActiveShortLabel;
  return if !$self->hasVideoExtension($curlabel);
  return qr{^MPlayer$};
}

### utilities that are currently not needed

sub activateFile { my ($self, $file) = @_;
  my $label     = $self->shortLabelFromFile($file);
  my $curLabel  = $self->currentlyActiveShortLabel;
  $self->log( "label    = $label\n" );
  $self->log( "curlabel = $curLabel\n" );
  return if $label eq $curLabel;
}

### demo & testing
sub demoFile {
  my $file;
  $file = 'F:/phonmedia/FilmAudio/MoodLove.mkv';
  $file = 'E:/perl/proj/player-wrapper/samples/det_countvid.avi';
  $file = Player::Util::flexname($file);
}

sub demoRange { (1.2720, 3.8090) }

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

  $self->mpl_saveProject;

  my $ranges = $self->mpl_getLabelsFromSavedProject;
  print $self->dump($ranges);
}

sub test202info {'get position'}
sub test202 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  $class->testreqs;
  my $self = $class->new;
  my $file = $self->demoFile;
  $self->initializeCommand($file);
  $self->prepareForFile;

  my @resp = $self->mpl_doCommand('pausing_keep get_time_pos');

  print $self->dump(\@resp);

  printf "in one command: p=%s\n", $self->position;
}

sub test203info {'get length'}
sub test203 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  $class->testreqs;
  my $self = $class->new;
  my $file = $self->demoFile;
  $self->initializeCommand($file);
  $self->prepareForFile;

  my @resp = $self->mpl_doCommand('get_time_length');

  print $self->dump(\@resp);
  
  printf "in one command: l=%s\n", $self->length;
}

sub test204info {'seek first arg (default: 1.234)'}
sub test204 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  $class->testreqs;
  my $self = $class->new;
  my $file = $self->demoFile;
  $self->initializeCommand($file);
  $self->prepareForFile;

  my $t = $argv->[0] // 1.234;
  $self->seek($t);

  printf "new position: t=%s\n", $self->position;
}

use DH::Testkit;
sub main {
  print __PACKAGE__ . " meldet sich!\n";
  return __PACKAGE__->test1 if @ARGV==0;
  DH::Testkit::selectTest(__PACKAGE__);
}

if ($0 eq __FILE__) {main();}

1;
