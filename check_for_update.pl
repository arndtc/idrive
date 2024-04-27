#!/usr/bin/env perl
#*****************************************************************************************************
# This script is used to check update is available or not and manual update
#
# Created By: Sabin Cheruvattil @ IDrive Inc
#****************************************************************************************************/

use strict;
use warnings;

use lib map{if(__FILE__ =~ /\//) { substr(__FILE__, 0, rindex(__FILE__, '/'))."/$_";} else { "./$_"; }} qw(Idrivelib/lib);

use Common;
use AppConfig;
use File::Basename;

eval {
	require File::Copy;
	File::Copy->import();
};

use Scalar::Util qw(reftype);
use JSON;

init();

#*****************************************************************************************************
# Subroutine			: init
# Objective				: This function is entry point for the script
# Added By				: Sabin Cheruvattil
# Modified By			: Yogesh Kumar, Senthil Pandian
#****************************************************************************************************/
sub init {
	my ($packageName, $updateAvailable, $taskParam, $targetuser, $updtype) =  ('', 0, $ARGV[0], $ARGV[1], $ARGV[2]);

	$taskParam = '' unless (defined($taskParam));
	$updtype = '' unless (defined($updtype));
	$targetuser = '' unless (defined($targetuser));

	my $silent = ($taskParam and ($taskParam eq 'silent'))? 'silent' : '';

	if ($taskParam eq 'silent') {
		$AppConfig::callerEnv = 'BACKGROUND';
	}

	Common::loadAppPath();
	Common::loadServicePath();
	Common::loadUsername();
	Common::loadUserConfiguration();
	checkWritePermission();

	if ($taskParam eq 'checkUpdate') {
		$updateAvailable = checkForUpdate();
		updateVersionInfoFile() if ($updateAvailable);
		exit(0);
	}

	Common::findDependencies(0) or Common::retreat('failed');

	if ($taskParam eq '') {
		system('clear');
		Common::displayHeader();
		checkAndCreateServiceDirectory();

        # Fetching & verifying OS & build version
        Common::getOSBuild(1);

		my $usrProfileDirPath	= Common::getCatfile(Common::getServicePath(), $AppConfig::userProfilePath);
		if(-d $usrProfileDirPath) {
			Common::display(['updating_script_will_logout_users', 'do_you_want_to_continue_yn']);
			Common::cleanupUpdate() if (Common::getAndValidate('enter_your_choice', 'YN_choice', 1) eq 'n');
		}

		Common::askProxyDetails() unless (Common::getProxyDetails('PROXYIP'));
		Common::display(["\n",'checking_for_updates', '...']);

		$packageName = qq(/$AppConfig::tmpPath/$AppConfig::appPackageName$AppConfig::appPackageExt);
		$updateAvailable = checkForUpdate();

		unless ($updateAvailable) {
			Common::display(['no_updates_but_still_want_to_update']);
			if (Common::getAndValidate('enter_your_choice', 'YN_choice', 1) eq 'n') {
				Common::retreat([$AppConfig::appType, ' ', 'is_upto_date']);
			}
		} else {
			Common::cleanupUpdate('INIT');
			Common::display(['new_updates_available_want_update']);
			Common::cleanupUpdate() if (Common::getAndValidate('enter_your_choice', 'YN_choice', 1) eq 'n');
			Common::display(['updating_scripts_wait', '...']);
		}

		$updtype = 'checkupdate';
	}
	elsif ($taskParam eq 'silent') {
		if($updtype eq "dashboard") {
			# $updtype = 'force';
			# Disable update related task which is in user mode | Lock file removal disables the scheduler job
			unlink($AppConfig::silupdtlock);
		}

		$AppConfig::callerEnv = 'BACKGROUND';
		checkAndCreateServiceDirectory();
		$packageName = qq(/$AppConfig::tmpPath/$AppConfig::appPackageName$AppConfig::appPackageExt);
		Common::cleanupUpdate('INIT');
	}
	else{
		Common::retreat(['invalid_parameter', ': ', $taskParam, '. ', 'please_try_again', '.']);
	}

	if (Common::download($AppConfig::packageUpdaterURL)) {
		my $upddwnpl = Common::getCatfile(Common::getServicePath(), $AppConfig::downloadsPath, $AppConfig::packageUpdaterZip);
		Common::unzip($upddwnpl, Common::getAppPath());

		my $updatepl = Common::getCatfile(Common::getAppPath(), $AppConfig::packageUpdater);
		chmod($AppConfig::execPermission, $updatepl);

		# $silent = 'silent'; # all the request from check for update goes in silent mode
		system("$AppConfig::perlBin $updatepl '$silent' '$targetuser' '$updtype'");
		unlink($updatepl);
	}
	else {
		Common::traceLog("Update download failed!");
	}

	Common::rmtree(Common::getCatfile(Common::getServicePath(), $AppConfig::downloadsPath));
}

#*************************************************************************************************
# Subroutine		: checkForUpdate
# Objective			: check if version update exists for the product
# Added By			: Sabin Cheruvattil
# Modified By		: Yogesh Kumar
#*************************************************************************************************/
sub checkForUpdate {
	my $cgiResult = Common::makeRequest(4, [
		($AppConfig::appType . "ForLinux"),
		$AppConfig::trimmedVersion
	]);

	return 0 unless (ref($cgiResult) eq 'HASH');
	chomp($cgiResult->{AppConfig::DATA});
	return 1 if ($cgiResult->{AppConfig::DATA} eq 'Y');
	return 0 if ($cgiResult->{AppConfig::DATA} eq 'N');

	Common::cleanupUpdate(['kindly_verify_ur_proxy']) if ($cgiResult->{AppConfig::DATA} =~ /.*<h1>Unauthorized \.{3,3}<\/h1>.*/);
	my $pingCmd = Common::updateLocaleCmd('ping -c2 8.8.8.8');
	my $pingRes = `$pingCmd`;
	Common::cleanupUpdate([$pingRes]) if ($pingRes =~ /connect\: Network is unreachable/);
	Common::cleanupUpdate(['please_check_internet_con_and_try']) if ($pingRes !~ /0\% packet loss/);
	Common::cleanupUpdate(['kindly_verify_ur_proxy']) if ($cgiResult->{AppConfig::DATA} eq '');
}

#*************************************************************************************************
# Subroutine		: updateVersionInfoFile
# Objective			: update version infomation file
# Added By			: Sabin Cheruvattil
#*************************************************************************************************/
sub updateVersionInfoFile {
	my $versionInfoFile = Common::getUpdateVersionInfoFile();
	open (VN,'>', $versionInfoFile);
	print VN $AppConfig::version;
	close VN;
	chmod $AppConfig::filePermission, $versionInfoFile;
}

#*************************************************************************************************
# Subroutine		: checkAndCreateServiceDirectory
# Objective			: check and create service directory if not present
# Added By			: Senthil Pandian
# Modified By		: Yogesh Kumar, Sabin Cheruvattil
#*************************************************************************************************/
sub checkAndCreateServiceDirectory {
	unless (Common::loadServicePath()) {
		unless (Common::checkAndUpdateServicePath()) {
			Common::createServiceDirectory();
		}
	}

	Common::createDir(Common::getCachedDir(),1) unless(-d Common::getCachedDir());
}

#*************************************************************************************************
# Subroutine		: checkWritePermission
# Objective			: check write permission of scripts
# Added By			: Senthil Pandian
# Modified By		: Yogesh Kumar, Sabin Cheruvattil
#*************************************************************************************************/
sub checkWritePermission {
	my $scriptDir = Common::getAppPath();
	my $noPerm = 0;
	if (!-w $scriptDir){
		Common::retreat(['system_user', " '$AppConfig::mcUser' ", 'does_not_have_sufficient_permissions', ' ', 'please_run_this_script_in_privileged_user_mode','update.']);
	}

	opendir(my $dh, $scriptDir);
	foreach my $script (readdir($dh)) {
		next if ($script eq '.' or $script eq '..');
		next if (-f $script and $script !~ /.pl|.pm/ and $script ne 'readme.txt');
		if (!-w Common::getCatfile($scriptDir, $script)) {
			Common::retreat(['system_user', " '$AppConfig::mcUser' ", 'does_not_have_sufficient_permissions',' ','please_run_this_script_in_privileged_user_mode','update.']);
		}
	}
	closedir $dh;
}
