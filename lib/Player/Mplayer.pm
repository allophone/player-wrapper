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
  print "Read responses before destroy...\n";
  d::dd;
  my @resp = $self->mpl_getResponses;
  for (@resp) { print "  $_\n";}
  $self->mpl_closePipes;
}

### accessors

sub verbose { $_[0]->{verbose} }

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
  print "[Total time for command: $elapsed seconds.]\n";
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
   print "[$command]\n";
}

# Return an array of all responses
sub mpl_getResponses { my ($self) = @_;
  my $fh = $self->{mpl_fromSrvFh};
   
  my ($eof, @responses) = nonblockGetLines($fh);
  return @responses;
}

# Send (and time) a command, and print responses
sub mpl_doCommand{ my ($self, $command, $opt) = @_;
   $self->mpl_startTiming();
   $self->mpl_sendCommand($command);

   my @resps = $self->mpl_getResponses;
   map { print "  $_\n"; } @resps 
      unless $opt && $opt->{ignore_response};

   $self->mpl_stopTiming;
   print "\n";
   return wantarray ? @resps : $resps[0];
}

# Send a menu command
sub mpl_menuCommand{ my ($self, $commandName, $opt) = @_;
  $self->mpl_doCommand("MenuCommand: CommandName=$commandName", $opt);
}

# like above, but checks result and repeats after moving to foreground
# This often seems to cure unresponsiveness by Audacity.
sub mpl_menuCommandWithCheck { my ($self, $command) = @_;
  my $ntry=3;
  while ($ntry-- > 0) {
    my ($resp) = $self->mpl_menuCommand($command);
    
    if ($resp && $resp!~/Failed/) {
      return 1;
    }
    $self->mpl_activeItemToForeground;
  }
}

sub update {1} # dummy

sub acceptsCommand { my ($self) = @_;
  $self->mpl_sendCommand(
    "GetTrackInfo: Type=Name TrackIndex=0"
  );
  my @resp = $self->mpl_getResponses;

  # check whether name of track 0 was found
  # if so, store it, so the info doesn't get lost
  if (@resp>=2) {
    if ( ($resp[1]//'') !~ m{finished:\s+OK\s*$} ) {
      $self->{knownActiveLabel} = $resp[1];
    }
  }
 
  # for the purpose of checking whether Audacity responds
  # @resp>2 is enough
  return @resp>=2;
}

### information retrieval through inner-layer command

sub currentlyActiveShortLabel { my ($self) = @_;
  my @resp = $self->mpl_doCommand('get_property path');
  return if !@resp;
  
  @resp = map { /^ANS_path=/ ? $' : () } @resp;
  
  return if !@resp;
  
  return $resp[-1];
}

### various audacity-only 2nd layer commands

# Get the value of a preference
sub mpl_getPref{ my ($self, $name) = @_;
   $self->mpl_sendCommand("GetPreference: PrefName=$name");
   my @resps = $self->mpl_getResponses;
   return shift(@resps);
}

# Set the value of a preference
sub mpl_setPref{ my ($self, $name, $val) = @_;
  $self->mpl_doCommand("SetPreference: PrefName=$name PrefValue=$val");
}

# Send a command which requests a list of all available menu commands
sub mpl_getMenuCommands{ my ($self) = @_;
  $self->mpl_doCommand("GetAllMenuCommands: ShowStatus=0");
}

sub mpl_showMenuStatus{ my ($self) = @_;
  $self->mpl_sendCommand("GetAllMenuCommands: ShowStatus=1");
  my @resps = $self->mpl_getResponses;
  map { print "$_\n"; } @resps;
}

sub mpl_getMenuCommandStatus { my ($self, $command) = @_;
  $self->mpl_sendCommand("GetAllMenuCommands: ShowStatus=1");
  my @resps = $self->mpl_getResponses;
  my $re = qr{^\Q$command\E\s+(\w+)};
  foreach my $resp (@resps) {
    next if $resp !~ /$re/;
    return $1;
  }
  return undef;
}

### computed player behaviour

# For mplayer I can use the full path instead of some shortened label
# as this is reported by mplayer.

sub shortLabelFromFile { my ($self, $file) = @_;
  return $file;
}

### manage connected files (i.e. files with audacity window)

## helpers for connecting/activating files (by GUI interaction)
sub mpl_existingWindowForFile { my ($self, $file) = @_;
  my ($name, $path, $ext) 
    = File::Basename::fileparse( $file, '\..*' );
  my $audwin = DH::GuiWin->findfirstviewablelike("\^$name\$");
  return $audwin;
}

sub mpl_newEmptyWindow { my ($self) = @_;
  $self->mpl_activeItemToForeground;
  
  my $i=0;
  my $resp;
  while ($i++<10) {
    $resp = $self->mpl_menuCommand('New');
    return 1 if $resp && $resp !~ /Failed/;
  }
  return;
}

sub mpl_newWindowForFile { my ($self, $file) = @_;
 
  #$self->mpl_menuCommand('New');
  $self->mpl_newEmptyWindow;
  $self->mpl_sendCommand("Import: Filename=$file");
  $self->mpl_startTiming;
  
  # new window takes focus => need to restore later
  $self->storeRefocus;

  my $wait = int( (-s $file)/(100e6) );
  printf "Waiting $wait sec for Import command to finish.\n\n";

  # The response to this command might take a while to arrive.
  # Keep polling
  while (1) {
    my @resp = $self->mpl_getResponses;

    my $elapsed = $self->mpl_timeElapsed;
    printf "%s sec since Import command.\n", $elapsed;

    if (!@resp) {
      print "No response yet to Import command.\n";
    }
    else {
      print "Received response:\n";
      foreach (@resp,) {
        print "  $_\n";
      }
    }
    print "\n";
    
    last if $resp[-1] && $resp[-1]=~m{Import\s+finished:\s+OK\s*$};
    last if $elapsed>$wait;
    
  }
  

  $wait = 1;
  while (1) {
    print "\nQuery Name and EndTime to check import okay:\n\n";
    
    foreach my $f (qw(Name EndTime)) {
      $self->mpl_getTrackInfoItem(0,$f);
      print "\n";
    }
    
    last if --$wait <= 0;
    print "rem time= $wait\n";
    sleep(1);
  }

  $self->mpl_menuCommand('FitV');
  
  # derive name of project from file
  # to delete project file from /x
  my ($name, $path, $suf) 
    = File::Basename::fileparse( $file, '\..*' );
  my $proj = "/x/$name.aup";
  if (-e $proj) {
    unlink $proj;
  }

  my $audWindow = $self->mpl_existingWindowForFile($file);
  # nicer to have it in top left corner
  $audWindow->movewindow(0,0) if $audWindow;

  return $audWindow;
}

### play state management for current file

## layer 2 commands: based on layer 1
# Select part of a track range
# track range can be number $i (meaning [$i..$i] or arrayref
sub mpl_selectRegion{  my ($self, $trackRange, $start, $end) = @_;
  if (!ref $trackRange) {
    my $i = $trackRange//0;
    $trackRange = [$i, $i];
  }
  my ($tr0, $tr1) = @$trackRange;
  
  $self->mpl_doCommand(
    "Select: "
    . "Mode=Range "
    . "FirstTrack=$tr0 LastTrack=$tr1 "
    . "StartTime=$start EndTime=$end"
  );
}

sub mpl_getTrackInfoItem{  my ($self, $trackID, $type) = @_;
  $trackID//=0;
  $type   //='Name';
  
  my (@resp, $val);
  my $n=10;
  
  while ($n-- > 0) {
    @resp = $self->mpl_doCommand(
      "GetTrackInfo: Type=$type TrackIndex=$trackID"
    );
  
    $val = $resp[0];
    if ($type eq 'EndTime' && $val =~ /[^\d\.]/) {
      print "Invalid response:\n";
      for (@resp) {print "$_\n"}
      print "\n";
      next;
    }
    last;
  }
  
  return wantarray ? @resp : $val;
}

# faster version: only check track 1 to distinguish stereo and mono
sub mpl_standardTrackRange { my ($self, $name) = @_;
=for me

Need to compare the labels of track 0 and 1.
To save one lookup, first try to obtain label of track 0 from arg or $self->knownActiveLabel.

=cut
  
  $name 
    //= $self->knownActiveLabel
    //  $self->mpl_doCommand("GetTrackInfo: Type=Name TrackIndex=0")//'';
  
  my ($name1) = 
    $self->mpl_doCommand("GetTrackInfo: Type=Name TrackIndex=1")//'';
  
  return
    $name eq $name1
      ? (0,1)
      : (0,0);
}

## layer 3 commands: based on layer 1 and 2
sub playRange { my ($self, $t0, $t1) = @_;
  # adapt times that are beyond end of file

  my $tmax = $self->mpl_getTrackInfoItem(0, 'EndTime')//0;

  if ($t1>$tmax) {$t1 =$tmax-0.001;}
  if ($t0>$t1  ) {$t0 =$t1  -0.001;}

  # work out the track region to apply selection to
  my @trackRange = $self->mpl_standardTrackRange;
  my $res = $self->mpl_selectRegion(\@trackRange, $t0, $t1);

  $self->mpl_menuCommand('ZoomSel');
  $self->mpl_menuCommandWithCheck('PlayStop');
}

## selection retrieval

sub mpl_projectFile { my ($self, $name) = @_;
  $name
    //= $self->knownActiveLabel
    //  $self->mpl_getTrackInfoItem(0,'Name');
  return if !$name;

  return "/x/$name.aup";
}

sub mpl_getLabelsFromSavedProject { my ($self, $projFile) = @_;
  $projFile //= $self->mpl_projectFile;
  
  # extract label lines
  my $sref  = Player::Util::slurp_to_ref($projFile);
  my @ranges;
  
  if ($sref && $$sref) {
    while (
      $$sref =~ m{
        \<label        \s+
        t     = "([\d\.]+)" \s+
        t1    = "([\d\.]+)" \s+
        title = "(.*?)"     \s*
        /?\>
      }xg
    )
    {
      push @ranges, 
        sprintf "%16.7f %16.7f", $1, $2;
    }
  }
  return wantarray ? @ranges : \@ranges;
}

sub mpl_saveProjectFirstTime { my ($self, $file) = @_;
  $file //= $self->mpl_projectFile;
  my $win = $self->mpl_activeItemWindow;
  return if !$win;

  $self->storeRefocus;
  $win->setforegroundwindow;

  #$win->setforegroundwindow;
  #sleep(1);
  my $ok = $self->mpl_sendCommand('MenuCommand: CommandName=Save');

  #$win->sendto('^(f)');
  #sleep(1);
  #$win->sendto('s');
  
  my $name = $win->title;
  my $title = qq{^Save Project.*"$name".*As};
  printf "Wait for window: '%s'\n", $title;
  my $dialog = DH::GuiWin->wait_for_window(
    $title ,
    {maxwait=>5, viewable=>1, verbose=>1} ,
  );
  
  my $delay = 0.3;
  return if !$dialog;
  
  $dialog->sendto("^(n)");
  Player::Util::sleep($delay);

  $dialog->sendto("^(a)");
  Player::Util::sleep($delay);

  $dialog->sendto($file);
  Player::Util::sleep($delay);

  $dialog->sendto('~');
  
  my @resp = $self->mpl_getResponses;
  foreach (@resp) { print "  $_\n"; }
  
  return 1;
}

sub mpl_saveProject { my ($self, $file) = @_;
  $file //= $self->mpl_projectFile;
  
  if (! -e $file ) {
    my $ok = $self->mpl_saveProjectFirstTime;
    if (!$ok) {
      print "Failed to save project. Give up.\n";
      return;
    }
  
    if (! -e $file) {
      print "Project file still missing after saveProjectFirstTime. Give up.\n";
      return;
    }
  }
  
  my $status = $self->mpl_getMenuCommandStatus('Save');
  if (!$status || $status ne 'Enabled') {
    print "\n";
    printf "Status of menu command 'Save': %s\n", ($status//'<undef>');
    printf "Assume there was nothing to save\n";;
    return 1;
  }
  
  # store atime/mtime before Save command
  my ($atime0, $mtime0) = (stat($file))[8,9];
  
  # make file 1 sec younger
  $mtime0 -= 1;
  $atime0 //= $mtime0;
  utime $atime0, $mtime0, $file;
  
  printf "mtime for '$file' before Save: %18.6f\n", $mtime0;
  
  # save project to file
  #my $projFile = $self->mpl_projectFile($file);
  
  my $resp = $self->mpl_menuCommand('Save');
  if ($resp =~ /failed/i) {
    print "'Save' failed: $resp\n";
    return;
  }
  
  # if project file didn't exist yet, audacity will ask
  
  # => doesn't work, sendCommand doesn't return before command finished
  #    maybe work around later...
  
  # capture window and enter filename
  #if (! -e $projFile) {
  #  my $win = DH::GuiWin->wait_for_window('Save\s+Project');
  #  if ($win) {
  #    my $title = $win->title;
  #    my $s = "\%a${projFile}{enter}";
  #    DH::Sendkeys::sendto($title, $s);
  #    sleep(1);
  #  }
  #}

  if (! -e $file) {
    print "project '$file' not found\n";
    return;
  }

  # wait for file to change
  for (my $i=0; $i<100; $i++) {
    my $mtime = $^T - 86400*(-M $file);
    printf "mtime for '$file' after Save: %18.6f\n", $mtime;
    
    last if $mtime > $mtime0;
    Player::Util::sleep(0.1);
  }
  
  return 1;
}

=for me

For unknown reasons, the Save command is often considered disabled by Audacity when it should be enabled. The save command will be reported as disabled and executing it result in a failure message.

A workaround seems to be to send the window to the foreground. Keep trying this until 'Enabled' is reported (at most 100x).

=cut

sub mpl_enableSaveCommand { my ($self, $opt) = @_;
  
  my $status;
  for (my $i=0; $i<100; $i++) {
    $status = $self->mpl_getMenuCommandStatus('Save');
    last if $status && $status eq 'Enabled';
    printf "Status of 'Save' command: %s\n", ($status//'<undef>');
    $self->mpl_activeItemToForeground;
    Player::Util::sleep(0.01);
  }
  
  return $status;
}

sub mpl_getSelection { my ($self, $opt) = @_;
  $self->mpl_menuCommand('Stop', {ignore_response=>1});
  
  my $file = $self->mpl_projectFile;
  
  my $ok = $self->mpl_saveProject($file);
  return if !$ok;

  my $before = $self->mpl_getLabelsFromSavedProject($file);
  return if !$before;
  
  # First adjust selection to zero crossing
  $self->mpl_menuCommand('ZeroCross');
  
  $self->mpl_menuCommand('AddLabel');
  
  $self->mpl_enableSaveCommand($opt);
  
  $self->mpl_saveProject($file);
  my $after  = $self->mpl_getLabelsFromSavedProject($file);
  
  # get rid of the label again
  $self->mpl_menuCommand('Undo');
  
  return if !$after;
  
  my $bfHash = Player::Util::multiplicity_hash($before, {base=>1});
  my $afHash = Player::Util::multiplicity_hash($after , {base=>1});
  my @new;
  foreach my $s (@$after) {
    next if ($bfHash->{$s}//0) >= ($afHash->{$s}//0);
    push @new, $s;
  }
  return $new[0];
}

sub mpl_getSelectionFormatted { my ($self, $opt) = @_;
  my $sel = $self->mpl_getSelection($opt);
  if ($sel) {
    #print "sel=$sel\n";
    $sel = Player::Util::trimWhite($sel);
    my ($t1, $t2) = split /\s+/, $sel;
    my ($t0s, $dts) = Player::Util::secs2tableTimes($t1, $t2);
    return ($t0s, "[$dts]");
  }
  else {
    print "Failed to retrieve selection\n";
    return ();
  }
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
    print "Can't start mplayer without input file!\n";
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
  
  print "\nExecuting Command:\n  $com\n\n";
  system($com);
  
  # remove initial output after giving the process some time
  sleep(1);
  $self->mpl_postLoadCheck($file);

  # window is only opened with video, not for audio
  
  #my $title = 'Mplayer';
  #print "\nWaiting for window: $title\n";
  #my $mplwin = DH::GuiWin->wait_for_window(
  #  "^${title}\$" ,
  #  {maxwait=>10, viewable=>1, verbose=>1} ,
  #);
  
  #return $mplwin ? 1 : undef;
}

sub mpl_postLoadCheck { my ($self, $file) = @_;
  
  # try 10 sec whether there is a response
  # and whether it contains a 'Playing ... ' line
  # afterwards get responses once more
  
  $self->mpl_startTiming;
  
  my ($playingFound, $finished);
  my $tmax = 10;
  
  my @resp;
  
  print "Wait for 'Playing' line...\n";
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
    
    printf "Elapsed %5.2f/%5.2f sec. Found: %s\n",
      $elapsed,
      $tmax,
      ($playingFound ? 'Yes' : 'No');
    
    #last if $finished;
    last if $playingFound;
    Player::Util::sleep(0.1);
  }
  
  
  printf "number of initial response lines: %d\n", 0+@resp;
  print '  ', join("  \n", @resp), "\n";
  
  return if !@resp;
  
  # try 10x whether active file is correct
  
  my $expect = "ANS_path=$file";
  print "\nWaiting for reponse '$expect'...\n";
  my $nwait = 10;
  for my $i (0..$nwait) {
    my @resp = $self->mpl_doCommand('get_property path');
    
    if (@resp==1 && $resp[-1] eq $expect) {
      print "Correct reply found!\n";
      return 1;
    }
    
    printf "Incorrect reply found after %d/%d sec:\n", $i, $nwait;
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
d::dd;
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
    print "Failed to activate file '$file' - give up!\n";
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
    print "No current window - don't activate\n";
    return;
  }

  my $win = DH::GuiWin->findfirstviewablelike("\^$name\$");
  my $res =
    $win
      ? 'Found window named '.$name
      : 'Did NOT find window named '.$name;
  print "$res\n";
  
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

### utilities that are currently not needed

sub activateFile { my ($self, $file) = @_;
  my $label     = $self->shortLabelFromFile($file);
  my $curLabel  = $self->currentlyActiveShortLabel;
  print "label    = $label\n";
  print "curlabel = $curLabel\n";
  return if $label eq $curLabel;
}

### demo & testing
sub demoFile {
  my $file;
  $file = 'F:/phonmedia/FilmAudio/MoodLove.mkv';
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
  $self->mpl_saveProject;

  my $ranges = $self->mpl_getLabelsFromSavedProject;
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
  my @sel = $self->mpl_getSelectionFormatted;

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

  $self->mpl_saveProjectFirstTime;
  
}


use DH::Testkit;
sub main {
  print __PACKAGE__ . " meldet sich!\n";
  return __PACKAGE__->test1 if @ARGV==0;
  DH::Testkit::selectTest(__PACKAGE__);
}

if ($0 eq __FILE__) {main();}

1;
