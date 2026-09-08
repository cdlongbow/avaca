package Pod::Usage;

use strict;
use warnings;

sub import {
    my ($class) = @_;
    my $caller = caller;
    no strict 'refs';
    *{"${caller}::pod2usage"} = \&pod2usage;
}

sub pod2usage { return; }

1;
