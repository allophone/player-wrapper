package Player::Config;
use strict;
use warnings;
use feature ':5.10'; # loads all features available in perl 5.10
use utf8; # → ju:z ju: tʰi: ɛf eɪt!

use Config::Tiny;

our $Config;

sub onWin   { state $onwin = $^O =~ /^MSWin/i }
sub home    { 
  state $home;
  return $home if $home;
  
  if ( onWin() ) {
    $home = "$ENV{HOMEDRIVE}$ENV{HOMEPATH}";
    $home =~ s{\\}{/}g;
  }
  else {
    $home = $ENV{HOME};
  }
  return $home;
}

sub iniFile { state $file = home() . '/.player-wrapper.ini' }

sub config {
  return $Config if $Config;
  my $file = iniFile();
  $Config = Config::Tiny->read($file,'utf8');
}

### utilities

### demo & testing
sub testreqs {
  my @mods = qw(Data::Dumper);
  foreach (@mods) {eval "use $_"};
  eval "\$Data::Dumper::Indent=1;";
}

sub test1info {'show basic settings to find config file'}
sub test1 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  #$class->testreqs;
  for (qw(onWin home iniFile)) {
    printf "%-12s: '%s'\n", $_, ($class->$_//'<undef>');
  }
}

sub test2info {'show config'}
sub test2 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  $class->testreqs;
  
  print Data::Dumper::Dumper( config() );
}

use DH::Testkit;
sub main {
  print __PACKAGE__ . " meldet sich!\n";
  return __PACKAGE__->test1 if @ARGV==0;
  DH::Testkit::selectTest(__PACKAGE__);
}

if ($0 eq __FILE__) {main();}

1;
