#####################################################################################
# Tomcat Auto-installation Script 													#
# Author: Kevin YOUNG																#
# Since: 2015-05-24																	#
# License: MIT 																		#
#####################################################################################

#!/usr/bin/perl
use strict;
use warnings;

use File::Fetch;
use Cwd;
use File::Basename;
use Archive::Extract;

use constant CONF_FILE => "tomcat.properties";
use constant TOMCAT_STARTUP_SCRIPT => "tomcat";

my $TOMCAT_URI = "tomcat.uri";
my $TOMCAT_INSTALL_DIR = "tomcat.install.dir";
my $TOMCAT_PORT = "tomcat.port";
my $TOMCAT_LOGPATH = "tomcat.logpath";
my $TOMCAT_RUN_USER = "tomcat.run.user";
my $TOMCAT_RUN_GROUP = "tomcat.run.group";
my $TOMCAT_JAVA_HOME = "tomcat.java.home";

#####################################################################################
#								Dowload tomcat archive								#
#####################################################################################

&check_root;

printf "Loading configuration file `%s`...\n", CONF_FILE;
my %conf = &load_conf_file(CONF_FILE);
printf "\n%s %s %s\n", "-" x 10, "configuration Start" ,"-" x 10;
&print_conf_file(%conf);
printf "%s %s %s\n", "-" x 10, "configuration End  " ,"-" x 10;

my $cwd = getcwd;
my $filename = basename($conf{$TOMCAT_URI});
my $tomcat_archive = "$cwd/$filename";

&download_tomcat_archive($tomcat_archive, $conf{$TOMCAT_URI});
my $tomcat_path = &extract_tomcat_archive($tomcat_archive);
my @tomcat_dirs = split /\//, $tomcat_path;

#####################################################################################
#								Install Tomcat 										#
#####################################################################################


my $user = $conf{$TOMCAT_RUN_USER};
my $group = $conf{$TOMCAT_RUN_GROUP};
my $install_dir = $conf{$TOMCAT_INSTALL_DIR} . "/" . $tomcat_dirs[$#tomcat_dirs];
my $tomcat_log_dir = $conf{$TOMCAT_LOGPATH};
my $log_conf_file = "$tomcat_path/conf/logging.properties";
my $port = $conf{$TOMCAT_PORT};
my $tomcat_conf_file = "$tomcat_path/conf/server.xml";
my $java_home = $conf{$TOMCAT_JAVA_HOME};

&create_group($group);
&create_user($user);
&change_log_location($log_conf_file, $tomcat_log_dir);
&config_tomcat_port($tomcat_conf_file, $port);
&install_tomcat;
&install_tomcat_startup_script(TOMCAT_STARTUP_SCRIPT, $java_home, $tomcat_path);

#####################################################################################
#								Sub routines 										#
#####################################################################################
sub change_log_location {
	my ($log_conf_file, $tomcat_log_dir) = @_;
	my $text = read_all($log_conf_file);
	$text =~ s/\${catalina\.base}\/logs/$tomcat_log_dir/g;
	write_to_file($log_conf_file, $text);
}

sub read_all {
	my($filename) = @_;
	open my $in, '<', $filename 
		or die "Could not open file `$filename`: $!\n";
	local $/ = undef;
	my $text = <$in>;
	close $in;
	return $text;
}

sub write_to_file {
	my($filename, $text) = @_;
	open my $out, '>', $filename 
		or die "Could not open file `$filename` to write: $!\n";
	print $out $text;
	close $out;
}

sub create_group {
	my($group) = @_;
	my $gid = getgrnam($group);
	if(!defined($gid) || !($gid > 0)) {
		printf "Creating group `%s`...\n", $group;
		system "groupadd $group";
		print "Done.\n";
	}
}

sub create_user {
	my($user) = @_;
	my $uid = getpwnam($user);
	if(!defined($uid) || !($uid > 0)) { #Create user
		printf "Creating user `%s`...\n", $user;
		system "useradd -r -g $group $user";
		print "Done.\n";
	}
}

sub install_tomcat {
	my($login, $pass, $uid, $gid) = getpwnam($user) or die "$user not in passwd file.\n";
	printf "chown `%s` to `%s:%s`\n", $tomcat_path, $user, $group;
	chown $uid, $gid, $tomcat_path;
	# TODO: print out a warning if $install_dir/ exists
	printf "Moving `%s` to `%s`\n", $tomcat_path, $install_dir;
	system "mv $tomcat_path $install_dir";

	mkdir $tomcat_log_dir;
	chown $uid, $gid, $tomcat_log_dir;
}

sub extract_tomcat_archive {
	my($filename) = @_;
	my $ae = Archive::Extract->new(archive => $filename);
	print "Begin to extract `$filename`...\n";
	$ae->extract or die $ae->error;
	my $tomcat_path = $ae->extract_path;
	print "Completed: " , $tomcat_path, "\n";
	return $tomcat_path;
}

sub download_tomcat_archive{
	my($filename, $uri) = @_;
	if( ! -e  $filename) {
		print "`$filename` doesn't exist, begin downloading from: $uri\n";
		my $file = File::Fetch->new(uri => $uri);
		$file->fetch() or die $file->error;
		print "Completed: $filename\n";
	}
}

sub check_root {
	my $root_uid = (getpwuid $>);
		die "ERROR: You need `root` user to run this script." if $root_uid ne 'root';
}

sub load_conf_file {
	my($conf_file) = @_;
	my %conf;
	my $fd;
	open $fd, $conf_file or die "Could not open file `$conf_file`: $!\n";
	while(my $line = <$fd>) {
		chomp($line);
		if($line !~ /^\s/) { # not blank
			my($key, $value) = split /=/, $line;
			$conf{$key} = $value;
		}
	}
	close $fd;	
	return %conf;
}

sub print_conf_file {
	my(%conf) = @_;
	while (my($key, $value) = each %conf) {
			print "$key => $value\n";
	}
}

sub config_tomcat_port {
	my($conf_file, $port) = @_;
	my $text = read_all($conf_file);
	$text =~ s/8080/$port/g;
	write_to_file($log_conf_file, $text);
}

sub install_tomcat_startup_script {
	my($script, $java_home, $catalina_home) = @_;
	my $text = read_all($script);
	$text =~ s/\${JAVA_HOME}/$java_home/g;
	$text =~ s/\${CATALANA_HOME}/$catalina_home/g;
	write_to_file($script, $text);

	my $startup_script_location = "/etc/init.d/tomcat";
	printf "Installing tomcat startup script `%s`\n", $startup_script_location;
	system "mv $script $startup_script_location";
	system "chkconfig tomcat on";
}
