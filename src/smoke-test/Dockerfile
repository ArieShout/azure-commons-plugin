FROM ubuntu:16.04

RUN wget -q -O - https://pkg.jenkins.io/debian/jenkins-ci.org.key | apt-key add - && \
    echo deb https://pkg.jenkins.io/debian-stable binary/ | tee /etc/apt/sources.list.d/jenkins.list && \
    apt-get update && \
    apt-get install -y jenkins

RUN echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ wheezy main" | tee /etc/apt/sources.list.d/azure-cli.list && \
    apt-key adv --keyserver packages.microsoft.com --recv-keys 52E16F86FEE04B979B07E28DB02C46DF417A0893 && \
    apt-get install apt-transport-https && \
    apt-get update && apt-get install -y azure-cli

