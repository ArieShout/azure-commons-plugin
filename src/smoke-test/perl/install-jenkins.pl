#!/usr/bin/env perl

use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/lib";
use Helpers;
use JenkinsCli;

my $cli = JenkinsCli->new();
#$cli->run('reload-configuration');
#$cli->run('create-job', 'acs-k8s-test', STDIN => '/home/vscjenkins/k8s-job.xml');
$cli->add_cloud('/home/vscjenkins/vm-cloud.xml');
