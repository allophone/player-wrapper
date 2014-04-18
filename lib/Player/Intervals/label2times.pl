use strict;
use warnings;
use feature ':5.10'; # loads all features available in perl 5.10
use utf8; # → ju:z ju: tʰi: ɛf eɪt!

use Flex;
use DH::Util;
use DH::File;

use Player::Audacity;
use Player::TableForLabels;
use Player::Util;

my $Glob;

sub showhelp { 
  eval 'require DH::Util';
  print DH::Util::console( <<HELP );

Retrieves ranges either from Audacity for file /x/l

  -l use file /x/l
     default: query Audacity
  
  -w open table in wordprocessor
  -o open table in default (=browser)
HELP

  my $src = Flex::canonAbsPath($0);
  DH::Util::quickopen( $src, {bat=>'s', show=>1} );
  exit();
}

sub init {
  if ($Glob->{initdone}) {return;}
  my $opts = $Glob->{opts} = {};
  # options as above. Values in %opt
  DH::Util::getopts('wolh', $opts);  
  showhelp() if $opts->{h};
  $Glob->{initdone}=1;
}

  init();

  my $rows;

  if ( $Glob->{opts}{l} ) {
    $rows = ranges_from_file();
  }
  else {
    $rows = ranges_from_audacity();
  }
  
  print "\n";
  my $out = Player::TableForLabels->writeTable($rows);
  DH::Util::quickopen($out);  
  DH::Util::showquickopen();
  
  if ($Glob->{opts}{w}) {
    DH::File::start_link($out, {in=>'word'});
  }
  if ($Glob->{opts}{o}) {
    DH::File::start_link($out);
  }

sub ranges_from_file {
=for me

/x/l looks like:

572.787379	1347.735010	
1794.172232	2063.719234	
2687.046676	3782.081371	
4405.408813	5146.663069	

=cut

  my $file = '/x/l';
  my @lines = DH::File::get_file_txt($file);
  my @rows;
  foreach my $l (@lines) {
    push @rows, rowFromLine($l);
  }
  return \@rows;
}

sub ranges_from_audacity {
=for me

$aud->aud_getLabelsFromSavedProject returns ranges in an array like:

0  ARRAY(0x3489070)
   0  '     572.7873792     1347.7350099'
   1  '    1794.1722319     2063.7192338'
   2  '    2687.0466759     3782.0813714'
   3  '    4405.4088134     5146.6630688'

=cut

  my $aud = Player::Audacity->new;
  return if !$aud->ensureCommunication;
  
  my $label = $aud->currentlyActiveShortLabel;
  return if !$label;
  
  $aud->aud_saveProject;
  my $ranges = $aud->aud_getLabelsFromSavedProject;
  
  my @rows;
  for my $range (@$ranges) {
    push @rows, rowFromLine($range);
  }
  return \@rows;
}

sub rowFromLine { my ($s) = @_;
  $s = Player::Util::trimWhite($s);
  my ($t0, $t1) = split /\s+/, $s;
  my $dt = $t1-$t0;
  my $t0s = Player::Util::ss2hhmmssmmm($t0, {ndec=>4});
  my $dts = Player::Util::ss2hhmmssmmm($dt, {ndec=>4});
  return {start_s=>$t0s, length_s=>"[$dts]"};
}
