use strict;
use warnings;
use feature ':5.10'; # loads all features available in perl 5.10
use utf8; # → ju:z ju: tʰi: ɛf eɪt!

use Flex;
use DH::Util;
use DH::File;

use Player::Audacity;

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
  my $opts = $Glob->{opts} = {};
  # options as above. Values in %opt
  DH::Util::getopts('h', $opts);  
  showhelp() if $opts->{h};
  $Glob->{initdone}=1;
}

  init();
  my $s = '';
  
  print join("\n",
    '-'x60 ,
    'Start retrieving selection from audacity' ,
    '-'x60 ,
  );    
  
  my $aud   = Player::Audacity->new;
  my $ok    = $aud->ensureCommunication;
  my $label = $ok && $aud->currentlyActiveShortLabel;
  
  if (!$label) {
    print "No active track found.\n";
  }
  else {
    print "Retrieving selection from: '$label'\n";

    my ($t0, $dt) = $aud->aud_getSelectionFormatted;
    my @s;
    push @s, "2=$t0" if defined $t0;
    push @s, "3=$dt" if defined $dt;
  
    $s = join("\t",@s);
  }
  
  my $file = Flex::path("d:/tmp/audacity_sel.txt");
  DH::File::write_file_txt($file, $s);
  
  $aud->doRefocus;

  printf "Selection for label='%s': '%s'\n", ($label//'<none>'), $s;
  DH::Util::quickopen($file);
  DH::Util::showquickopen();



  
