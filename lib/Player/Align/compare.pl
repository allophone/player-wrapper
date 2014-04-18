use strict;
use warnings;
use feature ':5.10'; # loads all features available in perl 5.10
use utf8; # → ju:z ju: tʰi: ɛf eɪt!

use Flex;
use DH::Util;
use DH::File;
use DH::Db;

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

  init();
  my $mod = $ARGV[0] || 'VLC';

  my $outfile_tbl = write_subs_from_tbl($mod);
  my $outfile_pm  = write_subs_from_pm($mod);
  
  my $outdir  = outdir();
  my $outfile = "$outdir/${mod}_subs_compare.html";
  system("pu diff2html '$outfile_pm' '$outfile_tbl' > '$outfile'");

  DH::Util::quickopen($outfile_tbl);
  DH::Util::quickopen($outfile_pm);
  DH::Util::quickopen($outfile, {bat=>'c'});
  
  DH::Util::showquickopen();


sub player_dir { Flex::canonDirOf( $0 ) }
sub outdir     { Flex::tmpdir(); }

sub write_subs_from_tbl { my ($mod) = @_;
  my $dir = player_dir();
  my $table_file = "$dir/doc/command-comparison.html";

  # load the table
  my $par = { returnids=>1 };
  my $tbl = DH::Db::load_table_array($table_file, $par);
  my $head = $par->{returnids}{cols};
  
  # look up column of this $mod
  my $headhash = DH::Util::position_hash($head);
  my $col = $headhash->{$mod};
  
  my @subs_in_tbl;
  foreach (@$tbl) {
    my $val = $_->{$mod};
    next if $val !~ /\S/;
    $val = DH::Util::trimWhite($val);
    
    # single '#' in table used as comment
    next if $val =~ /^\s*\#[^\#]/;
    
    # trim and collapse whitespace
    trim_and_collapse_ws($val);
    
    push @subs_in_tbl, $val;
  }
  
  # write non-empty values of this column to file
  my $outdir  = outdir();
  my $outfile = "$outdir/${mod}_subs_tbl.txt";
  DH::File::write_file_txt($outfile, \@subs_in_tbl, {utf8=>1});
  return $outfile;
}

sub write_subs_from_pm { my ($mod) = @_;
  # write non-empty values of this column to file
  my $outdir  = outdir();
  my $outfile = "$outdir/${mod}_subs_pm.txt";
  my $pm      = "Player::$mod";
  system("subss -C $pm > '$outfile'");
  my @lines = DH::File::get_file_txt($outfile);

  @lines =
    map {
      my @res;
      if (
           !/\S/ 
        || /^Subs in File:/     # extra output from subss
      )
      {
        @res = ();
      }
      else {
        trim_and_collapse_ws($_);
        @res = ( DH::Util::trimWhite($_) );
      }
      @res;
    }
    @lines;

  DH::File::write_file_txt($outfile, \@lines, {utf8=>1});
  return $outfile;
}

sub trim_and_collapse_ws {
  $_[0] =~ s{^\s+}{};
  $_[0] =~ s{\s+$}{};
  $_[0] =~ s{\{\s+}{\{}g;
  $_[0] =~ s{\s+}{ }g;
}
