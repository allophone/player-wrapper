package Player::TableForLabels;
use strict;
use warnings;
use feature ':5.10'; # loads all features available in perl 5.10
use utf8; # → ju:z ju: tʰi: ɛf eɪt!

use Flex;
use DH::Util;
use DH::File;
use DH::Db;
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

### work

sub writeTable { my ($class, $rows) = @_;
  my $out = Flex::tmpdir() . '/labels.html';
  my $head = [qw(stcid start_s length_s text extra)];
  DH::Db::write_table_array(
    $rows ,
    $out   ,
    {
      head=>$head, 
      verbose=>1 ,
      rightjust => [qw(start_s length_s)] ,
      noquickopen => 1 ,
    } ,
  );
  return $out;
}

### accessors

### utilities

### demo & testing
sub testreqs {
  my @mods = qw(Data::Dumper);
  foreach (@mods) {eval "use $_"};
  $Data::Dumper::Indent=1;
}

sub test1info {'explanation of test1'}
sub test1 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  $class->testreqs;
  print "This is test 1.\n";  
}

use DH::Testkit;
sub main {
  print __PACKAGE__ . " meldet sich!\n";
  return __PACKAGE__->test1 if @ARGV==0;
  DH::Testkit::selectTest(__PACKAGE__);
}

if ($0 eq __FILE__) {main();}

1;
