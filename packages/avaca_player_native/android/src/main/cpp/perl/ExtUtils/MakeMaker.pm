package ExtUtils::MakeMaker;

use strict;
use warnings;

# IPC::Cmd uses only MM->maybe_command while quictls discovers its build
# tools. Git-for-Windows' reduced Perl distribution omits the full module;
# this bounded implementation preserves the file/executable probe without
# adding a package manager dependency to the Android build.
sub import { return 1; }

package MM;

sub maybe_command {
    my ($class, $path) = @_;
    return unless defined $path && -f $path;
    return $path if -x $path || $path =~ /\.exe\z/i;
    return;
}

1;
