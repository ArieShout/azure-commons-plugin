package Helpers;

use strict;
use warnings;

use IPC::Open3 qw(open3);
use Symbol;
use base qw(Exporter);

our @EXPORT = qw(get_env throw_if_empty random_string);
our @EXPORT_OK = qw(
    retry_until_successful
    quote_cmd_arg list2cmdline check_tool run_shell checked_run checked_run_quiet checked_output
    log_info log_warning log_error print_banner
);
our %EXPORT_TAGS = (
    log => [qw(log_info log_warning log_error print_banner)],
    shell => [qw(quote_cmd_arg list2cmdline check_tool run_shell checked_run checked_output)]
);

sub get_env {
    my ($name, $default) = @_;
    my $value = $ENV{$name};
    if (defined $value) {
        $value;
    } else {
        $default;
    }
}

sub throw_if_empty {
    my ($name, $value) = @_;
    if (not defined $value or length($value) == 0) {
        die qq{Parameter '$name' cannot be empty.\n};
    }
}

sub check_tool {
    my ($name, $command) = @_;
    my ($infh, $outfh, $errfh);
    $errfh = gensym();
    my $pid = open3($infh, $outfh, $errfh, '/bin/bash', '-c', $command);
    waitpid($pid, 0);
    if ($? != 0) {
        die qq{"$name" not found. Please install "$name" before running this script.\n};
    }
}

sub retry_until_successful {
    my @command = @_;
    my $count = 0;
    system(@command);
    while ($? != 0) {
        if ($count > 20) {
            die qq{Failed to execute command:\n@command\n};
        } else {
            $count++;
        }
        sleep(5);
        system(@command);
    }
}

my @random_chars = ('a'..'z', '0'..'9');
sub random_string {
    my ($length) = @_;
    $length ||= 6;
    my $string;
    $string .= $random_chars[rand(@random_chars)] for 1..$length;
    $string;
}

sub checked_output {
    my $command = list2cmdline(@_);
    if ($main::verbose) {
        log_info($command);
    }
    my $output = qx($command);
    if ($? != 0) {
        die "$? - Failed to execute command\n\t" . $command . "\n";
    }
    chomp $output;
    $output;
}

sub run_shell {
    my $command = list2cmdline(@_);
    if ($main::verbose) {
        log_info($command);
    }
    system("/bin/bash", "-c", $command);
}

sub checked_run {
    run_shell(@_) and die "$? - Failed to execute command\n\t" . list2cmdline(@_) . "\n";
}

sub quote_cmd_arg {
    my ($arg) = @_;
    if (not defined $arg or $arg eq '') {
        return qq{''};
    }
    if ($arg =~ /[^\w@%+=:,.\/-]/) {
        $arg =~ s/'/'"'"'/g;
        return qq{'$arg'};
    }
    return $arg;
}

sub list2cmdline {
    my @quoted = map { quote_cmd_arg($_) } @_;
    join(' ', @quoted);
}

sub log_with_color {
    my ($color, $msg) = @_;
    print "${color}${msg}\033[0m\n";
}

sub log_info {
    my ($msg) = @_;
    log_with_color "\033[0;32m", $msg;
}

sub log_warning {
    my ($msg) = @_;
    log_with_color "\033[0;33m", $msg;
}

sub log_error {
    my ($msg) = @_;
    log_with_color "\033[0;31m", $msg;
}

sub print_banner {
    my ($msg) = @_;
    log_info '';
    log_info '********************************************************************************';
    log_info "* ${msg}";
    log_info '********************************************************************************';
}

1;
