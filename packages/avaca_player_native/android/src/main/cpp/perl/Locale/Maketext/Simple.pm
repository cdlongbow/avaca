package Locale::Maketext::Simple;

use strict;
use warnings;

# Git-for-Windows ships the Perl core used by the pinned quictls Configure
# script but omits this optional localization module.  OpenSSL only needs its
# gettext-compatible `loc` formatting helper while probing the build host, so
# keep a deterministic no-translation shim in the Android build overlay.
sub import {
    my ($class) = @_;
    my $caller = caller;
    no strict 'refs';
    *{"${caller}::loc"} = \&loc;
}

sub loc {
    my ($message, @arguments) = @_;
    for my $index (0 .. $#arguments) {
        my $number = $index + 1;
        my $replacement = defined $arguments[$index] ? $arguments[$index] : '';
        $message =~ s/%$number/$replacement/g;
    }
    return $message;
}

1;
