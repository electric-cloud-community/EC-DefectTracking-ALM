@files = (
    ['//property[propertyName="ECDefectTracking::ALM::Cfg"]/value', 'ALMCfg.pm'],
    ['//property[propertyName="ECDefectTracking::ALM::Driver"]/value', 'ALMDriver.pm'],
    ['//property[propertyName="createConfig"]/value', 'almCreateConfigForm.xml'],
    ['//property[propertyName="editConfig"]/value', 'almEditConfigForm.xml'],
    ['//property[propertyName="ec_setup"]/value', 'ec_setup.pl'],
	['//procedure[procedureName="LinkDefects"]/propertySheet/property[propertyName="ec_parameterForm"]/value', 'ec_parameterForm-LinkDefects.xml'],	
	['//procedure[procedureName="UpdateDefects"]/propertySheet/property[propertyName="ec_parameterForm"]/value', 'ec_parameterForm-UpdateDefects.xml'],	
	['//procedure[procedureName="CreateDefects"]/propertySheet/property[propertyName="ec_parameterForm"]/value', 'ec_parameterForm-CreateDefects.xml'],	
);
