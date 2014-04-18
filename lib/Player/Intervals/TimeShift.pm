package Player::TimeShift;
use strict;
use warnings;
use feature ':5.10'; # loads all features available in perl 5.10
use utf8; # → ju:z ju: tʰi: ɛf eɪt!

use Flex;
use DH::Util;
use DH::File;

use DH::Db;
use Player::Util;

use File::Basename;

=for me

Module for computing shifted times for my recording tables

=cut


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

### attributes
=for me

has 'infile'  ,
has 'outfile' ,
has 'fields'  ,
has 'head'    ,
has 'records' ,

=cut


### accessors

### work

sub loadTable { my ($self, $file) = @_;
  if ($file) {
    $self->{infile} = $file;
  }
  else {
    $file = $self->{infile};
  }
  
  my $par = {
    returnids => {} ,
  };
  my $list = DH::Db::loadTableArray(
    $file ,
    $par  ,
  );

  $self->{head}    = $par->{returnids}{cols};
  $self->{records} = $list;
}

sub writeTable { my ($self) = @_;
  my $out = $self->{outfile};
  if (!$out) {
    my $dir = Flex::tmpdir();
    my $in  = $self->{infile};
    my ($name, $path, $suf) = fileparse( $in, '\..*' );
    $out = $self->{outfile} = "$dir/$name.html";
  }

  my $head = $self->{head};
  my $par = {
    head        => $head ,
    noquickopen => 1 ,
  };
  my $list = $self->{records};
  DH::Db::write_table_array($list, $out, $par);
  DH::Util::quickopen($out, {bat=>'qq'});
}

sub timeShift { my ($self, $dt) = @_;
  my $list    = $self->{records}//[];
  my $fields  = $self->{fields}//=[qw(start_s length_s)];
  
  if ($dt) {
    $self->{dt} = $dt;
  }
  else {
    $dt = $self->{dt};
  }

  if (!$dt) {
    die "No time dt provided";
  }
  
  foreach my $r (@$list) {
    foreach my $f (@$fields) {
      my $t = DH::Util::trimWhite($r->{$f});
      
      # skip empty
      next if $t!~/\S/;
      
      # skip values enclosed in [...] - they're unaffected
      next if $t =~ m{^ \[ .*? \] $}x;

      # shift it by dt
      my $sec = Player::Util::mmssmmm2ss($t);
      my $t1  = Player::Util::ss2mmssmmm($sec+$dt);
      
      # remove leading zero if possible
      if ($t1=~m{^0\d:}) { $t1 =~ s{^0}{}; }
      
      $r->{$f} = $t1;
    }
  }
}

### utilities

### demo & testing
sub testreqs {
  my @mods = qw(Data::Dumper);
  foreach (@mods) {eval "use $_"};
  $Data::Dumper::Indent=1;
}

sub test1info {'shift mlv_001.html by 20 sec'}
sub test1 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  $class->testreqs;
  my $infile = 'F:/PhonPhen/transcr/mlv/mlv_001.html';
  $infile = 'F:/PhonPhen/transcr/eco/eco_001.html';
  $infile = Flex::path($infile);
d::dd;  
  my $self = $class->new;
  $self->loadTable($infile);
  $self->timeShift(-1.176);
  $self->writeTable;
  DH::Util::showquickopen();
}

use DH::Testkit;
sub main {
  print __PACKAGE__ . " meldet sich!\n";
  return __PACKAGE__->test1 if @ARGV==0;
  DH::Testkit::selectTest(__PACKAGE__);
}

if ($0 eq __FILE__) {main();}

1;
