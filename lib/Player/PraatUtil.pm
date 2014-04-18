package Player::PraatUtil;
use strict;
use warnings;
use feature ':5.10'; # loads all features available in perl 5.10
use utf8; # → ju:z ju: tʰi: ɛf eɪt!

use Player::Util;

=for me

This is an attribute-less parent module for Player::Praat holding a few modules that I want to be able to load separately from the whole Praat module.

Inside the Praat module they should function just as if they were part of the Praat module.

=cut

sub new { return bless {} }

# PraatUtil always returns script dir from Player::Util
# actual Praat object override this with their accessor
sub pra_scriptDir { Player::Util::praat_script_dir() }

sub pra_scriptForCommand { my ($self, $core, $opt) = @_;
  my $dir = $self->pra_scriptDir;
  my $for = $opt->{for} || (Flex::onWin() ? 'win' : 'lin');
  return "$dir/${core}_${for}.prs";
}

sub pra_writePraatScript { my ($self, $namecore, $body, $opt) = @_;
  my $file  = $self->pra_scriptForCommand($namecore, $opt);

  open my $fh, '>', $file or return;
  print $fh $body;
  close $fh;
  
  return $file;
}

sub pra_writeLoadScript { my ($self, $soundfile, $opt) = @_;
  my $dir = $self->pra_scriptDir;
  my $for = $opt->{for} || (Flex::onWin() ? 'win' : 'lin');
  
  if ($for eq 'win') {
    $soundfile = Flex::win_path_fast($soundfile);
  }
  elsif ($for eq 'lin') {
    $soundfile = Flex::canon_path_fast($soundfile);
  }

  my $body = <<PRS;
Open long sound file... $soundfile
View
PRS

  $self->pra_writePraatScript('long', $body, $opt);
}

sub pra_writePlayScript { my ($self, $t0, $t1, $opt) = @_;
  my $for = $opt->{for} || (Flex::onWin() ? 'win' : 'lin');

  my $t0s = sprintf "%12.4f", $t0;
  my $t1s = sprintf "%12.4f", $t1;
  
  my $body = <<PRS;
Zoom... $t0s $t1s
Play... $t0s $t1s
PRS

  $self->pra_writePraatScript('ctrl-f12', $body, $opt);
}

sub pra_writeLoadAndPlayScripts { my ($self, $file, $t0, $t1, $opt) = @_;
  $self->pra_writeLoadScript($file, $opt);
  $self->pra_writePlayScript($t0, $t1, $opt);
}

### demo & testing

sub demoFile {
  my $file;
  $file = 'f:/phonmedia/boc/boc_e01.wav';
  $file = Player::Util::flexname($file);
}

sub testreqs {
  my @mods = qw(Data::Dumper);
  foreach (@mods) {eval "use $_"};
  eval "\$Data::Dumper::Indent=1;";
}

sub test301info {'write open longsound scripts'}
sub test301 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  $class->testreqs;
  
  my $self = $class->new;
  my $file = $class->demoFile;

  eval 'use DH::Util';
  for my $for ('win','lin','') {
    my $script = $self->pra_writeLoadScript($file, {for=>$for});
    DH::Util::quickopen($script);
  }
  DH::Util::showquickopen();
}

sub test302info {'write open play scripts'}
sub test302 { my ($pkg, $argv) = @_;
  my $class = ref $pkg || $pkg || __PACKAGE__;
  $class->testreqs;
  
  my $self = $class->new;
  my $file = $class->demoFile;

  eval 'use DH::Util';
  for my $for ('win','lin','') {
    my $script = $self->pra_writePlayScript(123.456, 7.89, {for=>$for});
    DH::Util::quickopen($script);
  }
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
