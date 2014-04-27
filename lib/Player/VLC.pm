package Player::VLC;
use strict;
use warnings;
use feature ':5.10'; # loads all features available in perl 5.10
use utf8; # → ju:z ju: tʰi: ɛf eɪt!

use parent 'Player::Base';

### Construction

sub build { my ($self, $par) = @_;

  # host and port may be provided in a single parameter or separately
  # default for host:port like: 'c:8090'

  my ($host, $port) = split /:/, ($par->{host}//'');
  $self->{port} = $port ||= $par->{port} || 8090;
  $host ||= Player::Util::default_vlc_host();
  my $sub = Player::Util::remote_path_sub($host);
  $self->{remote_path_sub} = $sub if $sub;
  
  $self->{auth_key} = 'Basic Ond3';
  
  $self->{host}    = $host;
  return $self;
}

### accessors

sub verbose  { $_[0]->{verbose}  }

## definition of communication channel

sub host        { $_[0]->{host} }
sub port        { $_[0]->{port} }
sub auth_key    { $_[0]->{auth_key} }
sub remote_path_sub { $_[0]->{remote_path_sub} }

## for caching the response
sub vlc_response { $_[0]->{vlc_response} }

sub vlc_responseDom { my ($self) = @_;
  # use existing dom, if present
  my $dom = $self->{_vlc_reponse_dom};
  return $dom if $dom;
  
  # use existing response if present
  my $resp = $self->{vlc_response}||$self->vlc_command;
  
  return $self->{_vlc_response_dom} = $self->string2dom(\$resp);
}

### gateway to vlc

## helpers for innermost layer
sub getUrl { my ($self, $url) = @_;
  my $auth_key   = $self->auth_key;
  my $onwin = Player::Util::onWin();

  if ( !$onwin ) {
    state $tmpdir = Player::Util::tmpdir();
    
    #my $out   = "$tmpdir/wget.txt";
    #unlink $out if (-e $out);
    
    my $log   = "$tmpdir/wgetlog.txt";
    my $header_opt =
      $auth_key
        ? qq{ --header="Authorization: $auth_key"}
        : '';
    
    my $res = `wget$header_opt -O - -o '$log' '$url'`;
    return $res;
  }

  #state $loaded = Player::Util::load_on_demand('LWP::Simple');
  #return LWP::Simple::get($url); 

  state $loaded = Player::Util::load_on_demand('LWP::UserAgent');
  my $ua = LWP::UserAgent->new;
  $ua->timeout(10);
  $ua->env_proxy;
  $ua->default_header('Authorization' => $auth_key);
  my $response = $ua->get($url);
  if (!$response->is_success) {
    $self->logf( "Retrieving url '%s' failed with status '%s'!\n",
      $url,
      $response->status_line
    )
  }
  return $response->decoded_content;
}

## innermost layer for most commands

sub vlc_command { my ($self, $com, $opt) = @_;
  
  my $verbose = $self->verbose;
  
  # create url for command
  my $url = $self->vlc_baseUrl;
  $url .= '/requests/status.xml';
  $url .= "?command=$com" if $com;
  
  # val and input appended if provided
  foreach my $param ('val', 'input', 'id') {
    my $paramval = $opt->{$param};
    if ( ($paramval//'') eq '') {next;}
    printf STDERR 
      "%-6s='%s' (%s)\n", 
      $param, $paramval, (defined $paramval)
                                        if $verbose;
    $url .= "\&$param=$paramval";
  }
  print STDERR "url='$url'\n" if $verbose;
  
  # dispose of old dom (if any) and mark dom as non-existent
  my $olddom = $self->{_vlc_responseDom};
  $olddom->dispose if $olddom;
  $self->{_vlc_reponseDom} = undef;
  
  # mark cached status as invalid
  $self->{vlc_status}     = undef;
  
  $self->{vlc_response}     = $self->getUrl($url);
}

sub update { my ($self) = @_;
  $self->vlc_command;
  return $self;
}

sub acceptsCommand { my ($self) = @_;
  return $self->vlc_command;
}

## innermost layer for playlist command

sub vlc_playlistResponseRef { my ($self) = @_;
  my $url  = $self->vlc_baseUrl;
  $url    .= "/requests/playlist.xml";
  print STDERR "url='$url'\n" if $self->verbose;
  
  my $xml = $self->getUrl($url); 
  return if !$xml;
  return \$xml;
}

sub vlc_playlistDom { my ($self) = @_;
  my $xmlref = $self->vlc_playlistResponseRef;
  return undef if !$xmlref;
  return $self->string2dom($xmlref);
}

sub vlc_retrievePlaylist { my ($self) = @_;
  shift->vlc_retrievePlaylist_byRegex(@_);
  #shift->vlc_retrievePlaylist_proper_xml(@_);
}

sub vlc_retrievePlaylist_byRegex { my ($self, $xmlref) = @_;
  my $playlist_hoh = {};
  $xmlref //= $self->vlc_playlistResponseRef;
  return $playlist_hoh if !$xmlref;

  state $qu = qr{["']};

=for me

Response to /requests/playlist.xml looks like:

<node ro="rw" name="Undefined" id="1">
  <node ro="ro" name="Playlist" id="2">
  
    <leaf ro="rw" name="fric.wav" id="4" duration="8"
  uri="file:///home/detlev/windrive/f/phon/detlev/fric.wav"/>

    <leaf ro="rw" name="lanyu.avi" id="5" duration="5186"
  uri="file:///home/detlev/windrive/f/phonmedia/FilmAudio/lanyu.avi"/>

  </node>
  
  <node ro="ro" name="Media Library" id="3"/>

</node>

=cut


  # regex for step 1: find <node...> with name="Playlist"
  state $re1 = qr{
    <node \s+ ro=${qu}\w+${qu} \s+ name=${qu}Playlist${qu} [^>]* >
      \s*
      (.*?)
    </node>
  }xs;

  # regex for step 2: <leaf...> inside above <node...>
  state $re2 = qr{ <leaf \s* ([^>]*) /\s*> }xs;

  # regex for step 3: attributes in <leaf...>
  state $re3 = qr{ (\w+)=${qu}(.*?)${qu} }xs;

  # loop over <node...> named "Playlist"
  while ( $$xmlref =~ /$re1/g ) {
    my $leaves = $1;
    
    # loop over <leaf ... />
    while ( $leaves =~ /$re2/g ) {
      my $attrs = $1;
      $self->log("leaf:\n");
      $self->log("$attrs\n");
      my $r = {};
      # loop over attrs
      while ($attrs =~ /$re3/g) {
        $r->{$1} = $2;
        $self->logf( "%s->%s\n", $1, $2 );
      }
      # item is labeled by uri (without 'file://'), i.e. the filename
      my $uri   = $r->{uri}//'';
      my $label =
        $uri =~ m{^file://}
          ? $'
          : $uri;
    
      $playlist_hoh->{$label} = $r;
    }
  }

  return $playlist_hoh;

}

sub vlc_retrievePlaylist_proper_xml { my ($self) = @_;
  # Each node represents an item in the playlist
  # Create a hashref: $playlist_hoh->{$label} = $itemRecord
  # Use the filename of each item as label

  my $playlist_hoh = {};
  my $dom   = $self->vlc_playlistDom;
  return $playlist_hoh if !$dom;
  
  my $nodes = $dom->findnodes( q{//node[@name='Playlist']/leaf} );
  # should also be possible:
  #   $nodes = [ $doc->getElementsByTagName('leaf') ];


  for my $node (@$nodes) {
    # Turn each node into an item hash
    
    my $r = {};
    my $attrNodes = $node->getAttributes;
    for my $i (0..$attrNodes->getLength-1) {
      my $attr = $attrNodes->item($i);
      my $attrname = $attr->getNodeName;
      $r->{$attrname} = $attr->getNodeValue;
    }
    
    # item is labeled by uri (without 'file://'), i.e. the filename
    my $uri   = $r->{uri}//'';
    my $label =
      $uri =~ m{^file://}
        ? $'
        : $uri;
    
    $playlist_hoh->{$label} = $r;
  }
  
  return $playlist_hoh;
}

### information retrieval from last inner-layer response (non-refreshing!)

sub vlc_status { my ($self) = @_;
  my $status = 
        $self->{vlc_status}
    //= $self->vlc_status_byRegex;
}

sub vlc_status_byRegex { my ($self) = @_;
  my $s = $self->{vlc_response};
  my @lines = split /\r?\n/ , $s;
  
  my $r;
  for (@lines) {
    next if ! m{^ \s* <(\w+)> \s* (.*?) \s* </\1>}x;
    $r->{$1} = $2;
  }  
  return $r;
}

sub vlc_status_proper_xml { my ($self) = @_;
  
  my $dom   = $self->vlc_responseDom;
  my @nodes = $dom->getFirstChild->getChildNodes;
    
  my $r;
  foreach my $n (@nodes) {
    my $key = $n->getNodeName;
    my $c   = $n->getFirstChild;
    next if !$c;
    $r->{$key} = $c->getNodeValue;
  }
  
  return $r;
}

sub vlc_state { my ($self) = @_;
  my $status = $self->vlc_status;
  return $status->{state}//'';
}

# return current position in seconds (including fractional part)
sub vlc_position { my ($self) = @_;
  my $status = $self->vlc_status;
  my ($len, $pos) = ($status->{length}//0, $status->{position}//0);
  
  # old-fangled position is not a fraction of total length
  # return time
  if ($pos>1) {
    return $status->{time};
  }
  
  return $len*$pos;
}

sub vlc_statusLine { my ($self) = @_;
  my $r = $self->vlc_status;
  
  my $pos = Player::Util::ss2mmssmmm($r->{time}//0  , {ndigit=>0});
  my $len = Player::Util::ss2mmssmmm($r->{length}//0, {ndigit=>0});
  
  my $state = $r->{state}//'<undef>';

  my $title = $self->currentlyActiveShortLabel//'<undef>';
  if (length($title)>30) { $title = "..." . substr($title,-30) }
  return sprintf "%20s: %-6s/%-6s - %s",$state,$pos,$len, $title;
}

sub currentlyActiveShortLabel_byRegex { my ($self) = @_;

  state $qu = qr{["']};

=for me

new-fangled:

<information>
  <category name="meta">
    <info name="filename">boc_e01.mp4</info>
  </category>
...
</information>

=cut
  state $re = qr{
    <information>
      .*?
      <category\s+name=${qu}meta${qu} \s* >
        .*?
        <info\s+ name=${qu}filename${qu} \s* > (.*?) </info>
        .*?
      </category>
      .*?
    </information>
  }xs;

  return $1 if ($self->{vlc_response}//'') =~ /$re/;

=for me

old-fangled:

<information>
  <meta-information>
    <title>F:\phonmedia\FilmAudio\lanyu.avi</title>
    ...
  </meta-information>
  ...
</information>

=cut

  state $re_old = qr{
    <information>
      .*?
      <meta\-information\s*>
        .*?
        <title \s* > (.*?) </title>
        .*?
      </meta\-information>
      .*?
    </information>
  }xs;


  if ( ($self->{vlc_response}//'') =~ /$re_old/ ) {
    my $file = $1;
    if ($file && $file=~m{^ <!\[CDATA\[ (.*?) \]\]> $}x ) {
      $file = $1;
    }
    return $file;
  }

  return;
}

sub currentlyActiveShortLabel_proper_xml { my ($self) = @_;

  my $dom  = $self->vlc_responseDom;
  my ($node) = $dom->findnodes(
    q{/root/information/category[@name='meta']/info[@name='filename'}
  );
  return undef if !$node;
  
  my $child = $node->getFirstChild;
  return undef if !$child;
  
  return $child->getNodeValue;
}

sub currentlyActiveShortLabel { my ($self) = @_;
  my $file = $self->currentlyActiveShortLabel_byRegex;
  return if !$file;
  if ($file =~ m{ [\\\/] ([^\\\/]+) $}x) {
    $file = $1;
  }
  return $file;
}

### helpers for command sequences

sub vlc_waitForState { my ($self, $target_state, $intro, $opt) = @_;
  # target state can be supplied as regex or string
  my $re = $target_state;
  if (!ref $re) {
    $re = qr/^\Q$target_state\E$/;
  }
  
  $intro ||= "Waiting for state '$target_state'\n";
  (undef, undef, my $line) = caller;
  $self->logf( "%s (line %d)\n", $intro, $line );

  my $wait = $opt->{timeout} || 10;
  while ($wait-- > 0) {
    my $status = $self->vlc_status;

    $self->logf( "%2d: %s\n", $wait, $self->vlc_statusLine );
    if ($status->{state} =~ /$re/) { 
      $self->log( "Success\n" );
      return 1; 
    }
    sleep(1);
    
    # refresh info
    $self->vlc_command;
  }
  $self->log( "Timeout.\n" );
  return undef;
}

sub vlc_waitForActiveLabelAndLength { my ($self, $label, $intro, $opt) = @_;
  # target state can be supplied as regex or string
  my $re = $label;
  if (!ref $re) {
    $re = qr/^\Q$label\E$/;
  }
  
  $intro ||= "Waiting for label '$label'\n";
  (undef, undef, my $line) = caller;
  $self->logf( "%s (line %d)\n", $intro, $line );

  my $wait = $opt->{timeout} || 10;
  while ($wait-- > 0) {
    my $curLabel = $self->currentlyActiveShortLabel//'';
    my $status   = $self->vlc_status;
    
    my $ok = defined $status;
    my $length   = ($ok && $self->vlc_status->{length})//0;
    $self->logf( "%2d: %s\n", $wait, $self->vlc_statusLine );
    
    $ok   &&= $curLabel =~ /$re/;
    $ok   &&= $length>0;
    
    if ($ok) {
      $self->log( "Success\n" );
      return 1; 
    }
    sleep(1);
    
    # refresh info
    $self->update;
  }
  $self->log( "Timeout.\n" );
  return undef;
}

### various vlc-only 2nd layer commands

sub openItemsLongLabels { my ($self) = @_;
  my $playlist_hoh = $self->vlc_retrievePlaylist;
  my @labesl = sort keys %$playlist_hoh;
}

### computed player behaviour

sub shortLabelFromFile { my ($self, $file) = @_;
  my ($name, $path, $ext) 
    = File::Basename::fileparse($file, '\..*');
  return "$name$ext";
}

### manage connected files (i.e. files in playlist)

sub vlc_playId { my ($self, $id) = @_;
  $self->vlc_command('pl_play', {id=>$id});
}

# $mrl can be file or url
sub vlc_inPlay { my ($self, $mrl) = @_;
  $mrl =~ s/\\/\\\\/g;
  $mrl = encodeURIComponent($mrl);
  # args = command, val, input  
  $self->vlc_command('in_play',{input=>$mrl});
}

### play state management for current file

## layer 2 commands: based on layer 1
sub togglePause { $_[0]->vlc_command('pl_pause') }
sub stop        { $_[0]->vlc_command('pl_stop' ) }
sub seek        { my ($self, $val) = @_;
  $val = int(time_in_sec($val));
  $self->vlc_command('seek', {val=>$val});
}
sub position { shift->vlc_position }
sub length   { my ($self) = @_;
  my $status = $self->vlc_status;
  return $status && $status->{length};
}

# seekable positions close to $_[1] (in secs.)
sub previousSeekable { int( $_[1]     ) }
sub nearestSeekable  { int( $_[1]+0.5 ) }

## layer 3 commands: based on layer 1 and 2
sub ensurePaused { my ($self) = @_;
  # wait until connected (any state: playing/stopped/paused)
  $self->vlc_waitForState(
    qr/^(playing|stopped|paused)/,
    "Wait to be connected..."
  ) or return;
  
  my $state = $self->vlc_state;
  
  # if paused, we're done
  return if $state eq 'paused';
  
  # if stopped, I need to play first, then pause
  if ($state eq 'stopped') {
    $self->togglePause;
    $self->vlc_waitForState(
      'playing',
      "Wait for 'playing'..."
    ) or return;
    $state = $self->vlc_state;
  }

  if ($state eq 'playing') {
    $self->log( "State 'playing' found. Pausing before seek.\n" );
    $self->togglePause;
    $self->log( $self->vlc_statusLine."\n" );
    $state = $self->vlc_state;
  }
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

sub vlc_timedStop { my ($self, $t1, $opt) = @_;

  # If current playback time is known from previous seek,
  # it can be used for extra accuracy
  # by computing a correction to the time reported by
  # $vlc->position;
  my $reported_t0 = $self->vlc_position;
  my $t0          = $opt->{seektime} // $reported_t0;

  $self->log( "\n" );
  my $fmt = "%6s:%12s\n";
  $self->log(   "Play interval:\n" );
  $self->logf( $fmt, 'From', Player::Util::ss2hhmmssmmm($t0) );
  $self->logf( $fmt, 'To'  , Player::Util::ss2hhmmssmmm($t1) );
  $self->logf( $fmt, 'dt'  , Player::Util::ss2hhmmssmmm($t1-$t0) );
  $self->log( "\n" );
  
  # with $vlc_position I can get the current time with fractional
  # part, but it's imprecise, because it's based on the total
  # length, which is only known as integer.
  # Since I just sought $t0 (which was made integer) I should
  # know the current time now and I can use it to compute a correction
  
  my $corr = $t0 - $reported_t0;
  $self->logf(
    $fmt, 't0-rep' , Player::Util::ss2hhmmssmmm($reported_t0)
  );
  $self->logf(
    $fmt, 'Corr'   , Player::Util::ss2hhmmssmmm($corr)
  );
  $self->log( "\n" ); 
  
  # However, it seems to stop a bit earlier than the required time
  # Workaround: Allow an excess
  my $excess = 0.0;

  my ($prevtime, $done, $time);
  $prevtime = -1;
  
  while (!$done) {
    my $status = $self->vlc_status;
    my $state  = $status->{state};

    if ( ($state//'') ne 'playing' ) {
      $self->log( "State no longer 'playing' - exit playback loop\n" );
      last;
    }
    $time = $self->vlc_position;
    $time += $corr;
    
    #      printf "time=%s\n",$time;
    if ($time ne $prevtime) {
      my $timestr = Player::Util::ss2mmssmmm($time);
      # show status if time of status has changed
      my $line = $self->vlc_statusLine($status);
      $self->logf( "%s t=%s left: %8.3f\n",
        $line, $timestr, $t1-$time
      );
    }
    
    # done when time exceeds end time
    last if $time-$t1>$excess && $prevtime;

    # check whether key was pressed and stop if it was
    my $c = $opt->{allow_interrupt} && Player::Util::readkey();
    if ($c) {
      $self->log( "'$c' pressed - stop playing\n" );
      $done = 1;
    }

    # wait before checking again
    Player::Util::sleep(0.1);
    $self->update;

    # prepare for next iteration
    $prevtime = $time;
  }

  if ($self->vlc_state eq 'playing') {
    $self->togglePause;
    
    my $finalseek = $opt->{finalseek};
    $self->seek($finalseek) if defined $finalseek;
  }
  $self->log( "play interval ended\n" );
}

sub playRange { my ($self, $t0, $t1, $opt) = @_;
  
  $self->logf( "play [%.3f,%.3f]\n", $t0, $t1 );

  my ($status, $state);
  
  $status = $self->update->vlc_status//{};
  $state  = $status->{state}//'';
  
  # can't seek while stopped
  # if stopped, start and pause
  if ($state =~ m{^ (playing|paused) $}) {
    $self->togglePause;
    
    
    my $ok =  $self->vlc_waitForState(
                'playing',
                'Starting stopped item'
              );
              
    if (!$ok) {
      $self->log( "Failed to start current file\n" );
      return;
    }
    
    $status = $self->update->vlc_status//{};
    $state  = $status->{state}//'';
  }

  # seek start point of interval
  my $t0was = $t0;
  $t0 = int($t0);
  $status     = $self->vlc_status;
  my $length  = $status->{length};
  if ($t0>$length) {
    $self->logf(
      "Start time exceeds length (%d sec) - ignored\n",
      $length
    );
  }
  else {
    $self->seek($t0);
    $state = $self->vlc_state;
  }
  
  # start vlc at start time and wait for acknowledgement
  $self->togglePause;
  $self->vlc_waitForState(
    'playing', "Wait for 'playing' before loop"
  ) or return;
  
  # if end time $t1 is given and larger than $t0, 
  # pause after the interval
  # provide the time of last seek for better accuracy
  
  if ($t1>$t0) {
    my $finalseek = $self->videoFinalSeekTime($t0was, $t1);
    my $opt1={
      seektime  => $t0, 
      (defined $finalseek ? (finalseek=>$finalseek) : ()) ,
    };
    
    my $same_process = Flex::onWin() || $opt->{same_process};
    $same_process
      ? $self->vlc_timedStop($t1, {%$opt1, allow_interrupt=>1})
      : $self->vlc_timedStopInProcess($t1, $opt1);
  }
  return 1;
}

### complete setup for activation of file

## module specific helpers

sub vlc_baseUrl { my ($self) = @_;
  my ($host, $port) = @{$self}{qw(host port)};
  my $url = "http://$host";
  if ($port && $port != 80) { $url .= sprintf ":%d",$port; }
  return $url;
}

## locate current stage

sub stageFromLabelRequest { my ($self) = @_;
  my $resp = $self->update->vlc_response;
  
  if (!$resp) {
    # player didn't respond - assume not running
    return 1;
  }
  
  # If player responds, but there is no track, the response empty
  my $curLabel = $self->currentlyActiveShortLabel//'';
  
  # Consequence is the same as find a different label than sought
  # i.e. don't know whether file is connected
  
  if ( !$curLabel ) {
    # file not active, but might be connected
    return 3;
  }
  
  # Found an active file
  my $activeLabel = $self->{knownActiveLabel} = $curLabel;
  my $targetLabel = $self->targetLabel;
  
  if ( ($activeLabel//'') ne ($targetLabel//'') ) {
    # file not active, but might be connected
    return 3;
  }

  # correct file is connected and active
  return 6;
  
}

## establish process

sub vlc_pidForCommand { my ($self, $com) = @_;
  eval 'use Proc::ProcessTable';
  my $ptab = Proc::ProcessTable->new;
  $com =~ s{\s{2,}}{ }g;
  for my $p (@{$ptab->table}) {
    next if $p->cmndline ne $com;
    return $p->pid;
  }
}

sub exeFile { goto &Player::Util::vlc_exe }

sub startProcess { my ($self, $par) = @_;
  my $file = $par->{must_use_file} && $par->{with_file};
  
  my $exe = $self->exeFile;
  
  my $host     = $self->{host};
  my $port     = $self->{port};
  my $hostport = "--http-host $host --http-port $port ";
  #my $hostport = $self->{host} .':'.$self->{port};
  
  my ($nohup0, $nohup1, $amp);
  if ($^O !~ /^win/i) {
    $nohup0 = "nohup ";
    $nohup1 = ">/tmp/nohup_vlc_${host}_${port}";
    $amp   = " \&";
  }
  
  my $com0 = "$exe $hostport --extraintf http";
  $com0 .= " '$file'" if $file;

  # some decoration around $com0 to decouple process from this script
  my $com = "$nohup0$com0$nohup1$amp";
    
  $self->log( "Executing '$com'\n" );
  system($com);
  
  my $pid = $self->{playerPID} = $self->vlc_pidForCommand($com0);
  $self->log("Created vlc process with pid=$pid\n");
  
  my $wait = 30;
  my $success;
  while (! ($success=$self->acceptsCommand) ) {
    if ($wait-- < 1) {last;}
    $self->logf(
      "vlc not running. Waiting %d more seconds...\n" , 
      $wait
    );
    sleep(1);
  }
  
  # wait 1 more sec for vlc to become usable
  # (if too fast, it will open player in separate window)
  sleep(1);
  #$self->ensurePaused;
  
  return $success;
}

sub endProcess { $_[0]->killPlayer }

## connect to process
sub connectToProcess {1} # nothing to do in VLC, always succeeds

## activate file when file connection unknown / false / true

sub activateFileIfConnected { shift->activateConnectedFile(@_) }

sub activateNonConnectedFile { my ($self, $file) = @_;
  $file //= $self->targetFile;
  return if ! -e $file;

  my $label = $self->shortLabelFromFile($file);
  
  # Possible transform the file to an equivalent
  # (for example path on a remote machine)
  my $remote_path_sub = $self->remote_path_sub;
  if ($remote_path_sub) {
    $file = $remote_path_sub->($file);
  }

  $self->vlc_inPlay($file);

  $self->vlc_waitForActiveLabelAndLength(
    $label,
    "Wait for label and length '$label'..."
  ) or return;

  $self->{knownActiveLabel} = $label;

  $self->vlc_waitForState(
    'playing',
    "Wait for 'playing'..."
  ) or return;

  $self->ensurePaused;
  return 1;
}

sub activateConnectedFile { my ($self, $fileOrRec) = @_;
  my ($rec, $file);
  
  if ($fileOrRec && ref $fileOrRec eq 'HASH') {
    # playlist record already provided
    # filename can be derived from it
    $rec = $fileOrRec;
    $file = $rec->{uri};
    $file =~ s{^file://}{};
  }
  
  else {
    # file provided as string or default=targetFile
    $file = $fileOrRec || $self->targetFile;

    # retrieve playlist and find corresponding record
    my $playlist_hoh = $self->vlc_retrievePlaylist;
    $rec = $playlist_hoh->{$file};
    
    # if no record, file isn't in playlist yet, return false
    return if !$rec;
  }
  
  my $id    = $rec->{id};
  my $label = $self->shortLabelFromFile($file);

  $self->vlc_playId($id);

  $self->vlc_waitForActiveLabelAndLength(
    $label,
    "Wait for label '$label'..."
  ) or return;

  $self->{knownActiveLabel} = $label;

  $self->vlc_waitForState(
    'playing',
    "Wait for 'playing'..."
  ) or return;

  $self->ensurePaused;
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
  
  $self->storeRefocus;
  $self->initializeCommand($file);
  
  # first set up process only to check whether current state='playing'
  my $ok = $self->prepareForFile({upto=>3});
  
  if (!$ok) {
    $self->log( "Couldn't communicate with VLC - give up!\n" );
    return;
  }
  
  # if command is received while playing, only pause
  # (helpful to interrupt player by pressing same key again)
  if ($self->vlc_state eq 'playing') {
    $self->togglePause;
    return;
  }

  # now set up all the way up to active file
  $ok = $self->prepareForFile;

  if (!$ok) {
    my $file = $self->targetFile;
    $self->log( "Failed to activate file '$file' - give up!\n" );
    return;
  }

  $self->playRange($t0, $t1);

  $self->doRefocus;
  $self->cleanupAfterCommand;
}


### utilities

sub string2dom { my ($class, $s) = @_;
  my $sref = ref $s eq 'SCALAR' ? $s : \$s;
  
  Player::Util::load_on_demand('XML::DOM');
  Player::Util::load_on_demand('XML::DOM::XPath');
  Player::Util::load_on_demand('XML::DOM::Parser');
  
  my $parser = XML::DOM::Parser->new;
  my $dom = eval {$parser->parse($$sref)};
  if ($@) {
    print STDERR "Parsing of string failed with error:\n$@\n";
    return;
  }
  return $dom;
}

sub time_in_sec { my ($time) = @_;
  if ($time =~ /(\d+:|)(\d+:|)([\d\.]*)$/) {
    $time = 3600*($1||0) + 60*($2||0) + $3;
  }
  return $time;
}

sub encodeURIComponent { my ($s) = @_;
  $s =~ s/([^0-9A-Za-z!'()*\-._~])/sprintf("%%%02X", ord($1))/eg;
  return $s;
}

### window management

sub activeWindowRegex { my ($self) = @_;
  # In VLC active file has title equal to short label
  # followed by ' - VLC media player'
  my $curlabel = $self->currentlyActiveShortLabel;
  return qr{^\Q$curlabel\E\s+.\s+VLC\s+media\s+player$};
}

### utilities that are currently not needed

sub vlc_recOfConnectedFile { my ($self, $file) = @_;
  my $playlist_hoh = $self->vlc_retrievePlaylist;
  return $playlist_hoh->{$file};
}

sub activateFile { my ($self, $file) = @_;
  # first check whether file is active already
  my $label     = $self->shortLabelFromFile($file) // '<undef>';
  my $curLabel  = $self->currentlyActiveShortLabel // '<undef>';
  $self->logf( "label    = %s\n", $label      );
  $self->logf( "curlabel = %s\n", $curLabel   );
  return 1 if $label eq $curLabel;

  # then try activating file in playlist
  my $rec = $self->vlc_recOfConnectedFile($file);
  if ($rec) {
    $self->activateConnectedFile($rec);
    return 1;
  }
  
  # finally open a new file
  $self->activateNonConnectedFile($file);
 
}

### demo & testing
sub demoFile {
  my $file;
  $file = 'F:/phonmedia/FilmAudio/lanyu.avi';
  $file = 'F:/phon/chn_au/shawn5a.wav';
  $file = 'E:/perl/proj/player-wrapper/samples/det_countvid.avi';
  $file = Player::Util::flexname($file);
}

sub demoRange { (1,3) }

sub testreqs {
  my @mods = qw(Data::Dumper);
  foreach (@mods) {eval "use $_"};
  eval '$Data::Dumper::Indent=1';
}

sub test201info {'playlist response'}
sub test201 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  $class->testreqs;
  my $self = $class->new;
  $self->ensureCommunication;
  my $xmlref = $self->vlc_playlistResponseRef;
  $xmlref //= \"<undef>";
  
  printf "Response:\n%s\n", $$xmlref;  
}

sub test202info {'parse playlist by proper xml parsing'}
sub test202 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  $class->testreqs;
  
  my $self = $class->new;
  $self->ensureCommunication;
  my $playlist_hoh = $self->vlc_retrievePlaylist_proper_xml;
  
  print Data::Dumper::Dumper( $playlist_hoh );
}

sub test203info {'parse playlist by regex'}
sub test203 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  $class->testreqs;
  
  my $self = $class->new;
  $self->ensureCommunication;
  my $playlist_hoh = $self->vlc_retrievePlaylist_byRegex;
  
  print Data::Dumper::Dumper( $playlist_hoh );
}

use DH::Testkit;
sub main {
  print __PACKAGE__ . " meldet sich!\n";
  return __PACKAGE__->test1 if @ARGV==0;
  DH::Testkit::selectTest(__PACKAGE__);
}

if ($0 eq __FILE__) {main();}

1;
