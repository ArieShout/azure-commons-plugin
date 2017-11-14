#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

package main;

use FindBin qw($Bin);
use lib "$Bin/lib";
use Getopt::Long qw(:config gnu_getopt no_ignore_case auto_version auto_help);
use Helpers qw(:log :shell throw_if_empty random_string process_file);
use SSHClient;
use JenkinsCli;
use File::Spec;
use File::Basename;
use File::Find;
use File::Path qw(make_path);

use Data::Dumper;

our $VERSION = 0.1.0;

our %options = (
    verbose => 1,
    subscriptionId => $ENV{AZURE_SUBSCRIPTION_ID},
    clientId => $ENV{AZURE_CLIENT_ID},
    clientSecret => $ENV{AZURE_CLIENT_SECRET},
    tenantId => $ENV{AZURE_TENANT_ID},
    adminUser => 'azureuser',
    publicKeyFile => File::Spec->catfile($ENV{HOME}, '.ssh', 'id_rsa.pub'),
    privateKeyFile => File::Spec->catfile($ENV{HOME}, '.ssh', 'id_rsa')
);

GetOptions(\%options,
    'subscriptionId|s=s',
    'clientId|u=s',
    'clientSecret|p=s',
    'tenantId|t=s',
    'resource-group|g=s',
    'location|l=s',
    'vmName=s',
    'adminUser=s',
    'publicKeyFile=s',
    'privateKeyFile=s',
    'k8sName=s',
    'acrName=s',
    'clean!',
    'verbose!',
);

{
    my $secret = delete $options{clientSecret};
    print Data::Dumper->Dump([\%options], ["options"]);
    $options{clientSecret} = $secret;
}

our $verbose = $options{verbose};

check_tool('Azure CLI', 'which az');
check_tool('Docker', 'which docker && docker ps');

throw_if_empty('Azure subscription ID', $options{subscriptionId});
throw_if_empty('Azure client ID', $options{clientId});
throw_if_empty('Azure client secret', $options{clientSecret});
throw_if_empty('Azure tenant ID', $options{tenantId});
throw_if_empty('VM admin user', $options{adminUser});

-e $options{publicKeyFile} or die "SSH public key file $options{publicKeyFile} does not exist.";
-e $options{privateKeyFile} or die "SSH private key file $options{privateKeyFile} does not exist.";

$options{publicKey} = Helpers::read_file($options{publicKeyFile}, 1);
$options{privateKey} = Helpers::read_file($options{privateKeyFile}, 1);

{
    local $main::verbose = 0;
    checked_run(qw(az login --service-principal -u), $options{clientId}, '-p', $options{clientSecret}, '-t',
        $options{tenantId});
}
checked_run(qw(az account set --subscription), $options{subscriptionId});

if (!$options{'resource-group'}) {
    if (not exists $options{clean}) {
        $options{clean} = 1;
    }
    $options{'resource-group'} = 'jenkins-smoke-' . Helpers::random_string();
    $options{'location'} ||= 'Southeast Asia';

    checked_run(qw(az group create -n), $options{'resource-group'}, '-l', $options{location});
} else {
    $options{'location'} = checked_output(qw(az group show --query location --output tsv -n), $options{'resource-group'});
}

if (!$options{k8sName}) {
    $options{k8sDns} = Helpers::random_string(10);
    $options{k8sName} = 'containerserivce-' . $options{k8sDns};
    process_file("$Bin/../conf/acs.parameters.json", "$Bin/../target/conf", \%options);
    checked_run(qw(az group deployment create --template-uri https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/101-acs-kubernetes/azuredeploy.json),
        '--resource-group', $options{'resource-group'}, '--parameters', '@' . "$Bin/../target/conf/acs.parameters.json");
#    checked_run(qw(az acs create --orchestrator-type kubernetes --agent-count 1 --resource-group), $options{'resource-group'}, '--name', $options{k8sName}, '--ssh-key-value', $options{publicKeyFile});
} else {
    $options{k8sDns} = $options{k8sName};
}

if (!$options{acrName}) {
    $options{acrName} = 'acr' . Helpers::random_string();
    checked_run(qw(az acr create --sku Basic --admin-enabled true --resource-group), $options{'resource-group'}, '--name', $options{acrName});
}

$options{acrHost} = checked_output(qw(az acr show --query loginServer --output tsv --resource-group), $options{'resource-group'}, '--name', $options{acrName});
$options{acrPassword} = checked_output(qw(az acr credential show --query passwords[0].value --output tsv --name), $options{acrName});

find(sub {
    if (-d $_) {
        return;
    }
    my $rel = File::Spec->abs2rel($File::Find::name, "$Bin/..");
    my $target_dir = File::Spec->catfile("$Bin/../target", dirname($rel));
    process_file($File::Find::name, $target_dir, \%options);
}, "$Bin/..");
chdir "$Bin/../target";

$options{jenkinsImage} = 'smoke-' . Helpers::random_string();
$options{dockerProcessName} = 'smoke-' . Helpers::random_string();

checked_run(qw(docker build -t), $options{jenkinsImage}, '.');

my $jenkins_home = "$Bin/../target/jenkins_home";
make_path($jenkins_home);
chmod 0777, $jenkins_home;

my $pid = fork();
if (!$pid) {
    checked_run(qw(docker run -it -p8090:8080 -v), "$jenkins_home:/var/jenkins_home", '--name', $options{dockerProcessName}, $options{jenkinsImage});
    exit 0;
}

# TODO
my @jobs = qw(acs-k8s);

sub read_link {
    my ($file) = @_;
    if (-l $file) {
        return readlink($file) || -1;
    } else {
        return -1;
    }
}

while (1) {
    print_banner("Check Build Status");
    for my $job (@jobs) {
        my $job_home = File::Spec->catfile($jenkins_home, 'jobs', $job);
        if (not -e $job_home) {
            print "$job - missing\n";
            next;
        }
        my $builds_home = File::Spec->catfile($job_home, 'builds');
        if (not -e $builds_home) {
            print "$job - no build\n";
            next;
        }
        my $lastSuccessfulBuild = read_link(File::Spec->catfile($builds_home, 'lastSuccessfulBuild'));
        my $lastUnsuccessfulBuild = read_link(File::Spec->catfile($builds_home, 'lastUnsuccessfulBuild'));
        if ($lastUnsuccessfulBuild > 0) {
            print "$job - failed\n";
        } elsif ($lastSuccessfulBuild > 0) {
            print "$job - successful\n";
        } else {
            print "$job - unknown\n";
        }
    }

    sleep 20;
}

waitpid $pid, 0;

sub END {
    return if not $options{clean};

    if ($options{'resource-group'}) {
        run_shell(qw(az group delete -y --no-wait -n), $options{'resource-group'});
    }
}

__END__

=head1 NAME

jenkins-smoke-test.pl - Script to bootstrap and run the smoke tests for Azure Jenkins plugins.

=head1 SYNOPSIS

jenkins-smoke-test.pl [options]

 Options:
                                (Azure service principal <required>)
   --subscriptionId|-s          subscription ID
   --clientId|-u                client ID
   --clientSecret|-p            client secret
   --tenantId|-t                tenant ID

                                (Miscellaneous)
   --verbose                    Turn on verbose output
   --help                       Show the help documentation
   --version                    Show the script version

=cut
