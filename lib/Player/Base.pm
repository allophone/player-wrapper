package Player::Base;
use strict;
use warnings;
use feature ':5.10'; # loads all features available in perl 5.10
use utf8; # → ju:z ju: tʰi: ɛf eɪt!

use Player::Util;
use File::Basename ();

### constructor

sub new { my ($self) = shift @_;
  my $par = {};
  if (@_>1) {
    $par = { @_ };
  }
  elsif (@_==1 && ref $_[0] eq 'HASH') {
    $par = $_[0];
  }
  my $class = ref $self || $self;
  $self = bless {%$par}, $class;
  $self->build($par);
}

### accessors

sub verbose { $_[0]->{verbose} }

sub t0      { $_[0]->{t0} }

## params valid during single command execution
sub stage             { $_[0]->{stage} }
sub knownActiveLabel  { $_[0]->{knownActiveLabel} }
sub targetFile        { $_[0]->{targetFile} }
sub targetLabel       { $_[0]->{targetLabel} }

## refocussing
sub refocusChoice    { $_[0]->{refocusChoice} }
sub refocusWin       { $_[0]->{refocusWin} }
sub refocusNeeded    { $_[0]->{refocusNeeded} }

### stages

sub initializeCommand { my ($self, $file) = @_;
  $self->{stage}            = -1;
  $self->{knownActiveLabel} = undef;
  $self->{targetFile}       = $file;
  $self->{targetLabel}      = 
    $file && $self->shortLabelFromFile($file);
  return $self;
}

sub cleanupAfterCommand { my ($self, $file) = @_;
  $self->{stage}            = -1;
  $self->{knownActiveLabel} = undef;
  $self->{targetFile}       = undef;
  $self->{targetLabel}      = undef;
  $self->{refocusWin}       = undef;
  return $self;
}

sub prepareForFile { my ($self, $opt) = @_;
  my $stage = $self->{stage}//-1;
  
  my $upto = $opt->{upto} // 6;
  
  # if no file to activate, maximum stage is 3
  my $file = $self->targetFile;
  if (!$file && $upto>3) {$upto=3}
  
  my $n=0;
  
  while ($stage<$upto && ++$n<=10) {
    # stage<0: status of player unknown
    if ($stage<0) {
      # Try whether player responds as it should if it's running
      my $success = $self->connectToProcess;
      if (!$success) {
        # player not responding, start process first
        $stage = 1;   
      }
      else {
        # determine stage by talking to player
        $stage = $self->stageFromLabelRequest;
      }
    }
    
    # process needs to be started
    elsif ($stage<=1) {
      my $success = $self->startProcess({with_file=>$file});
      $stage = $success ? 2 : undef;
    }
    
    # pipes need to be opened
    elsif ($stage<=2) {
      my $success = $self->connectToProcess;
      $stage = $success ? 3 : undef;
    }
    
    # try whether file is connected and activate if so
    elsif ($stage<=3) {
      my $success = $self->activateConnectedFile;
      $stage = 
        $success 
          ? 6   # connected and active
          : 4   # not connected
      ;
    }

    # connect to file that's not yet connected
    elsif ($stage<=4) {
      my $success = $self->activateNonConnectedFile;
      $stage = 
        $success 
          ? 6       # connected and active
          : undef  # something went wrong
      ;
    }

    # activate a file that's connected
    #  => similar handling as for unknown file
    elsif ($stage<=5) {
      my $success = $self->activateConnectedFile;
      $stage = 
        $success 
          ? 6       # connected and active
          : undef  # not connected: here an error condition
      ;
    }

    # Failure if processing resulted in falsy $stage
    $self->{stage} = $stage;
    if (!$stage) {
      printf "Failed preparing for file!\n";
      return;
    }
    
    printf "Moved to stage $stage\n";
  }
  return $stage;
}

# more self explanatory convenience command
# also works without file, then initialize for current file
sub ensureCommunication { my ($self, $file) = @_;
  $self->initializeCommand($file);
  $self->prepareForFile;
}

### administration for optionally refocussing previous window

sub doRefocus { my ($self) = @_;
  return if !$self->{refocusNeeded};
  my $win = $self->searchRefocusWin;
  $win->setforegroundwindow if $win;
}

sub storeRefocus { my ($self, $file) = @_;
  return if !$self->{refocusChoice};
  
  # Delay the search until ->doRefocus
  # In no case is it necessary to store the refocus win
  # ahead of time, so delay this until after play commands
  # are sent
  # just flag the necessity of refocussing
  $self->{refocusNeeded} = 1;
  return;
  $self->searchRefocusWin;
}

sub searchRefocusWin { my ($self) = @_;
  my $refocusChoice = $self->{refocusChoice} ;
  return if !$refocusChoice;
  
  my $win;
  if ($refocusChoice eq 'term') {
    $win = DH::GuiWin->currentTerminalWin;
  }
  else {
    $win = DH::GuiWin->findfirstviewablelike($refocusChoice);
  }
  return if !$win;
  return $self->{refocusWin} = $win;
}

sub currentTerminalWin {
  return DH::GuiWin->currentTerminalWin;
}

### utilities

### demo & testing
sub dump { my ($self, $var) = @_;
  eval 'use Data::Dumper';
  eval '$Data::Dumper::Indent=1';
  say Data::Dumper::Dumper($var);
}

sub testreqs {
  my @mods = qw();
  foreach (@mods) {eval "use $_"};
}

sub test1info {'create object and show'}
sub test1 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  $class->testreqs;
  my $self = $class->new;
  $self->dump({%$self});
}

sub test2info {'check communication'}
sub test2 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  $class->testreqs;

  my $self = $class->new;
  say "Response:\n", ($self->acceptsCommand//'<undef>');
}

sub test3info {'set up process and communication - old version'}
sub test3 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  $class->testreqs;

  my $self = $class->new;
  
  my $ok = $self->acceptsCommand;
  if ($ok) {
    say "Communication was okay already";
  }
  else {
    my $ok = $self->setupProcessAndCommunication;
    say
      $ok
        ? 'success reported'
        : 'failure reported';
  }

}

sub test4info {'show media currently opened'}
sub test4 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  $class->testreqs;

  my $self = $class->new;
  my @labels = $self->openItemsLongLabels;
  printf "Number of open media: %d\n", 0+@labels;
  for my $l (@labels) {
    printf "  %s\n", $l;
  }
}

sub test5info {'show currently active media item'}
sub test5 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  $class->testreqs;

  my $self = $class->new;
  $self->ensureCommunication;
  $self->update;
  my $label = $self->currentlyActiveShortLabel;
  say ($label//'<undef>');
}

sub test6info {'activate file - only stub implemented'}
sub test6 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  $class->testreqs;
d::dd;
  my $self = $class->new;
  $self->ensureCommunication;

  my $file = $self->demoFile;

  $self->activateFile($file);
}

sub test7info {'activate connected file'}
sub test7 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  $class->testreqs;
d::dd;
  my $self = $class->new;
  $self->ensureCommunication;

  my $file = $self->demoFile;

  $self->activateConnectedFile($file);
}

sub test8info {'ensure paused'}
sub test8 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  $class->testreqs;
d::dd;
  my $self = $class->new;
  $self->ensureCommunication;

  $self->ensurePaused;
}

sub test9info {'play range for file'}
sub test9 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  $class->testreqs;

  my $self = $class->new;

  my $file = $self->demoFile;
  my $t0 = 506;
  my $t1 = $t0 + 5;
  d::dd;
  $self->playRangeForFile($file,$t0, $t1);
}

sub test10info {'check stage'}
sub test10 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  $class->testreqs;

  my $self = $class->new;

  $self->connectToProcess;
  my $file = Flex::path('f:/phon/detlev/vokale_tief.wav');
  $self->initializeCommand($file);
  d::dd;
  my $stage = $self->stageFromLabelRequest;
  my $kal   = $self->knownActiveLabel;
  
  printf "stage: %s\n", $stage//'<undef>';
  printf "label: %s\n", $kal//'<undef>';
  
}

sub test11info {'prepare file'}
sub test11 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  $class->testreqs;

  my $self = $class->new;

  my $file = 
       $argv->[0]
    || Flex::path('f:/phon/detlev/vokale_tief.wav');

  $self->initializeCommand($file);
  d::dd;
  my $stage = $self->prepareForFile;

  printf "stage: %s\n", $stage//'<undef>';
  
}
sub test12info {'start process'}
sub test12 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  $class->testreqs;

  my $self = $class->new;
  my $file = $argv->[0] || $self->demoFile;
  $file = Flex::canon_path_fast($file);
  
  print "Try to start process with file: '$file'\n";
  my $res = $self->startProcess({with_file=>$file});
  say $res ? 'process started' : 'process not started';
}

sub test13info {'locate current stage'}
sub test13 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  $class->testreqs;
d::dd;
  my $self = $class->new;
  $self->connectToProcess;
  
  my $file = $argv->[0] || $self->demoFile;
  $file = Flex::canon_path_fast($file);

  $self->initializeCommand($file);
  my $res = $self->stageFromLabelRequest;
  
  
  printf "Current stage is: %s\n", $res;
}

use DH::Testkit;
sub main {
  print __PACKAGE__ . " meldet sich!\n";
  return __PACKAGE__->test1 if @ARGV==0;
  DH::Testkit::selectTest(__PACKAGE__);
}

if ($0 eq __FILE__) {main();}

1;
