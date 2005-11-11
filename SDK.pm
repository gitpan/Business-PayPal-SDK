package Business::PayPal::SDK;

use strict;
use warnings;

use base qw/Class::Accessor/;
my @ACCESSORS = qw/
  paypal_apiid
  paypal_apipw
  paypal_cert
  paypal_certpw
  paypal_env
  java_sdk_dir
/;
use Data::Dumper;

__PACKAGE__->mk_accessors (@ACCESSORS, "paypal");

our $ERROR = '';
our $PPCONINFO = undef;

sub new {
  my $pkg = shift;
  my $args = shift;

  my $self = {
  };

  my $s = SUPER::new $pkg $self;

  foreach my $ac (@ACCESSORS) {
    $s->$ac($args->{$ac}) if ($args->{$ac});
  }

  unless ($s->java_sdk_dir) {
    $s->error("WARNING: java_sdk_dir must be set.");
  }
  return $s;
}

sub init_java {
  my $s = shift;

  my @study = qw(
    java.util.HashMap
    com.paypal.sdk.exceptions.PayPalException
    com.paypal.sdk.profiles.APIProfile
    com.paypal.sdk.profiles.ProfileFactory
    com.paypal.sdk.services.CallerServices
  );

  $ENV{CLASSPATH} = $s->get_classpath;

  ## Terrible hack to make Inline work in a module
  package main;
  require Inline;
  import Inline (
    Java => 'STUDY',
    STUDY => [],
    CLASSPATH => $ENV{CLASSPATH},
    JNI => 1,
    DIRECTORY => "/tmp",
  );
  Inline::Java::study_classes(\@study);
  package C::PayPal;

  foreach my $ac (@ACCESSORS) {
    if (!$s->$ac and !$PPCONINFO) {
      $s->error("$ac not set.");
    }
    return undef if $s->error;
  }
  my $prof = Inline::Java::cast('com.paypal.sdk.profiles.APIProfile', com::paypal::sdk::profiles::ProfileFactory->createAPIProfile());

  ## Test values from sdk
  if ($PPCONINFO) {
    $prof->setAPIUsername("sdk-seller_api1.sdk.com");
    $prof->setAPIPassword("12345678");
    $prof->setCertificateFile("paypal_java_sdk/samples/Cert/sdk-seller.p12");
    $prof->setPrivateKeyPassword("password");
    $prof->setEnvironment("sandbox");
  } else {
    $prof->setAPIUsername($s->paypal_apiid);
    $prof->setAPIPassword($s->paypal_apipw);
    $prof->setCertificateFile($s->paypal_cert);
    $prof->setPrivateKeyPassword($s->paypal_certpw);
    $prof->setEnvironment($s->paypal_env);
  }

  my $caller = com::paypal::sdk::services::CallerServices->new();

  eval {
    $caller->setAPIProfile($prof);
  };

  if ($@) {
    $s->error($@->getMessage());
    return undef;
  }

  $s->paypal($caller);
  return 1;
}

sub DoExpressCheckoutPayment {
  my $s = shift;
  my $args = shift;

  unless ($s->paypal) {
    unless ($s->init_java) {
      $s->error("could not init_java.");
      return undef;
    }
  }

  unless ($args->{token}) {
    $s->error("token must be defined in DoExpressCheckoutPayment.");
    return undef;
  }
  
  unless ($args->{PayerID}) {
    $s->error("PayerID must be defined in DoExpressCheckoutPayment.");
    return undef;
  }

  unless ($args->{OrderTotal}) {
    $s->error("OrderTotal must be defined in DoExpressCheckoutPayment.");
    return undef;
  }

  package main;
  Inline::Java::study_classes(
    [
      qw(
        com.paypal.soap.api.AckCodeType
        com.paypal.soap.api.BasicAmountType
        com.paypal.soap.api.CurrencyCodeType
        com.paypal.soap.api.DoExpressCheckoutPaymentRequestDetailsType
        com.paypal.soap.api.DoExpressCheckoutPaymentRequestType
        com.paypal.soap.api.DoExpressCheckoutPaymentResponseDetailsType
        com.paypal.soap.api.DoExpressCheckoutPaymentResponseType
        com.paypal.soap.api.ErrorType
        com.paypal.soap.api.PaymentActionCodeType
        com.paypal.soap.api.PaymentCodeType
        com.paypal.soap.api.PaymentDetailsType
        com.paypal.soap.api.PaymentInfoType
        com.paypal.soap.api.PaymentStatusCodeType
        com.paypal.soap.api.PaymentTransactionCodeType
        java.util.Calendar
        org.apache.axis.types.Token
      )
    ]
  );
  package C::PayPal;

  my $request = com::paypal::soap::api::DoExpressCheckoutPaymentRequestType->new();
  my $requestDetails = com::paypal::soap::api::DoExpressCheckoutPaymentRequestDetailsType->new();
  $requestDetails->setToken($args->{token});
  $requestDetails->setPayerID($args->{PayerID});
  $requestDetails->setPaymentAction($com::paypal::soap::api::PaymentActionCodeType::Sale);
  
  my $paymentDetails = com::paypal::soap::api::PaymentDetailsType->new();
  my $orderTotal = com::paypal::soap::api::BasicAmountType->new();

  $orderTotal->set_value($args->{OrderTotal});
  $orderTotal->setCurrencyID($com::paypal::soap::api::CurrencyCodeType::USD);

  $paymentDetails->setOrderTotal($orderTotal);

  $requestDetails->setPaymentDetails($paymentDetails);

  $request->setDoExpressCheckoutPaymentRequestDetails($requestDetails);

  my $resp = $s->paypal->call('DoExpressCheckoutPayment', $request);

  my $responseDetails = $resp->getDoExpressCheckoutPaymentResponseDetails();

  my $ret= {};

  my $ack = $resp->getAck();
  $ret->{ack} = $ack->toString;

  $ret->{Token} = $responseDetails->getToken;
  
  my $paymentInfo = $responseDetails->getPaymentInfo();
  
  if ($ret->{ack} eq 'Success') {
	  my $feeAmount = $paymentInfo->getFeeAmount();
	  
	  my $settleAmount = $paymentInfo->getSettleAmount();
	  
	  my $taxAmount = $paymentInfo->getTaxAmount();
	  
	  my $grossAmount = $paymentInfo->getGrossAmount();
	  
	  my $paymentStatus = $paymentInfo->getPaymentStatus();
	  
	  my $paymentType = $paymentInfo->getPaymentType();
	  
	  my $transactionType = $paymentInfo->getTransactionType();
	
	  my $paymentDate = Inline::Java::cast('java.util.Calendar', $paymentInfo->getPaymentDate());

	  $ret->{PaymentInfo} = {};
	
	  $ret->{PaymentInfo}->{PaymentStatus} = $paymentStatus->toString;
	  $ret->{PaymentInfo}->{PaymentType} = $paymentType->toString;
	  $ret->{PaymentInfo}->{ExchangeRate} = $paymentInfo->getExchangeRate();
	  $ret->{PaymentInfo}->{ParentTransactionID} = $paymentInfo->getParentTransactionID();
	  $ret->{PaymentInfo}->{TransactionID} = $paymentInfo->getTransactionID();
	  $ret->{PaymentInfo}->{TransactionType} = $transactionType->toString();
	  $ret->{PaymentInfo}->{ReceiptID} = $paymentInfo->getReceiptID();
	
	  $ret->{PaymentInfo}->{PaymentDate} = $s->_getDateString($paymentDate);
	  
	  $ret->{PaymentInfo}->{GrossAmount} = {};
    if ($grossAmount) {
	    $ret->{PaymentInfo}->{GrossAmount}->{value} = $grossAmount->get_value;
  	  $ret->{PaymentInfo}->{GrossAmount}->{CurrencyCode} = "USD";
    }
	
	  $ret->{PaymentInfo}->{FeeAmount} = {};
    if ($feeAmount) {
  	  $ret->{PaymentInfo}->{FeeAmount}->{value} = $feeAmount->get_value;
  	  $ret->{PaymentInfo}->{FeeAmount}->{CurrencyCode} = "USD";
    }
	 
	  $ret->{PaymentInfo}->{SettleAmount} = {};
    if ($settleAmount) {
  	  $ret->{PaymentInfo}->{SettleAmount}->{value} = $settleAmount->get_value;
  	  $ret->{PaymentInfo}->{SettleAmount}->{CurrencyCode} = "USD";
    }
	  
	  $ret->{PaymentInfo}->{TaxAmount} = {};
    if ($taxAmount) {
  	  $ret->{PaymentInfo}->{TaxAmount}->{value} = $taxAmount->get_value;
  	  $ret->{PaymentInfo}->{TaxAmount}->{CurrencyCode} = "USD";
    }
  } else {
    my $errors = $resp->getErrors;
    $ret->{ErrorCodes} = [];
    $ret->{LongMessages} = [];
    foreach my $err (@$errors) {
      $s->error($err->getLongMessage);
      my $token = $err->getErrorCode;
      push @{$ret->{ErrorCodes}}, $token->toString;
      push @{$ret->{LongMessages}}, $err->getLongMessage;
    }

    warn $s->error;

  }
  

  return $ret;
}

sub GetExpressCheckoutDetails {
  my $s = shift;
  my $args = shift;

  unless ($s->paypal) {
    unless ($s->init_java) {
      $s->error("could not init_java.");
      return undef;
    }
  }

  unless ($args->{token}) {
    $s->error("token must be defined in GetExpressCheckoutDetails.");
    return undef;
  }

  package main;
  Inline::Java::study_classes(
    [
      qw(
        com.paypal.soap.api.GetExpressCheckoutDetailsRequestType
        com.paypal.soap.api.GetExpressCheckoutDetailsResponseType
        com.paypal.soap.api.GetExpressCheckoutDetailsResponseDetailsType
        com.paypal.soap.api.PersonNameType
        com.paypal.soap.api.PayerInfoType
        com.paypal.soap.api.AddressType
        com.paypal.soap.api.ErrorType
        com.paypal.soap.api.AckCodeType
        org.apache.axis.types.Token
        com.paypal.soap.api.CountryCodeType
        com.paypal.soap.api.PayPalUserStatusCodeType
      )
    ]
  );
  package C::PayPal;

  my $request = com::paypal::soap::api::GetExpressCheckoutDetailsRequestType->new();
  $request->setToken($args->{token});

  my $resp = $s->paypal->call("GetExpressCheckoutDetails", $request);

  my $respDetails = $resp->getGetExpressCheckoutDetailsResponseDetails();
  
  my $payerInfo = $respDetails->getPayerInfo();
  
 
  my $ret = {};
  my $ack = $resp->getAck();
  $ret->{ack} = $ack->toString;
  if ($ret->{ack} eq 'Success') {
    $ret->{Custom} = $respDetails->getCustom;
    $ret->{InvoiceID} = $respDetails->getInvoiceID;
    $ret->{Token} = $respDetails->getToken;
  
	  $ret->{PayerInfo}->{Payer} = $payerInfo->getPayer;
	  $ret->{PayerInfo}->{PayerID} = $payerInfo->getPayerID;
	  $ret->{PayerInfo}->{PayerBusiness} = $payerInfo->getPayerBusiness;
    if ($payerInfo->getPayerCountry) {
  	  my $CountryCodeType = $payerInfo->getPayerCountry;
      $ret->{PayerInfo}->{PayerCountry} = $CountryCodeType->toString;
    }
	  
    my $PayerStatus = $payerInfo->getPayerStatus;
	  $ret->{PayerInfo}->{PayerStatus} = $PayerStatus->toString;
	  
    my $payerName = $payerInfo->getPayerName();
	
	  $ret->{PayerInfo}->{PayerName}->{FirstName} = $payerName->getFirstName();
	  $ret->{PayerInfo}->{PayerName}->{LastName} = $payerName->getLastName();
	
	  my $payerAddress = $payerInfo->getAddress();
	
	  $ret->{PayerInfo}->{PayerAddress}->{AddressID} = $payerAddress->getAddressID();
	  $ret->{PayerInfo}->{PayerAddress}->{CityName} = $payerAddress->getCityName();
	  my $CountryCodeType = $payerAddress->getCountry;
	  $ret->{PayerInfo}->{PayerAddress}->{Country} = $CountryCodeType->toString();
	  $ret->{PayerInfo}->{PayerAddress}->{CountryName} = $payerAddress->getCountryName();
	  $ret->{PayerInfo}->{PayerAddress}->{Phone} = $payerAddress->getPhone();
	  $ret->{PayerInfo}->{PayerAddress}->{Name} = $payerAddress->getName();
	  $ret->{PayerInfo}->{PayerAddress}->{PostalCode} = $payerAddress->getPostalCode();
	  $ret->{PayerInfo}->{PayerAddress}->{StateOrProvince} = $payerAddress->getStateOrProvince();
	  $ret->{PayerInfo}->{PayerAddress}->{Street1} = $payerAddress->getStreet1();
	  $ret->{PayerInfo}->{PayerAddress}->{Street2} = $payerAddress->getStreet2();
  } else {
    my $errors = $resp->getErrors;
    $ret->{ErrorCodes} = [];
    $ret->{LongMessages} = [];
    foreach my $err (@$errors) {
      $s->error($err->getLongMessage);
      my $token = $err->getErrorCode;
      push @{$ret->{ErrorCodes}}, $token->toString;
      push @{$ret->{LongMessages}}, $err->getLongMessage;
    }

    warn $s->error;
  }
  return  $ret;
}

sub SetExpressCheckout {
  my $s = shift;
  my $args = shift;

  unless ($s->paypal) {
    unless ($s->init_java) {
      $s->error("could not init_java.");
      return undef;
    }
  }

  unless ($args->{OrderTotal}) {
    $s->error("OrderTotal must be defined in SetExpressCheckout.");
    return undef;
  }

  unless ($args->{ReturnURL}) {
    $s->error("ReturnURL must be defined in SetExpressCheckout.");
    return undef;
  }
  
  unless ($args->{CancelURL}) {
    $s->error("CancelURL must be defined in SetExpressCheckout.");
    return undef;
  }
  
  package main;
  Inline::Java::study_classes(
    [
      qw(
        com.paypal.soap.api.SetExpressCheckoutRequestType
        com.paypal.soap.api.SetExpressCheckoutResponseType
        com.paypal.soap.api.SetExpressCheckoutRequestDetailsType
        com.paypal.soap.api.BasicAmountType
        com.paypal.soap.api.CountryCodeType
        com.paypal.soap.api.CurrencyCodeType
        com.paypal.soap.api.ErrorType
      )
    ]
  );
  package C::PayPal;

  my $OrderTotalObj = com::paypal::soap::api::BasicAmountType->new($args->{OrderTotal});
  $OrderTotalObj->setCurrencyID($com::paypal::soap::api::CurrencyCodeType::USD);
  my $MaxAmountObj;
  if ($args->{MaxAmount}) {
    $MaxAmountObj = com::paypal::soap::api::BasicAmountType->new($args->{MaxAmount});
    $MaxAmountObj->setCurrencyID($com::paypal::soap::api::CurrencyCodeType::USD);
  }
  
  my $ReqDetails = com::paypal::soap::api::SetExpressCheckoutRequestDetailsType->new();
  $ReqDetails->setReturnURL($args->{ReturnURL});
  $ReqDetails->setCancelURL($args->{CancelURL});
  $ReqDetails->setOrderTotal($OrderTotalObj);
  
  $ReqDetails->setCustom($args->{Custom}) if $args->{Custom};
  $ReqDetails->setInvoiceID($args->{InvoiceID}) if $args->{InvoiceID};

  my $request = com::paypal::soap::api::SetExpressCheckoutRequestType->new();
  $request->setSetExpressCheckoutRequestDetails($ReqDetails);

  my $resp = $s->paypal->call("SetExpressCheckout", $request);
  my $ret = {};

  if ($resp->getToken()) {
    $ret->{token} = $resp->getToken();
    return $ret;
  } else {
    my $errors = $resp->getErrors;
    foreach my $err (@$errors) {
      $s->error($err->getLongMessage());
    }
    return undef;
  }
}

sub _getAddressObj {
  my $s = shift;
  my $args = shift;

  return undef;
  package main;
  Inline::Java::study_classes(
    [
      qw(
        com.paypal.soap.api.AddressType
      )
    ]
  );
  package C::PayPal;
  
  my $AddressObj = com::paypal::soap::api::AddressType->new();
  $AddressObj->setStreet1($args->{Street1});
  $AddressObj->setStreet2($args->{Street2}) if $args->{Street2};
  $AddressObj->setCityName($args->{CityName});
  $AddressObj->setStateOrProvince($args->{StateOrProvince});
  $AddressObj->setPostalCode($args->{PostalCode});
  $AddressObj->setCountryName($args->{CountryName});

  return $AddressObj;
}

sub TransactionSearch {
  my $s = shift;
  my $args = shift;

  unless ($s->paypal) {
    unless ($s->init_java) {
      $s->error("could not init_java.");
      return undef;
    }
  }

  package main;
  Inline::Java::study_classes(
    [
      qw(
        com.paypal.soap.api.TransactionSearchRequestType
        com.paypal.soap.api.TransactionSearchResponseType
        com.paypal.soap.api.AckCodeType
        java.util.Calendar
        java.lang.String
      )
    ]
  );
  package C::PayPal;
  
  my $request = com::paypal::soap::api::TransactionSearchRequestType->new();
  my $jcal = java::util::Calendar->getInstance();
  $jcal->set(@{$args->{date}});
  $request->setStartDate($jcal);

  my $resp = $s->paypal->call("TransactionSearch", $request);

  my $ackcode = $resp->getAck();
  print $ackcode->toString;
}

sub _getDateString {
  my $s = shift;
  my $dateObj = shift;

  return sprintf(
    "%04d-%02d-%02d %02d:%02d:%02d",
    $dateObj->get($dateObj->{YEAR}),
    $dateObj->get($dateObj->{MONTH}),
    $dateObj->get($dateObj->{DAY_OF_MONTH}),
    $dateObj->get($dateObj->{HOUR}),
    $dateObj->get($dateObj->{MINUTE}),
    $dateObj->get($dateObj->{SECOND}),
  );
}

sub error {
  my $s = shift;
  my $msg = shift;

  if ($msg) {
    $ERROR .= "$msg\n";
  }

  return $ERROR;
}

sub get_classpath {
  my $s = shift;

  my $pplibdir = $s->java_sdk_dir . "/lib";

  opendir DIR, "$pplibdir";
  my @jars;
  foreach my $jar (grep { /\.jar$/ } readdir(DIR)) {
    push @jars, "$pplibdir/$jar";
  }
  closedir DIR;
  return join ":", @jars;
}

1;

__END__
=head1 NAME

Business::PayPal::SDK - An interface to paypals SDK's.

=head1 SYNOPSIS

  use Business::PayPal::SDK;
  my $pp = new Business::PayPal::SDK(
    {
      paypal_apiid => "sdk-seller_api1.sdk.com",
      paypal_apipw => "12345678",
      paypal_cert => "paypal_java_sdk/samples/Cert/sdk-seller.p12",
      paypal_certpw => "password",
      paypal_env => "sandbox",
      java_sdk_dir => "/path/to/paypals/java/sdk",
    }
  );

  my $res = $pp->SetExpressCheckout(
    {
      OrderTotal => '10.00',
      ReturnURL => 'http:://mydomain.com/myreturn',
      CancelURL => 'http:://mydomain.com/mycancel',
    }
  );

  print $res->{token};

=head1 DESCRIPTION

  Business::PayPal::SDK is a perl interface to the SDK provided by paypal (http://www.paypal.com/sdk). You can use this module to implement paypal pro and paypal express transactions in perl. On the back end this modules uses Inline::Java to interface directly with the paypals java sdk. Consequently you will need to get a J2SDK and Inline::Java installed. This was done for 2 reasons. 1) Speed of development, didnt have to deal with all the SOAP stuff. 2) Easier maintanance regarding future changes. That is to say, I only have to make sure I keep this compatiable with paypals SDK, not thier underlying protocol changes. I would eventually like to support there PHP sdk as well, but we will have to see.

All methods take a single hashref as an argument.
All methods return a hashref, or undef if there is a failure. Check $obj->error for description of failure.

=head1 Public Methods

  DoExpressCheckoutPayment()

  GetExpressCheckoutDetails()

  SetExpressCheckout()

=head1 NOTES
  This modules is currently in development, not all methods in the paypal SDK are implemented yet.

=head1 BUGS
  Non that I am aware of yet. :) Please email if you find any.

=head1 AUTHOR

Jacob Boswell <jacob@bluehost.com>

Also thanks to Rob Brown for assistance.

=head1 COPYRIGHT

Business::PayPal::SDK is Copyright(c) 2006 Jacob Boswell. All rights reserved
You may distribute under the terms of either the GNU General Public License or the Artistic License, as specified in the Perl README file.

=back

=cut

