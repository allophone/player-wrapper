package Player::Gui;
use strict;
use warnings;
no warnings 'redefine';
use feature ':5.10'; # loads all features available in perl 5.10
use utf8; # → ju:z ju: tʰi: ɛf eɪt!

use Player::State::State;

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

sub homePageBody { my ($self) = @_;

  my @fields = qw(
    stcid     
    start_s   
    length_s  
    refocus   
    tablefile 
    player    
  );
  
  my $oldvals = Player::State::State->previousCommandHash();
  
  my $s = <<HTML;
<p>
I'm the home page
</p>

<form name="input" action="/play" method="get">
  <input type="submit">
<table>
HTML

  foreach my $f (@fields) {
    my $value = $oldvals->{$f}//'';
    $s .= <<HTML;
  <tr>
    <td>$f:</td>
    <td><input type="text" name="$f" value="$value"></td>
  </tr>
HTML
  }
  
  $s .= <<HTML;
  </table>
</form> 
HTML

}

### utilities

### demo & testing
sub testreqs {
  my @mods = qw(Data::Dumper);
  foreach (@mods) {eval "use $_"};
  eval "\$Data::Dumper::Indent=1;";
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
