package SSHClient;

use strict;
use warnings FATAL => 'all';

use Helpers qw(:log :shell throw_if_empty);

sub new {
    my $class = shift;
    my ($host, $port, $user, $key) = @_;
    throw_if_empty("SSH host", $host);
    throw_if_empty("SSH user", $user);
    throw_if_empty("SSH private key file path", $key);

    my $self = {
        host => $host,
        port => $port,
        user => $user,
        key => $key,
    };

    bless $self, $class;
    $self;
}

sub run {
    my $self = shift;

    checked_run($self->base_command, @_);
}

sub output {
    my $self = shift;

    checked_output($self->base_command, @_);
}

sub login_host {
    my $self = shift;

    $self->{user} . '@' . $self->{host};
}

sub base_command {
    my $self = shift;
    'ssh', '-p', $self->{port}, '-i', $self->{key}, '-o', 'StrictHostKeyChecking=no', $self->login_host, '--';
}

1;
