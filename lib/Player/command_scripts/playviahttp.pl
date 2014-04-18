use strict;
use warnings;
use feature ':5.10'; # loads all features available in perl 5.10
use utf8; # → ju:z ju: tʰi: ɛf eɪt!

#use Flex;
#use DH::Util;
my $Glob;

sub showhelp { 
  eval 'require DH::Util';
  print DH::Util::console( <<HELP );
Dies ist meine Standardmethode, um dafür zu sorgen, dass mit der 
Option -h Hilfe angezeigt wird.
HELP

  my $src = Flex::canonAbsPath($0);
  DH::Util::quickopen( $src, {bat=>'s', show=>1} );
  exit();
}

sub init {
  if ($Glob->{initdone}) {return;}
  eval 'use DH::ForUtil::Getopts';
  
  my $opts = $Glob->{opts} = {};
  # options as above. Values in %opt
  DH::ForUtil::Getopts::getopts('h', $opts);  
  showhelp() if $opts->{h};
  $Glob->{initdone}=1;
}

  #init();

  #compute argument string
  
  my @args = @ARGV;

  my $s;
  if ( ($args[0]//'') eq '-r') {
    # with option -r, take previous command and modify it
    
    shift @args;

    eval 'use Player::Util';
    eval 'use Player::State::State';

    # current command as hash
    my $hash = Player::Util::paramHashFromStrings(\@args);

    # previous command hash
    my $basehash = Player::State::State->previousCommandHash();
    die "previous command not found" if !$basehash;
    
    # modify previous command with new command
    $hash = Player::Util::modifyBaseHash( $basehash, $hash );
    
    $s =    Player::Util::paramStringFromHash($hash);
  }

  else {
    # without -r take command string from command line
    for (@args) {
      s{^\s+}{};
      s{\s+$}{};
    }
    $s = join(';', @args);
  }
  
  print "s=\n$s\n";
  
  use URI::Escape;
  $s = uri_escape($s);

  # pass this command string to player via web interface
  my $url     = "http://localhost:8092/play/?com=$s";
  my $outfile = '~/.nohup/wget.out';
  my $log     = '~/.nohup/wget.log';
  my $dummy   = '~/.nohup/wgetdummy.txt';
  my $com = qq{nohup wget -O $outfile -o $log $url > $dummy \&};
  print "$com\n";
  system($com);

