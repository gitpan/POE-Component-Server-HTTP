use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'POE::Component::Server::HTTP',
    'VERSION_FROM'	=> 'lib/POE/Component/Server/HTTP.pm', # finds $VERSION
    'PREREQ_PM'		=> {
	POE => '0.27',
	File::Spec => 0,
	HTTP::Date => 0,
	HTTP::Status => 0,
    }, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM => 'lib/POE/Component/Server/HTTP.pm', # retrieve abstract from module
       AUTHOR     => 'Arthur Bergman') : ()),
);
