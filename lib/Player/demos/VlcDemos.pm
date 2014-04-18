package Player::VlcDemos;
use strict;
use warnings;
use feature ':5.10'; # loads all features available in perl 5.10
use utf8; # → ju:z ju: tʰi: ɛf eɪt!

use parent 'Player::VLC';

### accessors

### utilities

### demo & testing
sub testreqs {
  my @mods = qw();
  foreach (@mods) {eval "use $_"};
}

sub test1info {'activate file and seek 1:00'}
sub test1 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  $class->testreqs;
  my $self = $class->new;
  $self->ensureCommunication;
  
  my $file = $self->demoFile;
  $self->activateFile($file);
  
  $self->seek(60);
}

sub test2info {'seek while playing'}
sub test2 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  $class->testreqs;
  my $self = $class->new;
  $self->ensureCommunication;
  
  my $file = $self->demoFile;
  $self->activateFile($file);
  
  $self->seek(60);
  
  $self->togglePause;
  
  sleep(3);
  
  $self->seek(80);
}

sub test3info {'togglePause'}
sub test3 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  $class->testreqs;
  my $self = $class->new(verbose=>1);
  $self->ensureCommunication;
  
  my $file = $self->demoFile;
  $self->activateFile($file);
  
  $self->togglePause;
}

use DH::Testkit;
sub main {
  print __PACKAGE__ . " meldet sich!\n";
  return __PACKAGE__->test1 if @ARGV==0;
  DH::Testkit::selectTest(__PACKAGE__);
}

if ($0 eq __FILE__) {main();}

1;
