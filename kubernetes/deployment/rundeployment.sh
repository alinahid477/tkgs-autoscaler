#!/bin/bash

if [[ -z $1 || -z $2 ]]
then
    printf "\nERROR: You must provide/pass dockerhub username and password in the parameter."
    printf "\n\t parameter 1: username"
    printf "\n\t parameter 2: password"
    printf "\n\n"
    exit 1
fi

path=${BASH_SOURCE%/*}
if [[ ${path:0:1} == "." ]]
then
    path=${path:1}
    if [[ ${path:0:1} == "/" ]]
    then
        path=${path:1}
    fi
    if [[ -n $path ]]
    then
        path="${path}/"
    fi
fi

if [[ -z $path ]]
then
    printf "\ncurrent path is: .\n"
else
    printf "\ncurrent path is: $path\n"
fi

isexist=$(ls ${path}authz.yaml)
if [[ -z $isexist ]]
then
    printf "\nERROR: ${path}authz.yaml does not exist.\n"
    exit
fi

isexist=$(ls ${path}configmap.yaml)
if [[ -z $isexist ]]
then
    printf "\nERROR: ${path}configmap.yaml does not exist.\n"
    exit
fi

isexist=$(ls ${path}autoscaler-deployment.yaml)
if [[ -z $isexist ]]
then
    printf "\nERROR: ${path}autoscaler-deployment.yaml does not exist.\n"
    exit
fi

kubectl create namespace autoscaler
source ./${path}dockerhubregcred.sh $1 $2 autoscaler
kubectl apply -f ${path}authz.yaml
kubectl apply -f ${path}configmap.yaml
kubectl apply -f ${path}autoscaler-deployment.yaml

printf "\n****DONE****\n"