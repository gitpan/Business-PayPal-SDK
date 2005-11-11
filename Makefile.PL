#
# $Header: $
#
use ExtUtils::MakeMaker;
WriteMakefile(
	'NAME'	=> 'Business::PayPal::SDK',
	'VERSION' => '0.1',
	'DISTNAME' => 'Business-PayPal-SDK',
  'PREREQ_PM' => {
    'Class::Accessor' => 0,
    'Inline' => 0,
    'Inline::Java' => 0,
  },
  AUTHOR => "Jacob Boswell",
	'dist' => { COMPRESS => "gzip -9", SUFFIX => "gz" },
);

