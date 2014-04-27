package Player::State::State;
use strict;
use warnings;
use feature ':5.10'; # loads all features available in perl 5.10
use utf8; # → ju:z ju: tʰi: ɛf eɪt!

use Player::Util;
#use File::Basename;

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
  return bless $par, $class;
}

### accessors

### work

sub commandLogFile  { Player::Util::player_dir() . '/State/lastcom' }

sub createCommandFile { my ($self, $strOrHash) = @_;

  my $s =
    !ref $strOrHash 
      ? $strOrHash 
      : Player::Util::paramStringFromHash($strOrHash);

  #This wastes a lot of time!
  #Just use regular dir
  #my $dir  = Flex::canonDirOf($0);

  my $bat = $self->commandLogFile();

  # read, chomp and reduce to max. 50 lines
  my $read = $self->slurp($bat);
  my @lines = split /\r?\n/, $read;
  @lines = @lines[0..49] if @lines>49;

  # comment out all but last line, so file can be run
  @lines = map { s/^#\s*//; "# $_" } @lines;
  
  my @comps = split /\s*;\s*/ , $s;
  @comps = map { sprintf "%-12s", $_ } @comps;
  $s = join(' ; ',@comps);
  
  unshift @lines , "perl play.pl '$s'";
  
  $self->write_file_txt($bat, \@lines);

}

sub previousCommandHash { my ($self) = @_;
  # retrieve first non-blank, non-comment line
  my $bat = $self->commandLogFile();
  open my $fh, '<', $bat or return;
 
  my $s;
  while (defined ($s=<$fh>) ) {
    next if $s!~/\S/;
    next if $s=~/^\s*\#/;
    last;
  }
  close $fh;
  
  return if !$s;
  
  $s =~ s{^\s*perl\s+play\.pl\s+}{};
  if ($s =~ m{\s*'\s*(.*?)\s*'\s*$}x) {
    $s = $1;
  }
  
  return Player::Util::resolvedParamHash($s);
}

sub write_file_txt { my ($self, $file, $lines) = @_;
  open my $fh, '>', $file or die $!;
  foreach (@$lines) {
    print $fh ("$_\n");
  }
  close $fh;
}

sub slurp { my ($self, $file) = @_;
  open my $fh, '<', $file or die $!;
  
  my $s;
  {local $/=undef; $s=<$fh>}
  
  close $fh;
  return $s;
}

### utilities

### demo & testing
sub testreqs {
  my @mods = qw(Data::Dumper);
  foreach (@mods) {eval "use $_"};
  eval "\$Data::Dumper::Indent=1;";
}

sub test1info {'show hash of previous play command'}
sub test1 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  $class->testreqs;
  
  my $self = $class->new;
  my $hash = $self->previousCommandHash;
  print Data::Dumper::Dumper( $hash );
}

sub test2info {'show player dir'}
sub test2 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  $class->testreqs;

  my $dir = $class->findUnderLib;
  printf "dir=%s\n", $dir//'<undef>';
}

use DH::Testkit;
sub main {
  print __PACKAGE__ . " meldet sich!\n";
  return __PACKAGE__->test1 if @ARGV==0;
  DH::Testkit::selectTest(__PACKAGE__);
}

if ($0 eq __FILE__) {main();}

1;
