####################################################################
#
# ECDefectTracking::ALM::Driver  Object to represent interactions with 
#        ALM.
#
####################################################################
package ECDefectTracking::ALM::Driver;
@ISA = (ECDefectTracking::Base::Driver);
use ElectricCommander;
use Time::Local;
use File::Basename;
use File::Copy;
use File::Path;
use File::Spec;
use File::stat;
use File::Temp;
use FindBin;
use Sys::Hostname;

use LWP;
use HTTP::Request::Common;
use XML::Simple;
use XML::XPath;
use XML::XPath::XMLParser;
use Data::Dumper;
use POSIX qw/strftime/;

if (!defined ECDefectTracking::Base::Driver) {
    require ECDefectTracking::Base::Driver;
}

if (!defined ECDefectTracking::ALM::Cfg) {
    require ECDefectTracking::ALM::Cfg;
}

use strict;
use warnings;

$|=1;

use constant {
    SUCCESS => 1,
    ERROR => 0,
    
    PLUGIN_NAME => 'EC-DefectTracking-ALM',
    REPORT_NAME => 'ALM Report',
    
    METHOD_LINK_DEFECTS => 'linkDefects',
    METHOD_UPDATE_DEFECTS => 'updateDefects',
    METHOD_FILE_DEFECTS => 'fileDefect',
    METHOD_CREATE_DEFECTS => 'createDefects',
	
	ID_FIELD => 7,
	DESC_FIELD => 9,
	NAME_FIELD => 11,
	STATUS_FIELD => 24,
	SEVERITY_FIELD => 28,
};

my $browser = LWP::UserAgent->new();
$browser->cookie_jar( {} );

####################################################################
# new: Object constructor for ECDefectTracking::ALM::Driver
#  
# Side Effects:
#   
# Arguments:
#   cmdr -            previously initialized ElectricCommander handle
#   name -            name of this configuration
#
# Returns:
#   Nothing
#
####################################################################
sub new {
    my $this = shift;
    my $class = ref($this) || $this;

    my $cmdr = shift;
    my $name = shift;

    my $cfg = new ECDefectTracking::ALM::Cfg($cmdr, "$name");
    if ("$name" ne "") {
        my $sys = $cfg->getDefectTrackingPluginName();
        if ("$sys" ne PLUGIN_NAME) { die "DefectTracking config $name is not type ECDefectTracking-ALM"; }
    }

    my ($self) = new ECDefectTracking::Base::Driver($cmdr,$cfg);

    bless ($self, $class);
    return $self;
}

####################################################################
# isImplemented
#  
# Side Effects:
#   
# Arguments:
#   self -              the object reference
#   method -            method name
#
# Returns:
#   Nothing
#
####################################################################
sub isImplemented {
    my ($self, $method) = @_;
    
    if ($method eq METHOD_LINK_DEFECTS || 
        $method eq METHOD_UPDATE_DEFECTS ||
        $method eq METHOD_FILE_DEFECTS ||
        $method eq METHOD_CREATE_DEFECTS) {
        return SUCCESS;
    } else {
        return ERROR;
    }
}

####################################################################
# getALMInstance
#
# Side Effects:
#   
# Arguments:
#   self -              the object reference
#
# Returns:
#   request - A string with the request for REST queries
#   server
#   domain
#   project
####################################################################
sub getALMInstance{
    my ($self) = @_;
    
    my $cfg 				= $self->getCfg();    
    my $credentialName 		= $cfg->getCredential();
    my $credentialLocation 	= q{/projects/$[/plugins/EC-DefectTracking/project]/credentials/}.$credentialName;

    my ($success, $xPath, $msg) = $self->InvokeCommander({SupressLog=>1,IgnoreError=>1}, "getFullCredential", $credentialLocation);
    if (!$success) {
        print "\nError getting credential\n";        
        return;
    }

    my $user 	= $xPath->findvalue('//userName')->value();
    my $passwd 	= $xPath->findvalue('//password')->value();

    if (!$user || !$passwd) {
		print "User name and or password in credential $credentialLocation is not set\n";
		return;
    }

    my $server 	= $cfg->get('url');
    my $domain 	= $cfg->get('domain');
    my $project = $cfg->get('project');
    
    if (!$server || !$domain || !$project) {
        print "The information on configuration is incomplete\n";
        return;
    }
    
    #my $browser = LWP::UserAgent->new();
	#$browser->cookie_jar( {} );
	
	my $request = HTTP::Request->new(GET => $server."/authentication-point/authenticate");
	$request->authorization_basic("$user", "$passwd");
	print "request:\n ".$request->as_string . "\n";
	my $response = $browser->request($request);
	print "browser-request response:\n ".$response->as_string . "\n";
	# -- stop if there's a connection error
	die "\nError:\n\t" . $response->status_line . "\n" unless $response->is_success;

	# Create a session - should return '200' and give us a QCSESSION cookie
	print "Create a session - should return '200' and give us a QCSESSION cookie\n";
	my $request = HTTP::Request->new(POST => $server."/rest/site-session");
	print "request:\n ".$request->as_string . "\n";
	my $response = $browser->request($request);
	print "browser-request response:\n ".$response->as_string . "\n";
	# -- stop if there's a connection error
	die "\nError:\n\t" . $response->status_line . "\n" unless $response->is_success;

    return ($request, $server, $domain, $project);
}

####################################################################
# getUser
#
# Side Effects:
#   
# Arguments:
#   self -              the object reference
#
# Returns:
#   userName
####################################################################
sub getUser{
    my ($self) = @_;
    
    my $cfg 				= $self->getCfg();    
    my $credentialName 		= $cfg->getCredential();
    my $credentialLocation 	= q{/projects/$[/plugins/EC-DefectTracking/project]/credentials/}.$credentialName;

    my ($success, $xPath, $msg) = $self->InvokeCommander({SupressLog=>1,IgnoreError=>1}, "getFullCredential", $credentialLocation);
    if (!$success) {
        print "\nError getting credential\n";        
        return;
    }

    my $user 	= $xPath->findvalue('//userName')->value();
    my $passwd 	= $xPath->findvalue('//password')->value();

    if (!$user || !$passwd) {
		print "User name and or password in credential $credentialLocation is not set\n";
		return;
    }else{
		return $user;
	}
}

####################################################################
# linkDefects
#  
# Side Effects:
#   
# Arguments:
#   self -              the object reference
#   opts -              hash of options
#
# Returns:
#   Nothing
#
####################################################################
sub linkDefects {
    my ($self, $opts) = @_;
    
    # get back a hash ref
    my $defectIDs_ref 	= $self->extractDefectIDsFromProperty($opts->{propertyToParse}, $opts->{prefix});
    my $prefix 			= $opts->{prefix};
    print "Prefix: $prefix\n";

    if (! keys % {$defectIDs_ref}) {
        print "No defect IDs found, returning\n";
        return;
    }         

    $self->populatePropertySheetWithDefectIDs($defectIDs_ref);

    my $defectLinks_ref = {}; # ref to empty hash
    
    my $numb;
    
    @$numb = keys %$defectIDs_ref;
    s/$prefix// foreach @$numb;
    
    my ($request, $server, $domain, $project) = $self->getALMInstance();
    
    foreach my $e (@$numb){
        print "Defect ID: $e \n";
        my ($name, $url) = $self->queryALMWithDefectID($e, $request, $server, $domain, $project);
        
        print "Key: $e Name: $name\n";        
        if ($name && $name ne "" && $url && $url ne "") {
            $defectLinks_ref->{$name} = $url; 
        }
    }

    if (keys % {$defectLinks_ref}) {
        $self->populatePropertySheetWithDefectLinks($defectLinks_ref);
        $self->createLinkToDefectReport(REPORT_NAME);
    }
}

####################################################################
# queryALMWithDefectID
#
# Side Effects:
#   
# Arguments:
#   self     - 
#   defectID - 
#   request  - 
#   server   - 
#   domain   - 
#   project  - 
#
# Returns:
#   A tuple: (<name of url> , <url pointing to a defect id>)
####################################################################
sub queryALMWithDefectID {

    my ($self, $defectID, $request, $server, $domain, $project) = @_;
	
	my $url = "$server/rest/domains/$domain/projects/$project/defects/$defectID";
	$request = HTTP::Request->new(GET => $url);	
	print "\nResquest: $request";
	
	my $response = $browser->request($request);
	print "\nResponse: $response";
	
	my $responseXML = XMLin($response->content);

	if(!$response->is_success){
		print "\nError:\n\t" . $responseXML->{'Title'} . "\n";	
		return;
	}
	
	print "\nDumper: " . Dumper($responseXML);
	
	my $defectName = $responseXML->{'Fields'}->{'Field'}->[NAME_FIELD]->{'Value'};
	my $defectStatus = $responseXML->{'Fields'}->{'Field'}->[STATUS_FIELD]->{'Value'};
	my $defectSeverity = $responseXML->{'Fields'}->{'Field'}->[SEVERITY_FIELD]->{'Value'};
	
	my $name = "Defect $defectID: $defectName";
	my $url  = '#';
	
	if(ref($defectStatus) ne "HASH"){
		$name = $name . ", Status: $defectStatus";
	}
	if(ref($defectSeverity) ne "HASH"){
		$name = $name . ", Severity: $defectSeverity";
	}	   
    
    return ($name, $url);
}

####################################################################
# updateDefects
#  
# Side Effects:
#   
# Arguments:
#   self -              the object reference
#   opts -              hash of options
#
# Returns:
#   Nothing
#
####################################################################
sub updateDefects {
    my ($self, $opts) = @_;
    # Attempt to read the property "/myJob/defectsToUpdate" 
    # or the property entered as the "property" parameter to the subprocedure   
    my $property = $opts->{property};    
    if (!$property || $property eq "") {
                print "Error: Property does not exist or is empty\n";
                exit 1;
    }
    my ($success, $xpath, $msg) = $self->InvokeCommander({SupressLog=>1,IgnoreError=>1}, "getProperty", "$property");
        if ($success) {
            my $value = $xpath->findvalue('//value')->string_value;
            $property = $value;
        } else {
            # log the error code and msg
            print "Error querying for $property as a property\n";
            exit 1;
        }
    # split using ',' to get a list of key=value pairs
    print "Property : $property\n";
    my @pairs = split(',', $property);
    
    my $errors;
    my $updateddefectLinks_ref = {}; # ref to empty hash
    
    my ($request, $server, $domain, $project) = $self->getALMInstance();
    
    foreach my $val (@pairs) {
        print "Current Pair: $val\n";
        my @iDAndValue = split('=', $val);
        # the key of each pair is the defect ID, 
        # e.g. "11111" is the first key in the example above
        my $idDefect = $iDAndValue[0];
        # the value of each pair is the status,
        # e.g. "Resolved", is the first value in the example above
        my $valueDefect = $iDAndValue[1]; 
        #Validate $idDefect $valueDefect
        print "Current idDefect: $idDefect\n";
        print "Current valueDefect: $valueDefect\n";
        if (!$idDefect || $idDefect eq "" || !$valueDefect || $valueDefect eq "" ) {
            print "Error: Property format error\n";
        }else{
            # Call function to resolve Defect               
            my $message = "";
            eval{
				my $xmlOut = 
					"<Entity Type=\"defect\">
						<Fields>
							<Field Name=\"status\">
								<Value>$valueDefect</Value>
							</Field>
						</Fields>
					</Entity>";			
			
				my $url = "$server/rest/domains/$domain/projects/$project/defects/$idDefect";
				my $putRequest = HTTP::Request->new(PUT => $url);
				$putRequest->content($xmlOut);
				$putRequest->content_type("application/xml");
				my $response = $browser->request($putRequest);
				# -- stop if there's a connection error
				my $responseXML = XMLin($response->content);
				if(!$response->is_success){
					$message = "Defect: $idDefect Error:" . $responseXML->{'Title'};						
					$updateddefectLinks_ref->{$message} = '#';
					$errors = 1;
					print "$message \n";
				}else{
					$message = "Defect: $idDefect was successfully updated to $valueDefect status\n";
					$updateddefectLinks_ref->{$message} = '#';
					print "$message \n";
				}                                                
            };
            if ($@) {
                $message = "Error: failed trying to udpate $idDefect to $valueDefect status, with error: $@ \n";
                print "$message \n";
                $errors = 1;
            };
        }        
    }
    
    if (keys % {$updateddefectLinks_ref}) {
        my $propertyName_ref = "updatedDefectLinks"; 
        $self->populatePropertySheetWithDefectLinks($updateddefectLinks_ref, $propertyName_ref);
        $self->createLinkToDefectReport(REPORT_NAME);
    }
    if($errors && $errors ne ""){
        print "Defects update completed with some Errors\n";
                my ($success, $xpath, $msg) = $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1},
                 "setProperty", '/myJobStep/outcome', 'error');
    }
}

####################################################################
# createDefects
#  
# Side Effects:
#   
# Arguments:
#   self -              the object reference
#   opts -              hash of options
#
# Returns:
#   Nothing
#
####################################################################
sub createDefects {
    my ($self, $opts) = @_;
    
    my ($success, $xpath, $msg) = $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1},
                     "setProperty", "/myJob/config", "$opts->{config}");
         
    my $mode = $opts->{mode};    
    if (!$mode || $mode eq "") {
        print "Error: mode does not exist or is empty\n";
        exit 1;
    }
    
    ($success, $xpath, $msg) = $self->InvokeCommander({SupressLog=>1,IgnoreError=>1}, "getProperties", {recurse => "0", path => "/myJob/ecTestFailures"});
    if (!$success) {
        print "No Errors, so no Defects to create\n";
        return 0;       
    }    
    
    my $results = $xpath->find('//property');    
    if (!$results->isa('XML::XPath::NodeSet')) {
        #didn't get a nodeset
        print "Didn't get a NodeSet when querying for property: ecTestFailures \n";
        return 0;   
    }

    my @propsNames = ();
    
    foreach my $context ($results->get_nodelist) {
            my $propertyName = $xpath->find('./propertyName', $context);
            push(@propsNames,$propertyName);    
    }
    
    my $createdDefectLinks_ref = {}; # ref to empty hash
    my $errors;
    
    my ($request, $server, $domain, $project) = $self->getALMInstance();
    
    foreach my $prop (@propsNames) {
        print "Trying to get Property /myJob/ecTestFailures/$prop \n";
        my ($jSuccess, $jXpath, $jMsg) = $self->InvokeCommander({SupressLog=>1,IgnoreError=>1}, "getProperties", {recurse => "0", path => "/myJob/ecTestFailures/$prop"});
        
        my %testFailureProps = {}; # ref to empty hash
        
        ##Properties##
        #stepID
        my $stepID = "N/A";             
        #testSuiteName
        my $testSuiteName = "N/A";
        #testCaseResult
        my $testCaseResult = "N/A";
        #testCaseName
        my $testCaseName = "N/A";
        #logs
        my $logs = "N/A";
        #stepName
        my $stepName = "N/A";
        
        my $jResults = $jXpath->find('//property');
        foreach my $jContext ($jResults->get_nodelist) {                        
            my $subPropertyName = $jXpath->find('./propertyName', $jContext)->string_value;
            my $value = $jXpath->find('./value', $jContext)->string_value;
            
            if ($subPropertyName eq 'stepId'){$stepID = $value;}                    
            if ($subPropertyName eq 'testSuiteName'){$testSuiteName = $value;}
            if ($subPropertyName eq 'testCaseResult'){$testCaseResult = $value;}
            if ($subPropertyName eq 'testCaseName'){$testCaseName = $value;}
            if ($subPropertyName eq 'logs'){$logs = $value;}
            if ($subPropertyName eq 'stepName'){$stepName = $value;}                                
        }
        
        my $message = "";               
        my $comment = "Step ID: $stepID "
                    . "Step Name: $stepName "
                    . "Test Case Name: $testCaseName ";
                                        
        if($mode eq "automatic"){
            eval{
				my $DETECTED_BY_FIELD = $self->getUser();
				my $CREATION_TIME_FIELD = strftime('%Y-%m-%d',localtime);
				my $SEVERITY_FIELD = "2-Medium";
				my $NAME_FIELD = "Error: Step ID $stepID";
				my $DESCRIPTION_FIELD = $comment;
				my $STATUS_FIELD = "New";
				my $ID_FIELD = 7;
				
				my $xmlOut = 
					"<Entity Type=\"defect\">
					<Fields>
						 <Field Name=\"detected-by\">
							  <Value>$DETECTED_BY_FIELD</Value>
						 </Field>
						 <Field Name=\"creation-time\">
							  <Value>$CREATION_TIME_FIELD</Value>
						 </Field>
						 <Field Name=\"severity\">
							  <Value>$SEVERITY_FIELD</Value>
						 </Field>
						 <Field Name=\"name\">
							  <Value>$NAME_FIELD</Value>
						 </Field>
						 <Field Name=\"status\">
							  <Value>$STATUS_FIELD</Value>
						 </Field>
						 <Field Name=\"description\">
							  <Value>$DESCRIPTION_FIELD</Value>
						 </Field>
					</Fields>
					</Entity>";
					
				my $url = "$server/rest/domains/$domain/projects/$project/defects";
				my $postRequest = HTTP::Request->new(POST => $url);
				$postRequest->content($xmlOut);
				$postRequest->content_type("application/xml");
				my $response = $browser->request($postRequest);
				my $responseXML = XMLin($response->content);
				
				if(!$response->is_success){					
					$message = "Error: " . $responseXML->{'Title'};	
					print "$message \n";
					$createdDefectLinks_ref->{"$comment"} = "$message?prop=$prop";#?prop=Step29721-testBlockUnblock
					$errors = 1;
				}else{
					#GET ID FROM NEW DEFECT
					my $responseXML = XMLin($response->content);					
					my $defectID = $responseXML->{'Fields'}->{'Field'}->[$ID_FIELD]->{'Value'};
					$message = "Issue Created with ID: ". $defectID;
					print "$message \n";
					my $defectUrl = "#";
					$createdDefectLinks_ref->{"$comment"} = "$message?url=$defectUrl"; #ie: ?url=http://www.google.com/ig					
				}                            
            };
            if ($@) {
                    $message = "Error: failed trying to create issue, with error: $@ \n";
                    print "$message";
                    $errors = 1;                            
            };
        }else{#$mode eq "manual"
            $createdDefectLinks_ref->{"$comment"} = "Needs to File Defect?prop=$prop";#?prop=Step29721-testBlockUnblock
        }
    }#end foreach my $prop (@propsNames)    
    
    if (keys % {$createdDefectLinks_ref}) {
        my $propertyName_ref = "createdDefectLinks"; 
        $self->populatePropertySheetWithDefectLinks($createdDefectLinks_ref, $propertyName_ref);
        $self->createLinkToDefectReport(REPORT_NAME);
    }    
    if($errors && $errors ne ""){
        print "Created Defects completed with some Errors\n";
                my ($success, $xpath, $msg) = $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1},
                 "setProperty", '/myJobStep/outcome', 'error');
    }
}

####################################################################
# fileDefect
#  
# Side Effects:
#   
# Arguments:
#   self -              the object reference
#   opts -              hash of options
#
# Returns:
#   Nothing
#
####################################################################
sub fileDefect {
    my ($self, $opts) = @_;
    
    my $prop = $opts->{prop};    
    if (!$prop || $prop eq "") {
                print "Error: prop does not exist or is empty\n";
                exit 1;
    }
    
    my $jobIdParam = $opts->{jobIdParam};    
    if (!$jobIdParam || $jobIdParam eq "") {
                print "Error: jobIdParam does not exist or is empty\n";
                exit 1;
    }    
       
    print "Trying to get Property /$jobIdParam/ecTestFailures/$prop \n";    
    my ($jSuccess, $jXpath, $jMsg) = $self->InvokeCommander({SupressLog=>1,IgnoreError=>1}, "getProperties", {recurse => "0", jobId => "$jobIdParam", path => "/myJob/ecTestFailures/$prop"});
            
    ##Properties##
    #stepID
    my $stepID = 'N/A';             
    #testSuiteName
    my $testSuiteName = 'N/A';
    #testCaseResult
    my $testCaseResult = 'N/A';
    #testCaseName
    my $testCaseName = 'N/A';
    #logs
    my $logs = 'N/A';
    #stepName
    my $stepName = 'N/A';
    
    my $jResults = $jXpath->find('//property');
    foreach my $jContext ($jResults->get_nodelist) {                        
        my $subPropertyName = $jXpath->find('./propertyName', $jContext)->string_value;
        my $value = $jXpath->find('./value', $jContext)->string_value;
        
        if ($subPropertyName eq 'stepId'){$stepID = $value;}                    
        if ($subPropertyName eq 'testSuiteName'){$testSuiteName = $value;}
        if ($subPropertyName eq 'testCaseResult'){$testCaseResult = $value;}
        if ($subPropertyName eq 'testCaseName'){$testCaseName = $value;}
        if ($subPropertyName eq 'logs'){$logs = $value;}
        if ($subPropertyName eq 'stepName'){$stepName = $value;}                        
    }
    
    my $message = "";               
    my $comment = "Step ID: $stepID "
                . "Step Name: $stepName "
                . "Test Case Name: $testCaseName ";
                
    my ($request, $server, $domain, $project) = $self->getALMInstance();
	
	eval{
		my $DETECTED_BY_FIELD = $self->getUser();
		my $CREATION_TIME_FIELD = strftime('%Y-%m-%d',localtime);
		my $SEVERITY_FIELD = "2-Medium";
		my $NAME_FIELD = "Error: Step ID $stepID";
		my $DESCRIPTION_FIELD = $comment;
		my $STATUS_FIELD = "New";
		my $ID_FIELD = 7;
		
		my $xmlOut = 
			"<Entity Type=\"defect\">
			<Fields>
				 <Field Name=\"detected-by\">
					  <Value>$DETECTED_BY_FIELD</Value>
				 </Field>
				 <Field Name=\"creation-time\">
					  <Value>$CREATION_TIME_FIELD</Value>
				 </Field>
				 <Field Name=\"severity\">
					  <Value>$SEVERITY_FIELD</Value>
				 </Field>
				 <Field Name=\"name\">
					  <Value>$NAME_FIELD</Value>
				 </Field>
				 <Field Name=\"status\">
					  <Value>$STATUS_FIELD</Value>
				 </Field>
				 <Field Name=\"description\">
					  <Value>$DESCRIPTION_FIELD</Value>
				 </Field>
			</Fields>
			</Entity>";
			
		my $url = "$server/rest/domains/$domain/projects/$project/defects";
		my $postRequest = HTTP::Request->new(POST => $url);
		$postRequest->content($xmlOut);
		$postRequest->content_type("application/xml");
		my $response = $browser->request($postRequest);
		my $responseXML = XMLin($response->content);
		
		if(!$response->is_success){					
			$message = "Error: " . $responseXML->{'Title'};	
			print "$message \n";
			print "setProperty name: /$jobIdParam/createdDefectLinks/$comment value:$message?prop=$prop \n";
			my ($success, $xpath, $msg) = $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1},
             "setProperty", "/myJob/createdDefectLinks/$comment", "$message?prop=$prop", {jobId => "$jobIdParam"});			
		}else{
			#GET ID FROM NEW DEFECT
			my $responseXML = XMLin($response->content);					
			my $defectID = $responseXML->{'Fields'}->{'Field'}->[$ID_FIELD]->{'Value'};
			$message = "Issue Created with ID: ". $defectID;
			print "$message \n";
			my $defectUrl = "#";
			my ($success, $xpath, $msg) = $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1},
             "setProperty", "/myJob/ecTestFailures/$prop/defectId", "$defectID", {jobId => "$jobIdParam"});
            ($success, $xpath, $msg) = $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1},
             "setProperty", "/myJob/createdDefectLinks/$comment", "$message?url=$defectUrl", {jobId => "$jobIdParam"});
		}                            
	};
    if ($@) {
        $message = "Error: failed trying to create issue (EVAL), with error: $@ \n";
        print "$message \n";
        print "setProperty name: /$jobIdParam/createdDefectLinks/$comment value:$message?prop=$prop \n";
        my ($success, $xpath, $msg) = $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1},
             "setProperty", "/myJob/createdDefectLinks/$comment", "$message?prop=$prop", {jobId => "$jobIdParam"});
    };
}

####################################################################
# addConfigItems
# 
# Side Effects:
#   
# Arguments:
#   self -              the object reference
#   opts -              hash of options   
#
# Returns:
#   nothing
####################################################################
sub addConfigItems{
    my ($self, $opts) = @_;

    $opts->{'linkDefects_label'} = REPORT_NAME;
    $opts->{'linkDefects_description'} = 'Generates a report of ALM IDs found in the build.';
}

1;
