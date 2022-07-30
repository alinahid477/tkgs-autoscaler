#!/bin/bash

if [[ -z $1 || -z $2 ]]
then
    printf "\nERROR: You must provide/pass dockerhub username and password in the parameter."
    printf "\n\t parameter 1: username"
    printf "\n\t parameter 2: password"
    printf "\n\n"
    exit 1
fi
namespace=$3
if [[ -z $namespace ]]
then
    namespace='default'
fi
kubectl create secret docker-registry dockerhubregcred --docker-server=https://index.docker.io/v1/ --docker-username=$1 --docker-password=$2 --docker-email=your@email.com --namespace $namespace