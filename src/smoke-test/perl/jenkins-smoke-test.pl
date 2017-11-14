#!/usr/bin/env perl

use strict;
use warnings FATAL => 'all';

package main;

use FindBin qw($Bin);
use lib "$Bin/lib";
use Getopt::Long qw(:config gnu_getopt no_ignore_case auto_version auto_help);
use Helpers qw(:log :shell throw_if_empty random_string);
use SSHClient;
use JenkinsCli;
use File::Spec;

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
    'clean!',
    'verbose!',
);

print Dumper(\%options);

our $verbose = $options{verbose};

check_tool('Azure CLI', 'which az');
throw_if_empty('Azure subscription ID', $options{subscriptionId});
throw_if_empty('Azure client ID', $options{clientId});
throw_if_empty('Azure client secret', $options{clientSecret});
throw_if_empty('Azure tenant ID', $options{tenantId});
throw_if_empty('VM admin user', $options{adminUser});
-e $options{publicKeyFile} or die "SSH public key file $options{publicKeyFile} does not exist.";
-e $options{privateKeyFile} or die "SSH private key file $options{privateKeyFile} does not exist.";

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
}

# provision Jenkins
if (!$options{vmName}) {
    $options{vmName} = 'smoke-vm-' . random_string();
    checked_run(qw(az vm create -n), $options{vmName}, '-g', $options{'resource-group'}, '--image', 'UbuntuLTS', '--size',
        'Standard_DS2_v2', '--admin-username', $options{adminUser}, '--ssh-key-value', $options{publicKeyFile});
}

my $vmAddress = checked_output(qw(az vm show -d --query publicIps --output tsv --resource-group), $options{'resource-group'}, '--name', $options{vmName});

my $ssh = SSHClient->new($vmAddress, 22, $options{adminUser}, $options{privateKeyFile});

$ssh->run(<<'EOF');
# install jenkins
sudo apt-get update

wget -q -O - https://pkg.jenkins.io/debian/jenkins-ci.org.key | sudo apt-key add -
echo deb https://pkg.jenkins.io/debian-stable binary/ | sudo tee /etc/apt/sources.list.d/jenkins.list

sudo apt-get update
sudo apt-get install -y jenkins openjdk-8-jdk
EOF

my $jenkins_password = $ssh->output('sudo cat /var/lib/jenkins/secrets/initialAdminPassword');
my $jenkins = JenkinsCli->new(url => qq{http://$vmAddress:8080/}, password => $jenkins_password);
my @plugins = qw(
    cloudbees-folder
    antisamy-markup-formatter
    build-timeout
    credentials-binding
    timestamper
    ws-cleanup
    ant
    gradle
    workflow-aggregator
    github-branch-source
    pipeline-github-lib
    pipeline-stage-view
    git
    subversion
    ssh-slaves
    matrix-auth
    pam-auth
    ldap
    email-ext
    mailer
    azure-commons
    azure-credentials
    kubernetes-cd
    azure-acs
    windows-azure-storage
    azure-container-agents
    azure-vm-agents
    azure-app-service
    azure-function
);
for my $plugin (@plugins) {
    $jenkins->install_plugin($plugin, deploy => 1);
}

$ssh->copy_to("$Bin/../groovy/init.groovy", "init.groovy");
$ssh->run(<<'EOF');
sudo mv init.groovy /var/lib/jenkins/
sudo service jenkins restart
EOF

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
