
package POE::Component::Server::HTTP::Request;

use strict;

use vars qw(@ISA);
use HTTP::Request;
@ISA = qw(HTTP::Request);

sub connection {
    return $_[0]->{connection};
}



1;
