package Player::Audacity;
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
  my $dir = Flex::tmpdir() . "/pipetest";
  Player::Util::createDir($dir);
  $self->{aud_screenshotDir} = $dir;
  $self->{aud_testEffectDir} = $dir;

  # define pipe names

  # TODO: Maybe get the pipe names from audacity?

  if ($^O eq 'MSWin32') {
    my $Name = 'Srv';
    $self->{aud_toSrvName}    = '\\\\.\\pipe\\To'.$Name.'Pipe';
    $self->{aud_fromSrvName}  = '\\\\.\\pipe\\From'.$Name.'Pipe';
  } 
  elsif ($^O eq 'linux') {
    my $UID = $<;
    $self->{aud_toSrvName}    = '/tmp/audacity_script_pipe.to.'.$UID;
    $self->{aud_fromSrvName}  = '/tmp/audacity_script_pipe.from.'.$UID;
  } 
  elsif ($^O eq 'darwin') {
     my $UID = $<;
     $self->{aud_toSrvName}   = '/tmp/audacity_script_pipe.to.'.$UID;
     $self->{aud_fromSrvName} = '/tmp/audacity_script_pipe.from.'.$UID;
  }

  return $self;
}

sub DESTORY { my ($self) = @_;
  $self->aud_closePipes;
}

### accessors

sub verbose { $_[0]->{verbose} }

## definition of communication channel
sub aud_toSrvName   { $_[0]->{aud_toSrvName} }
sub aud_fromSrvName { $_[0]->{aud_fromSrvName} }
sub aud_toSrvFh     { $_[0]->{aud_toSrvFh} }
sub aud_fromSrvFh   { $_[0]->{aud_fromSrvFh} }

## directories
sub aud_screenshotDir { $_[0]->{aud_screenshotDir} }
sub aud_testEffectDir { $_[0]->{aud_testEffectDir} }

### gateway to audacity

## helpers for innermost layer

# Subroutines for measuring how long a command takes to complete
sub aud_startTiming{ my ($self) = @_;
  $self->{t0} = [gettimeofday];
}

sub aud_stopTiming{ my ($self) = @_;
  my $elapsed = $self->aud_timeElapsed;
  print "[Total time for command: $elapsed seconds.]\n";
}

sub aud_timeElapsed { my ($self) = @_;
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
sub aud_sendCommand{ my ($self, $command) = @_;
   my $toSrvFh = $self->{aud_toSrvFh};

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
sub aud_getResponses { my ($self) = @_;
  my $fh = $self->{aud_fromSrvFh};
   
  my ($eof, @responses) = nonblockGetLines($fh);
  return @responses;
}

# Send (and time) a command, and print responses
sub aud_doCommand{ my ($self, $command, $opt) = @_;
   $self->aud_startTiming;
   $self->aud_sendCommand($command);

   my @resps = $self->aud_getResponses;
   map { print "  $_\n"; } @resps 
      unless $opt && $opt->{ignore_response};

   $self->aud_stopTiming;
   print "\n";
   return wantarray ? @resps : $resps[0];
}

# Send a menu command
sub aud_menuCommand{ my ($self, $commandName, $opt) = @_;
  $self->aud_doCommand("MenuCommand: CommandName=$commandName", $opt);
}

# like above, but checks result and repeats after moving to foreground
# This often seems to cure unresponsiveness by Audacity.
sub aud_menuCommandWithCheck { my ($self, $command) = @_;
  my $ntry=3;
  while ($ntry-- > 0) {
    my (@resp) = $self->aud_menuCommand($command);
    my $last   = $resp[-1];
    
    if ($last && $last!~/Failed/) {
      return wantarray ? @resp : $last;
    }
    $self->aud_activeItemToForeground;
  }
}

sub aud_getMenuCommandStatus { my ($self, $command) = @_;
  $self->aud_startTiming;
  $self->aud_sendCommand("GetAllMenuCommands: ShowStatus=1");
  my @resps = $self->aud_getResponses;
  
  my $nshow = 0+@resps;
  $nshow = 4 if $nshow>4;
  printf
    "  Number of response lines %d - show at least %d/%d:\n" ,
    0+@resps, $nshow, 0+@resps;
  for ( @resps[0..$nshow-1]) { print "    $_\n"}

  # search for the important line for $command
  my ($sought, $res);
  my $re = qr{^\Q$command\E\s+(\w+)};
  for my $resp (@resps) {
    next if $resp !~ /$re/;
    ($sought, $res) = ($resp, $1);
    last;
  }

  # if it was found, also show it
  if (defined $sought) {
    for ('...', $sought) { print "    $_\n"}
  }

  $self->aud_stopTiming;
  
  return $res;
}

sub update {1} # dummy

sub acceptsCommand { my ($self) = @_;
  $self->aud_sendCommand(
    "GetTrackInfo: Type=Name TrackIndex=0"
  );
  my @resp = $self->aud_getResponses;

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

  $self->aud_sendCommand(
    "GetTrackInfo: Type=Name TrackIndex=0"
  );
  
  my @resps = $self->aud_getResponses;
  return if @resps<2;
  return if $resps[1]=~m{:\s*Failed!\s*$};
  return $resps[0];

}

### various audacity-only 2nd layer commands

# Get the value of a preference
sub aud_getPref{ my ($self, $name) = @_;
   $self->aud_sendCommand("GetPreference: PrefName=$name");
   my @resps = $self->aud_getResponses;
   return shift(@resps);
}

# Set the value of a preference
sub aud_setPref{ my ($self, $name, $val) = @_;
  $self->aud_doCommand("SetPreference: PrefName=$name PrefValue=$val");
}

# Send a command which requests a list of all available menu commands
sub aud_getMenuCommands{ my ($self) = @_;
  $self->aud_doCommand("GetAllMenuCommands: ShowStatus=0");
}

sub aud_showMenuStatus{ my ($self) = @_;
  $self->aud_sendCommand("GetAllMenuCommands: ShowStatus=1");
  my @resps = $self->aud_getResponses;
  map { print "$_\n"; } @resps;
}

### computed player behaviour

sub shortLabelFromFile { my ($self, $file) = @_;
  my ($name, $path, $ext) 
    = File::Basename::fileparse($file, '\..*');
  return $name;
}

### manage connected files (i.e. files with audacity window)

## helpers for connecting/activating files (by GUI interaction)
sub aud_existingWindowForFile { my ($self, $file) = @_;
  my ($name, $path, $ext) 
    = File::Basename::fileparse( $file, '\..*' );
  my $audwin = DH::GuiWin->findfirstviewablelike("\^$name\$");
  return $audwin;
}

sub aud_newEmptyWindow { my ($self) = @_;
  $self->aud_activeItemToForeground;
  
  my $i=0;
  my $resp;
  while ($i++<10) {
    $resp = $self->aud_menuCommand('New');
    return 1 if $resp && $resp !~ /Failed/;
  }
  return;
}

sub aud_newWindowForFile { my ($self, $file) = @_;
 
  #$self->aud_menuCommand('New');
  $self->aud_newEmptyWindow;
  $self->aud_sendCommand("Import: Filename=$file");
  $self->aud_startTiming;
  
  # new window takes focus => need to restore later
  $self->storeRefocus;

  my $wait = int( (-s $file)/(100e6) );
  printf "Waiting $wait sec for Import command to finish.\n\n";

  # The response to this command might take a while to arrive.
  # Keep polling
  while (1) {
    my @resp = $self->aud_getResponses;

    my $elapsed = $self->aud_timeElapsed;
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
      $self->aud_getTrackInfoItem(0,$f);
      print "\n";
    }
    
    last if --$wait <= 0;
    print "rem time= $wait\n";
    sleep(1);
  }

  $self->aud_menuCommand('FitV');
  
  # derive name of project from file
  # to delete project file from /x
  my $label = $self->shortLabelFromFile($file);
  $self->aud_removeProjectFile($label);

  my $audWindow = $self->aud_existingWindowForFile($file);
  # nicer to have it in top left corner
  $audWindow->movewindow(0,0) if $audWindow;

  return $audWindow;
}

### play state management for current file

## layer 2 commands: based on layer 1
# Select part of a track range
# track range can be number $i (meaning [$i..$i] or arrayref
sub aud_selectRegion{  my ($self, $trackRange, $start, $end) = @_;
  if (!ref $trackRange) {
    my $i = $trackRange//0;
    $trackRange = [$i, $i];
  }
  my ($tr0, $tr1) = @$trackRange;
  
  $self->aud_doCommand(
    "Select: "
    . "Mode=Range "
    . "FirstTrack=$tr0 LastTrack=$tr1 "
    . "StartTime=$start EndTime=$end"
  );
}

sub aud_getTrackInfoItem{  my ($self, $trackID, $type) = @_;
  $trackID//=0;
  $type   //='Name';
  
  my (@resp, $val);
  my $n=10;
  
  while ($n-- > 0) {
    @resp = $self->aud_doCommand(
      "GetTrackInfo: Type=$type TrackIndex=$trackID"
    );
  
    $val = $resp[0];
    
    if (      $type eq 'EndTime' 
          && (!defined $val || $val =~ /[^\d\.]/) 
    ) {
      printf "Invalid response (len=%d):\n", 0+@resp;
      for (@resp) {print "$_\n"}
      print "\n";
      next;
    }
    last;
  }
  
  return wantarray ? @resp : $val;
}

# faster version: only check track 1 to distinguish stereo and mono
sub aud_standardTrackRange { my ($self, $name) = @_;
=for me

Need to compare the labels of track 0 and 1.
To save one lookup, first try to obtain label of track 0 from arg or $self->knownActiveLabel.

=cut
  
  $name 
    //= $self->knownActiveLabel
    //  $self->aud_doCommand("GetTrackInfo: Type=Name TrackIndex=0")//'';
  
  my ($name1) = 
    $self->aud_doCommand("GetTrackInfo: Type=Name TrackIndex=1")//'';
  
  return
    $name eq $name1
      ? (0,1)
      : (0,0);
}

## layer 3 commands: based on layer 1 and 2
sub playRange { my ($self, $t0, $t1) = @_;
  # adapt times that are beyond end of file

  my $tmax = $self->aud_getTrackInfoItem(0, 'EndTime')//0;

  if ($t1>$tmax) {$t1 =$tmax-0.001;}
  if ($t0>$t1  ) {$t0 =$t1  -0.001;}

  # work out the track region to apply selection to
  my @trackRange = $self->aud_standardTrackRange;
  my $res = $self->aud_selectRegion(\@trackRange, $t0, $t1);

  $self->aud_menuCommand('ZoomSel');
  my $ok = $self->aud_menuCommandWithCheck('PlayStop');
  $self->aud_menuCommand('FitV');
  return $ok;
}

sub playCurrentSelection { my ($self, $t0, $t1) = @_;
  $self->aud_menuCommandWithCheck('PlayStop');
}

## selection retrieval

sub aud_removeProjectFile { my ($self, $name) = @_;
  my $file = $self->aud_projectFile($name);
  unlink $file if -e $file;
}

sub aud_projectFile { my ($self, $name) = @_;
  $name
    //= $self->knownActiveLabel
    //  $self->aud_getTrackInfoItem(0,'Name');
  return if !$name;

  return "/x/$name.aup";
}

sub aud_getLabelsFromSavedProject { my ($self, $projFile) = @_;
  $projFile //= $self->aud_projectFile;
  
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

sub aud_saveProjectFirstTime { my ($self, $file) = @_;
  $file //= $self->aud_projectFile;
  my $win = $self->aud_activeItemWindow;
  return if !$win;

  $self->storeRefocus;
  $win->setforegroundwindow;

  #$win->setforegroundwindow;
  #sleep(1);
  my $ok = $self->aud_sendCommand('MenuCommand: CommandName=Save');

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
  DH::ForUtil::Time::sleep($delay);

  $dialog->sendto("^(a)");
  DH::ForUtil::Time::sleep($delay);

  $dialog->sendto($file);
  DH::ForUtil::Time::sleep($delay);

  $dialog->sendto('~');

  print
    "\n",
    "All keystrokes for saving project file sent.\n",
    "Wait 1 more sec before retrieving response to Save command.\n" ,
    "\n",
  ;
  sleep(1); 
 
  $self->aud_startTiming;

  print "[Retrieving response...]\n";
  my @resp = $self->aud_getResponses;
  foreach (@resp) { print "  $_\n"; }
  $self->aud_stopTiming;
  
  return 1;
}

sub aud_saveProject { my ($self, $file) = @_;
  $file //= $self->aud_projectFile;
  
  if (! -e $file ) {
    my $ok = $self->aud_saveProjectFirstTime;
    if (!$ok) {
      print "Failed to save project. Give up.\n";
      return;
    }
  
    if (! -e $file) {
      print "Project file still missing after saveProjectFirstTime. Give up.\n";
      return;
    }
  }
  
  my $status = $self->aud_getMenuCommandStatus('Save');
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
  #my $projFile = $self->aud_projectFile($file);
  
  my $resp = $self->aud_menuCommand('Save');
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
    DH::ForUtil::Time::sleep(0.1);
  }
  
  return 1;
}

=for me

For unknown reasons, the Save command is often considered disabled by Audacity when it should be enabled. The save command will be reported as disabled and executing it result in a failure message.

A workaround seems to be to send the window to the foreground. Keep trying this until 'Enabled' is reported (at most 100x).

=cut

sub aud_enableSaveCommand { my ($self, $opt) = @_;
  
  my $status;
  for (my $i=0; $i<10; $i++) {
    $status = $self->aud_getMenuCommandStatus('Save');
    last if $status && $status eq 'Enabled';
    printf "Status of 'Save' command: %s\n", ($status//'<undef>');
    $self->aud_activeItemToForeground;
    DH::ForUtil::Time::sleep(0.01);
  }
  
  return $status;
}

sub aud_getSelection { my ($self, $opt) = @_;
  $self->aud_menuCommand('Stop', {ignore_response=>1});
  
  my $file = $self->aud_projectFile;
  
  my $ok = $self->aud_saveProject($file);
  return if !$ok;

  my $before = $self->aud_getLabelsFromSavedProject($file);
  return if !$before;
  
  # First adjust selection to zero crossing
  $self->aud_menuCommand('ZeroCross');
  
  $self->aud_menuCommand('AddLabel');
  
  $self->aud_enableSaveCommand($opt);
  
  $self->aud_saveProject($file);
  my $after  = $self->aud_getLabelsFromSavedProject($file);
  
  # get rid of the label again
  $self->aud_menuCommand('Undo');
  
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

sub aud_getSelectionFormatted { my ($self, $opt) = @_;
  my $sel = $self->aud_getSelection($opt);
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

sub aud_openPipes{ my ($self) = @_;

  my $toSrvFh   = $self->{aud_toSrvFh};
  my $fromSrvFh = $self->{aud_fromSrvFh};
  
  my $t_open = $toSrvFh   && tell($toSrvFh)  >=0;
  my $f_open = $fromSrvFh && tell($fromSrvFh)>=0;
  
  return 1 if $f_open && $t_open;
  
  close $toSrvFh    if $t_open;
  close $fromSrvFh  if $f_open;
  
  my $to    = $self->{aud_toSrvName};
  my $from  = $self->{aud_fromSrvName};
  return if (! -e $to);
  return if (! -e $from);

  open( $toSrvFh  , "+<$to"   ) or die "Could not open $to";
  open( $fromSrvFh, "+<$from" ) or die "Could not open $from";

  # The next 'magic incantation' causes TO_SRV to be flushed 
  # every time we write something to it.
  select((select($toSrvFh),$|=1)[0]);

  $self->{aud_toSrvFh}   = $toSrvFh;
  $self->{aud_fromSrvFh} = $fromSrvFh;

  return 1;
}

sub aud_closePipes{ my ($self) = @_;

  my $toSrvFh   = $self->{aud_toSrvFh};
  my $fromSrvFh = $self->{aud_fromSrvFh};
  
  my $t_open = $toSrvFh   && tell($toSrvFh)  >=0;
  my $f_open = $fromSrvFh && tell($fromSrvFh)>=0;
  
  close $toSrvFh    if $t_open;
  close $fromSrvFh  if $f_open;
  
  $self->{aud_toSrvFh}   = undef;
  $self->{aud_fromSrvFh} = undef;

  return 1;
}

## locate current stage

sub stageFromLabelRequest { my ($self) = @_;
  $self->aud_sendCommand(
    "GetTrackInfo: Type=Name TrackIndex=0"
  );
  my @resp = $self->aud_getResponses;
  
  if (@resp<2) {
    # player didn't respond - assume not running
    return 1;
  }
  
  # If player responds, but there is no track, the response is:
  
  #  TrackIndex was invalid.
  #  GetTrackInfo finished: Failed!
  
  # Consequence is the same as find a different label than sought
  # i.e. don't know whether file is connected
  
  if ( ($resp[1]//'') !~ m{finished:\s+OK\s*$} ) {
    # file not active, might be connected
    return 3;
  }
  
  # Found an active file
  my $activeLabel = $self->{knownActiveLabel} = $resp[0];
  my $targetLabel = $self->targetLabel;
  
  if ( ($activeLabel//'') ne ($targetLabel//'') ) {
    # file not active, might be connected
    return 3;
  }

  # correct file is connected and active
  return 6;
  
}

## establish process

sub exeFile { Player::Util::audacity_exe() }

sub startProcess { my ($self, $par) = @_;
  my $fileForCommandLine = $par->{with_file};
  
  $self->aud_closePipes;
 
  my $com = "'" . exeFile() . "'";
  $com .= " '$fileForCommandLine'" if $fileForCommandLine;
  print "\nExecuting Command:\n  $com\n";
  `$com`;

  my $title = 'Module Loader';
  print "\nWaiting for window: $title\n";
  my $moduleWindow = DH::GuiWin->wait_for_window(
    "^${title}\$" ,
    {maxwait=>10, viewable=>1, verbose=>1} ,
  );

  if ($moduleWindow) {
    $title = $moduleWindow->title;
    DH::Sendkeys::sendto($title, "\n");
  }

  my $label;
  
  if ($fileForCommandLine && (-e $fileForCommandLine) ) {
    # if there is a file, derive the label (and save it for later)
    # and use it as title of track window
    $label = $self->shortLabelFromFile( $fileForCommandLine );
    $title = $label;
  }
  else {
    # no file => title is fixed and no label
    $title = 'Audacity';
  }

  print "\nWaiting for window: $title\n";
  my $audWindow = DH::GuiWin->wait_for_window(
    "^${title}\$" ,
    {maxwait=>30, viewable=>1, verbose=>1} ,
  );

  # if import succeeded make sure stale project file is removed
  $self->aud_removeProjectFile($label);

  return $audWindow ? 1 : undef;
}

## connect to process
sub connectToProcess { my ($self) = @_;
  $self->aud_openPipes;
}

## activate file when file connection unknown / false / true

sub activateFileIfConnected { shift->activateConnectedFile(@_) }

sub activateNonConnectedFile { my ($self, $file) = @_;
  $file //= $self->targetFile;
  $self->{knownActiveLabel} = undef;
  
  my $win  = $self->aud_newWindowForFile($file);
  return if !$win;
  #$win->setforegroundwindow;
  return 1;
}

sub activateConnectedFile { my ($self, $file) = @_;
  $file //= $self->targetFile;
  my $win  = $self->aud_existingWindowForFile($file);
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
  
  # audacity has a different working dir
  # make sure file names are absolute
  if ($file && !Flex::is_absolute($file) ) {
    $file = Flex::canonAbsPath($file);
  }

  # refocusChoice can be set in $self of two different options
  # (for backwards compatibility)
  $self->{refocusChoice} //= $opt->{refocusChoice} // $opt->{refocus};
  
  $self->initializeCommand($file);

  my $ok = $self->prepareForFile;

  if (!$ok) {
    my $file = $self->targetFile // '<undef>';
    print "Failed to activate file '$file' - give up!\n";
    return;
  }
  
  # send stop command, in case playback is running
  #$self->aud_menuCommandWithCheck("Stop");

  $opt->{cursel}
    ? $self->playCurrentSelection
    : $self->playRange($t0, $t1);

  $self->doRefocus;
  $self->cleanupAfterCommand;
}


### utilities

sub aud_activeItemWindow { my ($self) = @_;
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

sub aud_activeItemToForeground { my ($self) = @_;
  my $win = $self->aud_activeItemWindow;
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

sub windowTitle { my ($self) = @_;
  $self->ensureCommunication;
  
  $self->aud_sendCommand(
    "GetTrackInfo: Type=Name TrackIndex=0"
  );
  
  my @resps = $self->aud_getResponses;
  
  # no response => audacity not running
  return if @resps<2;
  
  # response, but no track => assume window called 'Audacity'
  if ( $resps[1]=~m{:\s*Failed!\s*$} ) {
    return 'Audacity';
  }
  
  # current track found => windowname = track name
  return $resps[0];

}

### demo & testing
sub demoFile {
  my $file;
  $file = 'F:/phonmedia/FilmAudio/MoodLove.wav';
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
  $self->aud_saveProject;

  my $ranges = $self->aud_getLabelsFromSavedProject;
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
  my @sel = $self->aud_getSelectionFormatted;

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

  $self->aud_saveProjectFirstTime;
  
}


use DH::Testkit;
sub main {
  print __PACKAGE__ . " meldet sich!\n";
  return __PACKAGE__->test1 if @ARGV==0;
  DH::Testkit::selectTest(__PACKAGE__);
}

if ($0 eq __FILE__) {main();}

1;
