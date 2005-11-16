package Business::PayPal::SDK;

#$Id: SDK.pm,v 1.3 2005/11/16 02:31:42 jacob Exp $

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
our $VERSION = '0.12';
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
    return undef;
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
  package Business::PayPal::SDK;

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
    $prof->setCertificateFile($s->java_sdk_dir . "/samples/Cert/sdk-seller.p12");
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
    if (ref $@) {
      $s->error("setAPIProfile failed: [" . $@->getMessage() . '] [' . $@ . ']');
    } else {
      $s->error("setAPIProfile failed: [$@]");
    }
    return undef;
  }

  $s->paypal($caller);
  return 1;
}

sub DoDirectPayment {
  my $s = shift;
  my $args = shift;

  unless ($s->paypal) {
    unless ($s->init_java) {
      $s->error("could not init_java.");
      return undef;
    }
  }

  my $reqs = [
    qw/
      OrderTotal
      FirstName
      LastName
      CreditCardNumber
      ExpMonth
      ExpYear
      Street1
      CityName
      StateOrProvince
      IPAddress
    /
  ];

  return undef unless ($s->_checkRequires($reqs, $args));

  package main;
  Inline::Java::study_classes(
    [
      qw(
        com.paypal.soap.api.DoDirectPaymentRequestDetailsType
        com.paypal.soap.api.DoDirectPaymentRequestType
        com.paypal.soap.api.DoDirectPaymentResponseType
        com.paypal.soap.api.PaymentActionCodeType
        com.paypal.soap.api.PaymentDetailsType
        com.paypal.soap.api.ErrorType
        com.paypal.soap.api.PaymentCodeType
        com.paypal.soap.api.CurrencyCodeType
        com.paypal.soap.api.BasicAmountType
        com.paypal.soap.api.PayerInfoType
        org.apache.axis.types.Token
        com.paypal.soap.api.AckCodeType
      )
    ]
  );
  package Business::PayPal::SDK;

  my $resp;
  eval {
	  my $requestDetails = com::paypal::soap::api::DoDirectPaymentRequestDetailsType->new();
	  $requestDetails->setPaymentAction($com::paypal::soap::api::PaymentActionCodeType::Sale);
	
	  my $paymentDetails = com::paypal::soap::api::PaymentDetailsType->new();
	  my $totalAmount = com::paypal::soap::api::BasicAmountType->new();
	  $totalAmount->set_value($args->{OrderTotal});
	  $totalAmount->setCurrencyID($com::paypal::soap::api::CurrencyCodeType::USD);
	
	  $paymentDetails->setOrderTotal($totalAmount);
	
	  my $creditCard = $s->_getCreditCard($args);
	  my $payerName = $s->_getPersonName($args);
	  
	  my $payerInfo = com::paypal::soap::api::PayerInfoType->new();
	  $payerInfo->setPayerName($payerName);
	
	  my $payerAddress = $s->_getAddress($args);
	  $payerInfo->setAddress($payerAddress);
	  $creditCard->setCardOwner($payerInfo);
	
	  $requestDetails->setCreditCard($creditCard);
	  $requestDetails->setPaymentDetails($paymentDetails);
	  $requestDetails->setIPAddress($args->{IPAddress});
	
	  my $paymentRequest = com::paypal::soap::api::DoDirectPaymentRequestType->new();
	  $paymentRequest->setDoDirectPaymentRequestDetails($requestDetails);
	  
	  $resp = $s->paypal->call("DoDirectPayment", $paymentRequest);
  };
	
  my $ret = {};
  if ($@) {
    if (Inline::Java::caught('java.lang.Exception')) {
      $s->error("DoDirectPayment failed: [" . $@->getMessage() . '] [' . $@->toString() . ']');
      return undef;
    } else {
      $s->error($@);
      return undef;
    }
  }

  my $ack = $resp->getAck();
  $ret->{ack} = $ack->toString;

  if ($ret->{ack} eq 'Success') {
    my $Amount = $resp->getAmount;
    $ret->{Amount}->{value} = $Amount->get_value;
    $ret->{Amount}->{Currency} = $Amount->getCurrencyID->toString;
    $ret->{TransactionID} = $resp->getTransactionID;
    $ret->{AVSCode} = $resp->getAVSCode;
    $ret->{CVV2Code} = $resp->getCVV2Code;
  } else {
    $ret->{ErrorCodes} = $s->_getErrorHash($resp->getErrors);
  }

  return $ret;
}

sub _getCreditCard {
  my $s = shift;
  my $args = shift;

  my $reqs = [
    qw/
      CreditCardNumber
      ExpMonth
      ExpYear
      CardType
    /
  ];

  return undef unless $s->_checkRequires($reqs, $args);

  $args->{CVV2} ||= 000;
  package main;
  require Inline::Java;
  Inline::Java::study_classes(
    [
      qw(
        com.paypal.soap.api.CreditCardDetailsType
      )
    ]
  );
  package Business::PayPal::SDK;

  my $creditCard;
  eval {
    $creditCard = com::paypal::soap::api::CreditCardDetailsType->new();
    $creditCard->setCreditCardNumber($args->{CreditCardNumber});
    $creditCard->setExpMonth($args->{ExpMonth});
    $creditCard->setExpYear($args->{ExpYear});
    $creditCard->setCVV2($args->{CVV2});
    $creditCard->setCreditCardType($s->_getCardType($args->{CardType}));
  };

  if ($@) {
    $s->error("getCreditCard failed: " . $@->getMessage());
    return undef;
  } else {
    return $creditCard;
  }
}

sub _getPersonName {
  my $s = shift;
  my $args = shift;

  my $reqs = [
    qw/
      FirstName
      LastName
    /
  ];

  package main;
  require Inline::Java;
  Inline::Java::study_classes(
    [
      qw(
        com.paypal.soap.api.PersonNameType
      )
    ]
  );
  package Business::PayPal::SDK;

  my $payerName;
  eval {
    $payerName = com::paypal::soap::api::PersonNameType->new();
    $payerName->setFirstName($args->{FirstName});
    $payerName->setLastName($args->{LastName});
    $payerName->setMiddleName($args->{MiddleName}) if $args->{MiddleName};
    $payerName->setSalutation($args->{Salutation}) if $args->{Salutation};
    $payerName->setSuffix($args->{Suffix}) if $args->{Suffix};
  };

  if ($@) {
    $s->error("getPersonName failed: [" . $@->getMessage() . ']' . ' [' . $@->toString() . ']');
    return undef;
  } else {
    return $payerName;
  }
}

sub _getCardType {
  my $s = shift;
  my $type = shift;

  unless ($type) {
    $s->error("You must pass a card type to _getCardType");
    return undef;
  }

  package main;
  require Inline::Java;
  Inline::Java::study_classes(
    [
      qw(
        com.paypal.soap.api.CreditCardTypeType
      )
    ]
  );
  package Business::PayPal::SDK;

  my $ccType;
  eval {
    $ccType = com::paypal::soap::api::CreditCardTypeType->fromString($type);
  };

  if ($@) {
    $s->error("getCreditCardType failes: [" . $@->getMessage() . "] [" . $@->toString() . ']');
    return undef;
  } else {
    return $ccType;
  }
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

  my $reqs = [
    qw/
      token
      PayerID
      OrderTotal
    /
  ];

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
  package Business::PayPal::SDK;

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
    $ret->{ErrorCodes} = $s->_getErrorHash($resp->getErrors);
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
  package Business::PayPal::SDK;

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
    $ret->{ErrorCodes} = $s->_getErrorHash($resp->getErrors);
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

  my $reqs = [
    qw/
      OrderTotal
      ReturnURL
      CancelURL
    /
  ];

  return undef unless $s->_checkRequires($reqs, $args);
 
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
        com.paypal.sdk.exceptions.PayPalException
      )
    ]
  );
  package Business::PayPal::SDK;

  my $resp;
  eval {
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
    $resp = $s->paypal->call("SetExpressCheckout", $request);
  };
  my $ret = {};

  if ($@) {
    if (ref $@) {
      $s->error("SetExpressCheckout failed: [" . $@->getMessage() . '] [' . $@ . ']');
    } else {
      $s->error("SetExpressCheckout failed: [$@]");
    }
    return undef;
  }

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

sub _getAddress {
  my $s = shift;
  my $args = shift;

  my @requires = qw/
    Street1
    CityName
    StateOrProvince
    PostalCode
    Country
  /;
  return undef unless $s->_checkRequires(\@requires, $args);
  package main;
  require Inline::Java;
  Inline::Java::study_classes(
    [
      qw(
        com.paypal.soap.api.AddressType
      )
    ]
  );
  package Business::PayPal::SDK;
 
  my $AddressObj;
  eval { 
    $AddressObj = com::paypal::soap::api::AddressType->new();
    $AddressObj->setStreet1($args->{Street1});
    $AddressObj->setStreet2($args->{Street2}) if $args->{Street2};
    $AddressObj->setCityName($args->{CityName});
    $AddressObj->setStateOrProvince($args->{StateOrProvince});
    $AddressObj->setPostalCode($args->{PostalCode});
    $AddressObj->setCountry($s->_getCountryCode($args->{Country}));
  };

  if ($@) {
    $s->error("getAddress failed: [" . $@->getMessage() . '] [' . $@->toString() . ']');
    return undef;
  } else {
    return $AddressObj;
  }
}

sub _getCountryCode {
  my $s = shift;
  my $cc = shift;

  $cc ||= '';
  unless ($cc && $cc =~ /^[A-Z]{2}$/) {
    $s->error("You must pass a valid code to _getCountryCode. [$cc]");
    return 
  }

  package main;
  require Inline::Java;
  Inline::Java::study_classes(
    [
      qw(
        com.paypal.soap.api.CountryCodeType
      )
    ]
  );
  package Business::PayPal::SDK;
  
  my $code;
  eval {
   $code = com::paypal::soap::api::CountryCodeType->fromString($cc);
  };

  if ($@) {
    $s->error("getCountryCode failed: [" . $@->getMessage() . '] [' . $@->toString() . ']');
    return undef;
  } else {
    return $code;
  }
}

sub _checkRequires {
  my $s = shift;
  my $reqs = shift;
  my $args = shift;

  unless (ref $reqs) {
    my $s->error('You must pass an arrayref to check_requires.');
    return undef;
  }

  foreach my $req (@$reqs) {
    unless ($args->{$req}) {
      my @stack = caller(1);
      $s->error("$req is required for method $stack[3]");
      return undef;
    }
  }
  return 1;
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
        com.paypal.sdk.exceptions.TransactionException
        com.paypal.sdk.exceptions.PayPalException
        com.paypal.soap.api.ErrorType
        java.util.Calendar
        java.lang.String
      )
    ]
  );
  package Business::PayPal::SDK;
  
  my $request = com::paypal::soap::api::TransactionSearchRequestType->new();
  my $jcal = Inline::Java::cast('java.util.Calendar', java::util::Calendar->getInstance());
  $jcal->set(@{$args->{date}});
  $request->setStartDate($jcal);

  my $resp = $s->paypal->call("TransactionSearch", $request);

  my $ackcode = $resp->getAck();

  print $ackcode->toString;
  my $ret = {};
  $ret->{ErrorCodes} = $s->_getErrorHash($resp->getErrors);
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

sub _getErrorHash {
  my $s = shift;
  my $errors = shift;

  my $ErrorCodes = {};
  foreach my $err (@$errors) {
    my $token = $err->getErrorCode;
    $s->error($err->getLongMessage) if $err;
    $ErrorCodes->{$token->toString} = $err->getLongMessage if ($err && $token);
  }
  return $ErrorCodes;
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

Business::PayPal::SDK is a perl interface to the SDK provided by paypal (http://www.paypal.com/sdk). You can use this module to implement paypal pro and paypal express transactions in perl. On the back end this modules uses Inline::Java to interface directly with the paypals java sdk. Consequently you will need to get a J2SDK and Inline::Java installed.  This was done for 2 reasons. 1) Speed of development, didnt have to deal with all the SOAP stuff. 2) Easier maintanance regarding future changes. That is to say, I only have to make sure I keep this compatiable with paypals SDK, not thier underlying protocol changes.

All methods take a single hashref as an argument.
All methods return a hashref, or undef if there is a failure. Check $obj->error for description of failure.

=head1 Public Methods

$resp = DoExpressCheckoutPayment({ arg => value, args => value })

$resp = GetExpressCheckoutDetails({ args => value, args => value })

$resp = SetExpressCheckout({ args => value, args => value })

$resp = DoDirectPayment({ args => value, args => value })

=head1 NOTES

This modules is currently in development, not all methods in the paypal SDK are implemented yet.

=head1 BUGS

Non that I am aware of yet. :) Please email if you find any.

=head1 AUTHOR

Jacob Boswell <jacob@s56.net>

Also thanks to Rob Brown for assistance.

=head1 COPYRIGHT

Business::PayPal::SDK is Copyright(c) 2005 Jacob Boswell. All rights reserved
You may distribute under the terms of either the GNU General Public License or the Artistic License, as specified in the Perl README file.

=cut
