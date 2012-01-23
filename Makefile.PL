use 5.012004;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Finance::Quant',
    VERSION_FROM      => 'lib/Finance/Quant.pm', # finds $VERSION
    PREREQ_PM         => {"WWW::Mechanize"=>0,
"Carp"=>0,
"Data::Dumper"=>0,
"File::Spec::Functions"=>0,
"File::Path"=>0,
"Time::Local"=>0,
"File::Fetch"=>0,
"File::Copy"=>0,
"File::Find"=>0,
"Finance::Optical::StrongBuy"=>0,
"HTML::TreeBuilder"=>0,
"Text::Buffer"=>0}
, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Finance/Quant.pm', # retrieve abstract from module
       AUTHOR         => 'Hagen Geissler <santex@cpan.org>') : ()),
);
