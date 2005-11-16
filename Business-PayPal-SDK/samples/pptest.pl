#!/usr/bin/perl
#

use strict;
use warnings;

use lib qw#../blib/lib#;

use Business::PayPal::SDK;

$Business::PayPal::SDK::PPCONINFO = 1;
my $pp = new Business::PayPal::SDK({java_sdk_dir => "/var/www/cgi-bin/xmlrpc/paypal_java_sdk"});

my $req = {
  FirstName => 'Big',
  LastName => 'Spender',
  MiddleName => 'Cash',
  Street1 => '2211 N. First St.',
  CityName => 'San Jose',
  StateOrProvince => 'CA',
  PostalCode => '95131',
  Country => 'US',
  CreditCardNumber => '4138848780259668',
  ExpMonth => 1,
  ExpYear => 2006,
  CVV2 => '000',
  CardType => 'Visa',
  OrderTotal => '39.85',
  IPAddress => '216.234.213.44',
};

my $res = $pp->DoDirectPayment($req);

use Data::Dumper;
print Dumper($res);
print "\n";
print $pp->error if $pp->error;
print "\n";
