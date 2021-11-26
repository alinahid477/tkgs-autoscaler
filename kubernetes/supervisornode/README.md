# vSphere with Tanzu Autoscaler

1. For this autoscaler to work there must be a service account created in the supervisor cluster.

2. The autoscaler uses the service account and its secret token to create a kubeconfig file which it uses to do `kubectl get tkc --kubeconfig={supervisor-sa.kubeconfig}`. That's how the autoscaler knows the status of the tanzu workload cluster and scale in or scale out it.

3. The container knows about this service account token and other stuffs that it needs to know about via 
    - **k8s deployment context:** env variables in the autoscaler-deployment.yaml file
    Fill out the environment variable accordingly.

4. Build and push docker to docker registry of choice using Dockerfile in script dir. Alternatively, use accordingtoali/autoscaler:0.0.4 prebuilt docker.

5. Deployment the autoscaller requires few steps
    - create namespace
    - create dockerhub credential (this for dockerhub's pull limit)
    - deploy the deployment file

# Steps

## Step 1: Service account in supervisor cluster

### Get password for ssh'ing into supervisor-cluster's node

ssh into vcentre server and run:
```
/usr/lib/vmware-wcp/decryptK8Pwd.py
```

For example:

```
root@vcenter [ ~ ]# /usr/lib/vmware-wcp/decryptK8Pwd.py
Read key from file

Connected to PSQL

Cluster: domain-c46:def22104-2b40-4048-b049-271b1de46b94
IP: 192.168.250.50
PWD: WpDPx87AQpMerTZ0nUN9CUlc6GmroZglczLp4AGFKd+5bUJEc7XolVfMjt9IBhy7gXIMd9tI
------------------------------------------------------------
```

### Transfer necessary files

Grab one of the supervisors node id (any will do) from vsphere and perform below:

Below are the file you will need to transfer to supervisor node to create service account in supervisor cluster
- kubernetes/supervisornode/authz.yaml
- 

### SSH into one of the supervisor node



```
ssh root@192.168.130.3
```

when prompted for password apply the password you recorded from the above.



