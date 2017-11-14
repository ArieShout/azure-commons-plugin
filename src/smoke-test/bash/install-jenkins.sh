#!/usr/bin/env bash
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See LICENSE in the project root for license information.

set -x

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPT_NAME="$(basename $0)"
soruce "$SCRIPT_DIR/lib.sh"
if false; then
source "lib.sh"
fi

print_usage() {
    cat <<EOF
Command
    $SCRIPT_NAME
Arguments

EOF
}

# sudo usermod -aG jenkins $USER
# sudo chmod -R g+w /var/lib/jenkins

export JENKINS_URL="http://localhost:8080/"
export JENKINS_USERNAME="admin"

# install plugins
# TODO install specific versions
readarray -t plugins < "$SCRIPT_DIR/plugins-topology"
for plugin in "${plugins[@]}"; do
    [[ -z "$plugin" ]] && continue
    [[ "$plugin" =~ ^\s*#.* ]] && continue
    echo "$plugin"
    "$SCRIPT_DIR/run-cli-command.sh" -c "install-plugin $plugin"
done

# Create Credential by XML
# here we may use some legacy version of credentials to check the backward compatibility
"$SCRIPT_DIR/run-cli-command.sh" -c "create-credentials-by-xml SystemCredentialsProvider::SystemContextResolver::jenkins _" <"credentials-file"
# 
#<com.microsoft.azure.util.AzureCredentials plugin="azure-credentials@1.3">
#    <scope>GLOBAL</scope>
#    <id>service-principal</id>
#    <description>Visual Studio China Jenkins DevINT</description>
#    <data>
#        <subscriptionId>...</subscriptionId>
#        <clientId>...</clientId>
#        <clientSecret>...</clientSecret>
#        <tenant>...</tenant>
#        <azureEnvironmentName>Azure</azureEnvironmentName>
#    </data>
#</com.microsoft.azure.util.AzureCredentials>

# <com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey plugin="ssh-credentials@1.13">
#     <scope>GLOBAL</scope>
#     <id>ssh-credentials</id>
#     <description>SSH credentials for Linux VM</description>
#     <username>chenyl</username>
#     <privateKeySource class="com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey$DirectEntryPrivateKeySource">
#         <privateKey>
# -----BEGIN RSA PRIVATE KEY-----
# ...
# -----END RSA PRIVATE KEY-----
#         </privateKey>
#     </privateKeySource>
# </com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey>

# Creates a new job by reading stdin as a configuration XML file.
"$SCRIPT_DIR/run-cli-command.sh" -c "create-job NAME" <"job-file"


"$SCRIPT_DIR/run-cli-command.sh" -c 'build acs-k8s-job -s'
