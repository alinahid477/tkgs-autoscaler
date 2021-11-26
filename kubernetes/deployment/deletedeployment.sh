#!/bin/bash

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


kubectl delete secret dockerhubregcred -n autoscaler
kubectl delete -f ${path}autoscaler-deployment.yaml
kubectl delete -f ${path}configmap.yaml
kubectl delete -f ${path}authz.yaml
# kubectl create namespace autoscaler

printf "\n****DONE****\n"