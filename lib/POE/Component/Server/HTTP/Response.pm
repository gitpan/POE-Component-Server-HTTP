
package POE::Component::Server::HTTP::Response;

use strict;

use vars qw(@ISA);
use HTTP::Response;
@ISA = qw(HTTP::Response);

use POE;


sub streaming {
    my $self = shift;
    if(@_) {
	if($_[0]) {
	    $self->{streaming} = 1;
	} else {
	    $self->{streaming} = 0;
	}
    }
    return $self->{streaming};
}

sub send {
    my $self = shift;
    $self->{connection}->{wheel}->put(@_);
}

sub continue {
    my $self = shift;
    $poe_kernel->post($self->{connection}->{session},'execute',$self->{connection}->{my_id});
}


sub close {
    my $self = shift;
    $self->{streaming} = 0;
    print shift @{$self->{connection}->{handlers}->{Handler}};
}

1;













