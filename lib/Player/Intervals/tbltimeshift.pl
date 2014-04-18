use strict;
use warnings;
use feature ':5.10'; # loads all features available in perl 5.10
use utf8; # → ju:z ju: tʰi: ɛf eɪt!

use Flex;
use DH::Util;

use Player::TimeShift;

my $Glob;

sub showhelp { 
  eval 'require DH::Util';
  print DH::Util::console( <<HELP );
  perl tbltimeshift.pl <INFILE>
  
  -d : amount to add to all times

HELP

  my $src = Flex::canonAbsPath($0);
  DH::Util::quickopen( $src, {bat=>'s', show=>1} );
  exit();
}

sub init {
  if ($Glob->{initdone}) {return;}
  eval 'use DH::ForUtil::Getopts';
 
  my $o = $Glob->{opts} = {};
  
  # options as above. Values in %opt
  DH::ForUtil::Getopts::getopts('d:h', $o);  
  showhelp() if $o->{h};

  $Glob->{t_add} = $o->{d} if $o->{d};

  $Glob->{initdone}=1;
}

  init();
  
  my $infile = $ARGV[0];
  $infile = Flex::path($infile);
  
  showhelp() if !$infile;
  
  if (! -e $infile) {
    die "input file '$infile' not found\n";
  }
  
  my $delay = $Glob->{t_add};
  if (!$delay) {
    die "Specify a delay to apply like -d 1.234";
  }
  
  my $shifter = Player::TimeShift->new;

  $shifter->loadTable($infile);
  $shifter->timeShift($delay);
  $shifter->writeTable;
  DH::Util::showquickopen();

