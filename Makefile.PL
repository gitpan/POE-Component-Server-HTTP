use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'POE::Component::Server::HTTP',
    'VERSION_FROM'	=> 'HTTP.pm', # finds $VERSION
    'PM' => {
    	'lib/Request.pm' => '${INST_LIBDIR}/HTTP/Request.pm',
    	'lib/Connection.pm' => '${INST_LIBDIR}/HTTP/Connection.pm',
    	'lib/Response.pm' => '${INST_LIBDIR}/HTTP/Response.pm',
    	'HTTP.pm' => '${INST_LIBDIR}/HTTP.pm',
    	},
    'PREREQ_PM'		=> {
	POE => '0.27',
	File::Spec => 0,
	HTTP::Date => 0,
	HTTP::Status => 0,
    }, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'HTTP.pm', # retrieve abstract from module
       AUTHOR     => 'Arthur Bergman') : ()),
);
