/*
 * Copyright (c) Microsoft Corporation. All rights reserved.
 * Licensed under the MIT License. See LICENSE in the project root for license information.
 */


import com.cloudbees.jenkins.plugins.sshcredentials.impl.BasicSSHUserPrivateKey
import com.cloudbees.plugins.credentials.CredentialsScope
import com.cloudbees.plugins.credentials.SystemCredentialsProvider
import com.cloudbees.plugins.credentials.domains.Domain
import com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl
import com.microsoft.azure.util.AzureCredentials
import com.microsoft.azure.vmagent.AzureVMAgentTemplate
import com.microsoft.azure.vmagent.AzureVMCloud
import com.microsoft.azure.vmagent.AzureVMCloudRetensionStrategy
import groovy.json.JsonSlurper
import hudson.security.AuthorizationStrategy
import hudson.security.HudsonPrivateSecurityRealm
import jenkins.model.*

class Helper {
    static String randomString(int length = 8) {
        UUID.randomUUID().toString().replaceAll("-", "").substring(0, length)
    }
}

class Config {
    static String location = 'Southeast Asia'
    static Map<String, String> vmCredential = [
            id: 'vm-credential',
            username: 'jenkinssmoke',
            password: 'A*1' + Helper.randomString(16)
    ]
    static Map<String, String> sshCredential = [
            id: 'ssh-credential',
            username: 'azureuser',
            privateKey: '/opt/jenkins/.ssh/id_rsa',
            publicKey: '/opt/jenkins/.ssh/id_rsa.pub'
    ]
    static String configPath = "/opt/jenkins/config.json"

    static Map<String, String> servicePrincipal = [
            id: 'sp',
            subscriptionId: '',
            clientId: '',
            clientSecret: '',
            tenant: ''
    ]

    static {
        def jsonSlurper = new JsonSlurper()
        def cfg = jsonSlurper.parseText(new File(configPath).text)

        servicePrincipal.subscriptionId = cfg.subscriptionId
        servicePrincipal.clientId = cfg.clientId
        servicePrincipal.clientSecret = cfg.clientSecret
        servicePrincipal.tenant = cfg.tenant
    }
}

static void setupSecurity() {
    Jenkins instance = Jenkins.instance
    def strategy = AuthorizationStrategy.UNSECURED
    instance.authorizationStrategy = strategy
    instance.save()
}

static void addVmCredential() {
    def credential = new UsernamePasswordCredentialsImpl(
            CredentialsScope.GLOBAL,
            Config.vmCredential.id,
            "VM Credential",
            Config.vmCredential.username,
            Config.vmCredential.password
    )
    SystemCredentialsProvider.instance.store.addCredentials(Domain.global(), credential)
}

static void addSshCredential() {
    def credential = new BasicSSHUserPrivateKey(
            CredentialsScope.GLOBAL,
            Config.sshCredential.id,
            Config.sshCredential.username,
            new BasicSSHUserPrivateKey.FileOnMasterPrivateKeySource(Config.sshCredential.privateKey),
            '',
            'SSH private key credential to login to the given VM'
    )
    SystemCredentialsProvider.instance.store.addCredentials(Domain.global(), credential)
}

static void addAzureCredential() {
    def credential = new AzureCredentials(
            CredentialsScope.GLOBAL,
            Config.servicePrincipal.id,
            'Service Principal for Azure resources',
            Config.servicePrincipal.subscriptionId,
            Config.servicePrincipal.clientId,
            Config.servicePrincipal.clientSecret
    )
    credential.tenant = Config.servicePrincipal.tenant
    credential.azureEnvironmentName = 'Azure'
    SystemCredentialsProvider.instance.store.addCredentials(Domain.global(), credential)
}

static void setupVmCloud(String azureCredentialId) {
    String storageAccount = "storage" + Helper.randomString()
    AzureVMAgentTemplate template = new AzureVMAgentTemplate(
            "vm-cloud-template",
            "VM cloud for Jenkins plugins smoke test",
            "vm linux",
            Config.location,
            "Standard_A0",
            "new",
            "Standard_LRS",
            storageAccount,
            "",
            "managed",
            "1",
            "NORMAL",
            "Ubuntu 16.04 LTS",
            true,
            true,
            false,
            "Linux",
            "basic",
            false,
            new AzureVMAgentTemplate.ImageReferenceTypeClass("", "", "", "", ""),
            "SSH",
            true,
            "",
            Config.vmCredential.id,
            "",
            "",
            "",
            false,
            "",
            "",
            "",
            new AzureVMCloudRetensionStrategy(60),
            false,
            false,
            "",
            true,
            true
    )

    AzureVMCloud cloud = new AzureVMCloud(
            "vm-cloud",
            "vm-cloud",
            azureCredentialId,
            "3",
            "1200",
            "new",
            "jenkins-smoke-" + Helper.randomString(),
            "",
            [template]
    )

    Jenkins instance = Jenkins.instance
    instance.clouds.replace(cloud)
    instance.save()
}

setupSecurity()
addVmCredential()
addSshCredential()
addAzureCredential()
setupVmCloud(Config.servicePrincipal.id)

Thread.start {
    sleep 10000
    println '--> setting up jobs'
    def process = 'bash /opt/bash/setup-jobs.sh'.execute()
    process.waitForProcessOutput(System.out, System.err)
}
