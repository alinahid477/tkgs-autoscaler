#!/bin/bash

SUPERVISOR_NAMESPACE=$1
SUPERVISOR_ENDPOINT=$2


if [[ $1 == @("--help"|"--h") ]]
then
  printf "\nUsage:"
  printf "\n\tparameter 1 supervisor/vsphere-namespace"
  printf "\n\tparameter 2 supervisor-endpoint (optional)"
  printf "\n"
  exit
fi

# if [[ -z $SUPERVISOR_ENDPOINT ]]
# then
#   echo "Error: You must provide supervisor endpoint as the first parameter."  
#   exit
# fi

if [[ -z $SUPERVISOR_NAMESPACE ]]
then
  echo "Error: You must provide supervisor namespace name (vsphere namespace) as the 1st parameter."  
  exit
fi

printf "Info: deploying authz.yaml...."
kubectl apply -f authz.yaml -n $SUPERVISOR_NAMESPACE

AUTO_SCALER_SA_TOKEN=$(kubectl get secrets -n $SUPERVISOR_NAMESPACE | grep autoscaler-sa-token | awk 'NR==1{print $1}')

echo "Info: AUTO_SCALER_SA_TOKEN_NAME=$AUTO_SCALER_SA_TOKEN"

# server=https://$SUPERVISOR_ENDPOINT:6443
# the name of the secret containing the service account token goes here
# AUTO_SCALER_SA_TOKEN=autoscaler-sa-token-bz5xp

# ca=$(kubectl get secret/$AUTO_SCALER_SA_TOKEN -n dev -o jsonpath='{.data.ca\.crt}')
token=$(kubectl get secret/$AUTO_SCALER_SA_TOKEN -n dev -o jsonpath='{.data.token}' | base64 --decode)
namespace=$(kubectl get secret/$AUTO_SCALER_SA_TOKEN -n dev -o jsonpath='{.data.namespace}' | base64 --decode)

# echo "
# apiVersion: v1
# kind: Config
# clusters:
# - name: $SUPERVISOR_ENDPOINT
#   cluster:
#     insecure-skip-tls-verify: true
#     server: ${server}
# contexts:
# - name: $SUPERVISOR_ENDPOINT
#   context:
#     cluster: $SUPERVISOR_ENDPOINT
#     namespace: $SUPERVISOR_NAMESPACE
#     user: autoscaler-sa
# current-context: $SUPERVISOR_ENDPOINT
# users:
# - name: autoscaler-sa
#   user:
#     token: ${token}
# " > autoscaler-supervisorsa.kubeconfig

echo ${token} > supervisorsatoken-$SUPERVISOR_NAMESPACE

printf "\n*Generated file supervisorsatoken-$SUPERVISOR_NAMESPACE* with token data.\n"