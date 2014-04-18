use strict;
use warnings;
use feature ':5.10'; # loads all features available in perl 5.10
use utf8; # → ju:z ju: tʰi: ɛf eɪt!

use Flex;
use DH::GuiWin; # with playdirect also enable 'use DH::GuiWin'

  my $scriptdir = $0;
  $scriptdir =~ s{\/}{//}g;
  $scriptdir = Flex::make_absolute_fast($scriptdir);
  $scriptdir =~ s{/[^/]*$}{};
  my $pl;

  $pl = "$scriptdir/playdirect.pl";
  #$pl = "$scriptdir/playviahttp.pl";
  require $pl;

