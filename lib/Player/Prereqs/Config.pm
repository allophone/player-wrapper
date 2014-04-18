package Player::Prereqs::Config;
use strict;
use warnings;
use feature ':5.10'; # loads all features available in perl 5.10
use utf8; # → ju:z ju: tʰi: ɛf eɪt!

### define optional dependencies
sub optional_deps_as_m2a_pairs { [
  'Player::VLC' => [qw(DH::ReadKey)] ,
] }

### defs for mods (what defs apply to a module?)
sub ignored_mods {
  [
    qr/^Moo      (?: $|::) /x ,
#    qr/^Mo[ou]se (?: $|::) /x ,
#    qr/^Marpa    (?: $|::) /x ,
    
#    qr/^Encode   (?: $|::) /x ,
#    qr/^Win32    (?: $|::) /x ,
  ]
}

### defs for bundles (what defs apply to a bundle?)
sub ignored_bundles {
  [
    qw(
      dhutils
    )
  ]
}

sub unrecursed_bundles {
  [
    qw(
      dhutils
      ppi
      graph-easy
      perl-prereq
      graphviz2
    ) ,
  ]
}

### bundle listing (to what bundle does a mod belong?)
sub bundles_as_b2a_pairs { my ($struct) = @_;
  [

    ppi           => [ qr/^PPI                 (?: $|::) /x ] ,
    'graph-easy'  => [ qr/^Graph::Easy         (?: $|::) /x ] ,
    'perl-prereq' => [ qr/^Perl::PrereqScanner (?: $|::) /x ] ,
    graphviz2     => [ qr/^GraphViz2           (?: $|::) /x ] ,

  ];
}


1;
