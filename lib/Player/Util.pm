package Player::Util;
use strict 'vars';
use feature ':5.10'; # loads all features available in perl 5.10

use Flex;

use DH::ForUtil::Quickopen;
use DH::ForUtil::CreateDir;
use DH::ForUtil::Time;
use DH::ForUtil::CompId;

sub find_under_lib {
  my $dir;
  for (@INC) {
    next if ! -e "$_/Player";
    $dir = "$_/Player";
    return $dir;
  }
}

sub player_dir      { find_under_lib() }
sub proj_dir        {
  my @pl_parts = split '/', player_dir();
  my @pr_parts = @pl_parts[0..$#pl_parts-2];
  return join('/', @pr_parts);
}

sub tmpdir          { Flex::tmpdir(@_) }
sub onWin           { goto &Flex::onWin }

sub flexname        { Flex::path(@_)  }
sub load_on_demand  { eval "use $_[0];";}
sub createDir       { goto &DH::ForUtil::CreateDir::createDir }
sub createDirForFile{ goto &DH::ForUtil::CreateDir::createDirForFile }

sub quickopen       { goto &DH::ForUtil::Quickopen::quickopen }
sub showquickopen   { goto &DH::ForUtil::Quickopen::showquickopen }
#sub position_hash   { DH::Util::position_hash(@_) }
#sub multiplicity_hash   { DH::Util::multiplicity_hash(@_) }
#sub cprintf(@)      { DH::Util::cprintf(@_) }
#sub cprint(@)       { DH::Util::cprint(@_ ) }
#sub csay(@)         { DH::Util::csay(@_ ) }
#sub console         { DH::Util::console(@_)   }

sub xx (@) {
  load_on_demand('DH::Dump');
  my $dumper = DH::Dump->new;
  my @s = map { $dumper->s($_) } @_;
  print ( join(' ', @s) );
}

#sub start_link      { DH::File::start_link(@_)      }
#sub write_file_txt  { DH::File::write_file_txt(@_)  }
#sub get_file_txt    { DH::File::get_file_txt(@_)    }

#sub oneline_dumper  { DH::Dump->new }
#sub disp_table                { Disp::table(@_)                 }

sub default_vlc_host {
  #return 'd2';
  return 'localhost';
  lc( DH::ForUtil::CompId::compid() );
}

sub remote_path_sub { my ($host) = @_;
  return $host =~ m{^[cd][27]$} ? \&Flex::win_path_fast : undef;
}

sub vlc_exe       { 
  if ( onWin() ) {
    load_on_demand('DH::FileLocs');
    return DH::FileLocs::vlc(); 
  }
  return 'vlc';
}

sub praat_exe       { 
  if ( onWin() ) {
    return 'E:\p\audio\praat\praat.exe';
  }
  return 'praat';
}

sub praat_script_dir  { Flex::path('E:/praatscr') }
sub audacity_exe      { 'audacity-with-scripting' }
sub mplayer_exe       { 'mplayer' }

sub sleep { goto &DH::ForUtil::Time::sleep }


sub readkey {
  state $loaded = load_on_demand('Term::ReadKey');
  return if !$INC{'Term/ReadKey.pm'};

  Term::ReadKey::ReadMode(4); # Turn off control keys
  my $key = Term::ReadKey::ReadKey(-1);
  Term::ReadKey::ReadMode(0); # Reset tty mode before exiting
  return $key;

  my $c = DH::ReadKey::readkey({dontblock=>1});
  if ($c) {
    # escape control chars
    $c =~ 
      s{([\x00-\x19])}
      {sprintf(" Ctrl-%s",chr(ord($1)+ord('@')))}ge;
  }
  return $c;
}

### simple stand-alone utilities

sub slurp_to_ref { my ($file) = @_;
  return if !-e $file;
  
  open my $fh, '<', $file or return;
  
  my $s;
  {local $/=undef; $s=<$fh>}
  
  close $fh;
  return \$s;
}

=head3 multiplicity_hash

For example:

  multiplicity_hash( [qw(a b c a)] ) =
  {a=>2, b=>1, c=>1}

=cut

sub multiplicity_hash { my ($list) = @_; # like [qw(a a b)] -> {a=>2, b=>1}
  my %hash;
  $list ||= [];
  foreach (@$list) {
    $hash{$_}++;
  }
  return \%hash;
}

sub trimWhite {           my $s=$_[0];
  #  $s =~ /^\s*(.*?)\s*$/;
  #  $1;
  $s =~ s/^\s*//g;
  $s =~ s/\s*$//g;
  return $s;
}

### colors

sub colormarkers { my ($arg) = @_;
  eval 'use DH::ForUtil::Terminal';
  goto &DH::ForUtil::Terminal::colormarkers;
}


### time conversions

=head3 subs ss2mmssmmm($t), mmssmmm2ss($q)

Converts between time representation in seconds or human-friendly format

Example:

  in seconds:      123.456
  human-friendly:  02:03.456 ( 2 min, 3 sec, 456 msec)

=cut

sub ss2mmssmm_pm { my ($t) = @_;
  return ( ($t<0) ? '-' : ' ') . ss2mmssmmm(abs($t));
}

sub ss2mmssmmm { my (@vals) = @_;
  my $opt;
  if (ref $vals[-1] eq 'HASH') {
    $opt = $vals[-1];
    @vals = @vals[0..$#vals-1];
  }
  my $ndigit = $opt->{ndigit}//3;
  my $w = $opt->{width};
  
  my $msfmt = sprintf "%%0.%df", $ndigit;
  foreach my $val (@vals) {
    if (!defined $val) {next;}
    my $t = $val;
    $t =~ s/\,/\./g;

    my $sgn='';
    if ($t =~ /^([\-\+])(.*)$/) {
      ($sgn,$t) = ($1, $2);
    }

    my $s = int($t);
    my $ms = $t-$s;
    my $ss = $s % 60;
    my $mm = int($s/60);
    
    $ms = sprintf $msfmt, $ms;

    $val = sprintf ("%s%02d:%02d",$sgn,$mm,$ss);
    if ($ndigit) { $val .= '.' .substr($ms,2) };
    if ($opt->{trim_leading}) {
      if ($val =~ /^[0:]*(\d[\d:]*\.\d*)$/) { $val = $1;}
    }
    if ($w) {
      if (length($val)<$w) { $val = (' 'x($w-length($val))) . $val }
    }
  }
  return wantarray ? @vals : $vals[0];
}

sub ss2mmss { my (@vals) = @_;
  my $s = ss2mmssmmm(@vals);
  $s =~ s{\.\d*$}{};
  return $s;
}

sub mmssmmm2ss { my @vals = @_;
  foreach my $q (@vals) {
    if (!defined $q) {next;}
  # trim white, get sign
    my $sgn;
    if ($q =~ /^\s*([\+\-]?)(.*?)\s*$/) { ($sgn,$q) = ($1, $2); }
    my ($h, $m, $s);
    my @els = split /\:/ , $q;
    ($h, $m, $s) = ($els[-3],$els[-2],$els[-1]);
    $q = $h*3600 + $m*60 + $s;
    if ($sgn eq '-') {$q=-1*$q;}
  }
  return wantarray ? @vals : $vals[0];
}

# mmssmm2ss can do hhmmssmm2ss as well
sub hhmmssmmm2ss { mmssmmm2ss(@_) }

sub ss2hhmmssmmm { my ($q, $par) = @_;
  # number of decimals after '.'
  my $ndec = $par->{ndec}//3;
  
  my $h = int($q/3600);
  $q -= $h*3600;
  
  my $m = int($q/60);
  $q -= $m*60;

  my @out;
  push @out, sprintf ("%d", $h) if $h;
  
  if (@out) {
    push @out, sprintf ("%02d", $m);
  }
  elsif ($m) {
    push @out, sprintf ("%d", $m);
  }

  my $fmt =
    @out
      ? sprintf '%%0%d.%df', $ndec+3, $ndec
      : sprintf '%%.%df'   ,          $ndec;

  push @out, sprintf($fmt, $q);
  
  return join(':',@out);
}

sub secs2tableTimes { my ($t0, $t1) = @_;
  my $dt = $t1-$t0;
  my $t0s = ss2hhmmssmmm($t0, {ndec=>4});
  my $dts = ss2hhmmssmmm($dt, {ndec=>4});
  return ($t0s, $dts);
}

### input parameter handling

=for me

I decided to move arguments around in the form of key value pairs, like:

  key1 = value1 ; key1 = value2 ; ...

with all whitespace optional.

The input can be a single string like the above or an arrayref containing several of these above strings, each holding any number of key value pairs. The last key/value pair for each key will be used.

=cut

sub paramHashFromStrings { my ($input) = @_;
  my $strings = ref $input eq 'ARRAY' ? $input : [$input];
  
  my %resHash;
  
  for my $s (@$strings) {
    my @pairs = split /;/, $s;

    foreach my $p (@pairs) {
      my ($key, $val) = 
        $p =~ m{^\s* (\w+?) \s* = \s* (.*?) \s* $}x;
      
      $resHash{$key} = $val;
    }
  }

  return \%resHash;
}

sub resolveArguments { my ($hash) = @_;
  
  # move single-letter entries to full-length forms
  my @keys = qw(file start_s length_s refocus widen player);
  for (@keys) {
    my $first = substr($_,0,1);
    next if !defined $hash->{$first};
    $hash->{$_} = $hash->{$first};
    delete $hash->{$first};
  }
  
  # $hash->{length_s} can be replaced by $hash->{d},
  # auto-surrounded by [...]
  if (!defined $hash->{length_s} && defined $hash->{d}) {
    $hash->{length_s} = "[$hash->{d}]";
  }
  
  return $hash;
}

sub fillInDefaultParams { my ($hash) = @_;
  $hash->{start_s}  //= 0;
  $hash->{length_s} //= '[1]';
  return $hash;
}

sub adaptFilesToOS { my ($hash) = @_;
  # make sure file arguments suitable for OS
  for (qw(file tablefile audiofile videofile)) {
    next if !$hash->{$_};
    $hash->{$_} = Flex::canon_path_fast( $hash->{$_} );
  }
  return $hash;
}

sub paramStringFromHash { my ($hash) = @_;
  my %seen;
  my @order;
  
  # transfer an entry 'key=value' to @pairs for each
  # entry in $hash
  
  # First determine the order of keys
  
  # First do standard keys in standard order
  my @standardKeys = qw(
    stcid
    start_s
    length_s
    refocus
    tablefile
    player
    audiofile
    videofile
    file
  );
  
  foreach (@standardKeys) {
    next if !defined $hash->{$_};
    push @order, $_;
    $seen{$_}++;
  }

  # Now collect remaining keys
  my @rest = grep { !$seen{$_}++ } keys %$hash;
  push @order, sort @rest;
  
  # Create pairs in this order
  my @pairs = map {"$_=$hash->{$_}" } @order;

  return join('; ', @pairs);
}

sub resolvedParamHash { my ($s) = @_;
  my $hash = paramHashFromStrings($s);
  return resolveArguments($hash);
}

sub resolvedParamHashWithDefaults { my ($s) = @_;
  my $hash = resolvedParamHash($s);
  return fillInDefaultParams($hash);
}

sub makeAbsolute { my ($file) = @_;

  $file =~ s{\\\/}{}g;
  $file =~ m{ (^|/) [^/]+ $}x;
  my $dir = $`;
  
  return $dir if defined $dir && length($dir)>0;

  # $0 wasn't fully-qualified: get cwd
  eval 'use Cwd';
  return Cwd::getcwd();
}

sub modifyBaseHash { my ($basehash, $newhash) = @_;
  delete $basehash->{refocus} if exists $basehash->{refocus};
  
  # replace all key-value pairs specified for this run
  for (keys %$newhash) {
    $basehash->{$_} = $newhash->{$_};
  }

  return $basehash;
}

### interface to commands triggered from libreoffice

sub processPlayCommand { my ($hash) = @_;
  fillInDefaultParams($hash);
  adaptFilesToOS($hash);
  eval 'use ExWord::Audio::PlaySelFromTable';
  ExWord::Audio::PlaySelFromTable->playFromHash($hash);
}

### demo && testing

sub test1info{'parse input strings to hash and back'};
sub test1 {
  my $input = [
    'a=b; c=d' ,
    'e=f ; g = h' ,
    'f=abc.wav' ,
  ];
  
  my $res = resolvedParamHash($input);
  eval 'use DH::Util';
  my $dumper = DH::Util::oneline_dumper();
  say $dumper->s($res);
  
  my $s = paramStringFromHash($res);
  say "back to string: '$s'";
}

sub test2info{'show player and proj dir'};
sub test2 {
  say "player dir=" . player_dir();
  say "proj   dir=" . proj_dir();
}

use DH::Testkit;
sub main {
  print __PACKAGE__ . " meldet sich!\n";
  DH::Testkit::selectTest(__PACKAGE__);
}

if ($0 eq __FILE__) {main();}

1;
