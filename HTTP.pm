
package POE::Component::Server::HTTP;

use strict;
use Socket qw(inet_ntoa);
use HTTP::Date;
use HTTP::Status;
use File::Spec;
use Exporter();

use vars qw(@ISA @EXPORT $VERSION);
@ISA = qw(Exporter);
use constant RC_WAIT => -1;
use constant RC_DENY => -2;
@EXPORT = qw(RC_OK RC_WAIT RC_DENY);

use POE qw(Wheel::ReadWrite Driver::SysRW Session Filter::Stream Filter::HTTPD);
use POE::Component::Server::TCP;
use Sys::Hostname qw(hostname);


$VERSION = 0.04;

use POE::Component::Server::HTTP::Response;
use POE::Component::Server::HTTP::Request;
use POE::Component::Server::HTTP::Connection;

use Carp;

my %default_headers = (
		       "Server" => "POE HTTPD Compontent/$VERSION ($])",       
		       );



sub new {
  my $class = shift;
  my $self = bless {@_},$class;
  $self->{Headers} = { %default_headers,  ($self->{Headers} ? %{$self->{Headers}}: ())};



  $self->{TransHandler} = [] unless($self->{TransHandler});
  $self->{PreHandler} = {} unless($self->{PreHandler});
  $self->{PostHandler} = {} unless($self->{PostHandler});
  if(ref($self->{ContentHandler}) ne 'HASH') {
    croak "You need a default content handler or a ContentHandler setup" unless(ref($self->{DefaultContentHandler}) eq 'CODE');
    $self->{ContentHandler} = {};
    $self->{ContentHandler}->{'/'} = $self->{DefaultContentHandler};
  }

  $self->{Hostname} = hostname() unless($self->{Hostname});

  my $alias = "PoCo::Server::HTTP::";
  my $session =  POE::Session->create
    (
     inline_states => {
		       _start => sub {
			 $_[KERNEL]->alias_set($alias . $_[SESSION]->ID);
		       },
		       _stop => sub { },
		       accept => \&accept,
		       input => \&input,
		       execute => \&execute,
		       shutdown => sub {
			 my ($kernel, $session, $heap) = @_[KERNEL, SESSION, HEAP];
			 $kernel->call($alias . "TCP::" . $session->ID, "shutdown");
			 $kernel->alias_remove($alias . $session->ID);
		       },
		      },
     heap => { self => $self }
    );


  POE::Component::Server::TCP->new( Port => $self->{Port}, Acceptor => sub {
				      $poe_kernel->post($session,'accept',@_[ARG0,ARG1,ARG2]);
				    });
 
}



sub accept {
      my ($socket,$remote_addr, $remote_port) = @_[ARG0,ARG1,ARG2]; 
      my $self = $_[HEAP]->{self};
      my $connection = POE::Component::Server::HTTP::Connection->new();
      $connection->{remote_ip} = inet_ntoa($remote_addr);
      $connection->{remote_addr} = getpeername($socket);
      $connection->{local_addr} = getsockname($socket);

      $connection->{handlers} = {TransHandler => [@{$self->{TransHandler}}],
				 PreHandler   => [],
				 ContentHandler => undef,
				 PostHandler  => [],
				 Handler => [qw(
						TransHandler
						Map
						PreHandler 
						ContentHandler 
						Send
						PostHandler
						Cleanup
						)],
			     };
      
      my $wheel = POE::Wheel::ReadWrite->new(
	      Handle => $socket,
	      Driver => POE::Driver::SysRW->new,
	      Filter => POE::Filter::HTTPD->new(),
	      InputEvent => 'input',
	      FlushedEvent => 'execute',
	      );
      $_[HEAP]->{wheels}->{$wheel->ID} = $wheel; 
      $_[HEAP]->{c}->{$wheel->ID} = $connection
}

sub execute {
    my $id = $_[ARG0];
    my $self = $_[HEAP]->{self};
    my $connection = $_[HEAP]->{c}->{$id};
    my $handlers = $connection->{handlers};

    my $response = $connection->{response};
    my $request  = $connection->{request};

#    print Data::Dumper::Dumper($handlers);

    my $state = $handlers->{Handler}->[0];
  HANDLERS: while(1) {
      $state = $handlers->{Handler}->[0];

      
      if($state eq 'Map') {
	    my $path = $request->uri->path();
	    my $filename;
	    (undef, $path,$filename) = File::Spec->splitpath($path);
	    my @dirs = File::Spec->splitdir($path);
	    pop @dirs;
	    push(@dirs, $filename) if($filename);
	    my $fulldir;
	    
	    my(@pre,$content,@post);
	    
	    foreach my $dir (@dirs) {
		$fulldir .= $dir.'/';
		if(exists($self->{PreHandler}->{$fulldir})) {
		    push @{$handlers->{PreHandler}}, @{$self->{PreHandler}->{$fulldir}};
		}	    
		if(exists($self->{PostHandler}->{$fulldir})) {
		    push @{$handlers->{PostHandler}}, @{$self->{PostHandler}->{$fulldir}};
		}
		if(exists($self->{ContentHandler}->{$fulldir})) {
		    $handlers->{ContentHandler} = $self->{ContentHandler}->{$fulldir};
		}
		
	    }
	    $state = shift @{$handlers->{Handler}};
	    next;
	} elsif($state eq 'Send') {
	    $response->header(%{$_[HEAP]->{self}->{Headers}});
	    unless($response->header('Date')) {
		$response->header('Date',time2str(time));
	    }
	    if(!($response->header('Content-Lenth')) && !($response->streaming())) {
		$response->header('Content-Length',length($response->content));
	    }
	    

	    $_[HEAP]->{wheels}->{$id}->put($response);
	    $state = shift @{$handlers->{Handler}};
	    last;
	} elsif($state eq 'ContentHandler') {
	    my $retvalue = $handlers->{ContentHandler}->($request,$response);
	    $state = shift @{$handlers->{Handler}};
	    if($retvalue == RC_WAIT) {
		last HANDLERS;
	    }
	    next;
	} elsif($state eq 'Cleanup') {
	    if($response->streaming()) {
		print "Turn on streaming\n";
		$_[HEAP]->{wheels}->{$id}->set_output_filter(POE::Filter::Stream->new() );
		unshift(@{$handlers->{Handler}},'Streaming');
		next HANDLERS;
	    }
	    delete($response->{connection});
	    delete($request->{connection});
	    delete($connection->{handlers});
	    delete($connection->{wheel});
	    delete($_[HEAP]->{c}->{$id});
	    delete($_[HEAP]->{wheels}->{$id});
	    last;
	} elsif($state eq 'Streaming') {
	    print "Streaming mode\n";
	    $self->{StreamHandler}->($request, $response);
	    last HANDLERS;;
	}

      DISPATCH: while(1) {
	  
	  my $handler = shift(@{$handlers->{$state}});
	  last DISPATCH unless($handler);
	  my $retvalue = $handler->($request,$response);
	  
	  if($retvalue == RC_DENY) {
	      last DISPATCH;
	  } elsif($retvalue == RC_WAIT) {
	      last HANDLERS;
	  }
	  
      }

	
	$state = shift @{$handlers->{Handler}};
	last unless($state);
    }

}

sub input {
    my ($request,$id) = @_[ARG0, ARG1];
    bless $request, 'POE::Component::Server::HTTP::Request';
    my $c = $_[HEAP]->{c}->{$id};
    my $self = $_[HEAP]->{self};

    $request->uri->scheme('http');
    $request->uri->host($self->{Hostname});
    $request->uri->port($self->{Port});
    $request->{connection} = $c;


    my $response = POE::Component::Server::HTTP::Response->new();

    $response->{connection} = $c;

    $c->{wheel} = $_[HEAP]->{wheels}->{$id};

    $c->{request} = $request;
    $c->{response} = $response;
    $c->{session} = $_[SESSION];
    $c->{my_id} = $id;
    $poe_kernel->yield('execute',$id);
    
}

=head1 NAME

POE::Component::Server::HTTP - Foundation of a POE HTTP Daemon

=head1 SYNOPSIS

    use POE::Component::Server::HTTP;
    use HTTP::Status;
    $httpd = POE::Component::Server::HTTP->new(
       Port => 8000,
       ContentHandler => { '/' => \&handler },
       Headers => { Server => 'My Server' },
      );
    
    sub handler {
	my ($request, $response) = @_;
	$response->code(RC_OK);
	$response->content("Hi, you fetched ". $request->uri);
	return RC_OK;	
    }

	POE::Kernel->call($httpd, "shutdown");

=head1 DESCRIPTION

POE::Component::Server::HTTP (PoCo::HTTPD) is a framework for building
custom HTTP servers based on POE. It is loosely modeled on the ideas of 
apache and the mod_perl/Apache module.

It is built alot on work done by Gisle Aas on HTTP::* modules and the URI
module which are subclassed.

PoCo::HTTPD lets you register different handler, stacked by directory that
will be run during the cause of the request.

=head2 Handlers

Handlers are put on a stack in fifo order. The path /foo/bar/baz/ will
first push the handlers of / then of /foo/ then of /foo/bar/ and lastly
/foo/bar/baz/, 

However, there can be only one ContentHandler and if any handler installs
a ContentHandler that will override the old ContentHandler.

If no handler installs a ContentHandler it will find the closest one directory wise and use it.

There is also a special StreamHandler which is a coderef that gets invoked if you have turned on streaming by doing $response->streaming(1);

Handlers take the $request and $response objects as arguments.

=over 4

=item RC_OK

Everything is ok, please continue processing.

=item RC_DENY

If it is a TransHandler, stop translation handling and carry on with
a PreHandler, if it is a PostHandler do nothing, else return denied to 
the client.

=item RC_WAIT

This is a special handler that suspends the execution of the handlers.
They will be suspended until $response->continue() is called, this is 
usefull if you want to do a long request and not blocck.

=back

The following handlers are available.

=over 4

=item TransHandler

TransHandlers are run before the URI has been resolved, giving them a chance
to change the URI. They can therefore not be registred per directory.

    new(TransHandler => [ sub {return RC_OK} ]);

A TransHandler can stop the dispatching of TransHandlers and jump to the next
handler type by specifing RC_DENY;

=item PreHandler

PreHandlers are stacked by directory and run after TransHandler but before
the ContentHandler. They can change ContentHandler (but beware, other PreHandlers
might also change it) and push on PostHandlers.

    new(PreHandler => { '/' => [sub {}], '/foo/' => [\&foo]});

=item ContentHandler

The handler that is supposed to give the content. When this handler returns
it will send the response object to the client. It will automaticly add
Content-Length and Date if these are not set. If the response is streaming
it will make sure the correct headers are set. It will also expand any cookies
which have been pushed onto the response object.

    new(ContentHandler => { '/' => sub {}, '/foo/' => \&foo});

=item PostHandler

These handlers are run after the socket has been flushed.

    new(PostHandler => { '/' => [sub {}], '/foo/' => [\&foo]});

=back

=head1 Events

The C<shutdown> event may be sent to the component indicating that it should shut down.  The event may be sent using the return value of the I<new()> method (which is a session id) by either post()ing or call()ing.

I've experienced some problems with the session not receiving the event when it gets post()ed so call() is advised.
 
=head1 See Also

Please also take a look at L<HTTP::Response>, L<HTTP::Request>, 
L<URI>, L<POE> and L<POE::Filter::HTTPD>

=head1 TODO

=over 4

=item Document Connection Response and Request objects.

=item Write tests

=item Add a PoCo::Server::HTTP::Session that matches a http session against poe session using cookies or other state system

=item Add more options to streaming

=item Figure out why post()ed C<shutdown> events don't get received.

=item Probably lots of other API changes

=back

=head1 Author

Arthur Bergman, arthur@contiller.se

Released under the same terms as POE.

=cut
1;











