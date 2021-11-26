#!/bin/bash

create_supervisor_sa_kubeconfig()
{
	server=https://$SUPERVISOR_ENDPOINT:6443
	echo "
apiVersion: v1
kind: Config
clusters:
- name: $SUPERVISOR_ENDPOINT
  cluster:
    insecure-skip-tls-verify: true
    server: ${server}
contexts:
- name: $SUPERVISOR_ENDPOINT
  context:
    cluster: $SUPERVISOR_ENDPOINT
    namespace: $SUPERVISOR_NAMESPACE
    user: autoscaler-sa
current-context: $SUPERVISOR_ENDPOINT
users:
- name: autoscaler-sa
  user:
    token: ${SUPERVISOR_SA_TOKEN}
" > autoscaler-supervisorsa.kubeconfig

	echo "Info: Created autoscaler-supervisorsa.kubeconfig"
	ls -la
}

if [[ $INCLUSTER_CONFIG -eq 1 ]]
then
	echo "Info: Starting script within a Kubernetes cluster"	
else
	if [[ -f /app/autoscale.config ]]
	then
		echo "Info: Starting script outside a Kubernetes Cluster. Make sure a valid kubeconfig file exists for a Supervisor Cluster"
		source /app/autoscale.config
	else
		sleep 120
		exit 1
	fi
fi

create_supervisor_sa_kubeconfig


convert_to_bytes()
{
	VALUE_IN_Gi=${1%Gi}
	if [[ ${VALUE_IN_Gi} == ${1} ]]
	then
		VALUE_IN_Mi=${1%Mi}
		if [[ ${VALUE_IN_Mi} == ${1} ]]
		then
			VALUE_IN_Ki=${1%Ki}
			if [[ ${VALUE_IN_Ki} == ${1} ]] 
			then
				echo "${1}"|bc
			else
				echo "${VALUE_IN_Ki}*1024"|bc
			fi
		else
			echo "${VALUE_IN_Mi}*1024*1024"|bc
		fi
	else
		echo "${VALUE_IN_Gi}*1024*1024*1024"|bc
	fi
}

convert_to_millicpu()
{
	VALUE_IN_m=${1%m}
	if [[ ${VALUE_IN_m} == ${1} ]]
	then
		echo "${VALUE_IN_m}*1000"|bc
	else
		echo "${VALUE_IN_m}"|bc
	fi
}

scale_out()
{
	CLUSTER_STATUS=$4
	NUM_WORKER_NODES=$5

	if [ ${CLUSTER_STATUS} == "running" ]
	then
		TKC_NODE_COUNT=$(kubectl get tkc $1 -n $2 -o json --kubeconfig=autoscaler-supervisorsa.kubeconfig | jq -r '.spec.topology.nodePools[].replicas' | awk '{s+=$1} END {print s}')

		# Are nodes healthy? This will indicate that tkc is not in the process of creating or deleting (although running status says it but this is 2nd level check)
		ARE_NODES_HEALTHY=$(kubectl get tkc $1 -n $2 -o json --kubeconfig=autoscaler-supervisorsa.kubeconfig | jq -r '.status.conditions[] |select(.type=="NodesHealthy") | .status')
		# make it lower case
		ARE_NODES_HEALTHY=$(echo ${ARE_NODES_HEALTHY,,})

		echo "Info:  (scale out) TKC_NODE_COUNT - ${TKC_NODE_COUNT}, NUM_WORKER_NODES - ${NUM_WORKER_NODES}"
		if [[ $TKC_NODE_COUNT == $NUM_WORKER_NODES && $ARE_NODES_HEALTHY == "true" ]]
		then
			((TKC_NEW_NODE_COUNT=TKC_NODE_COUNT+1))
			if [ ${TKC_NEW_NODE_COUNT} -gt $3 ]
			then
				echo "Warning: Cluster ${1} already has maximum node count. Cannot scale out further..."
			else
				NODE_POOL_BLOCK=$(kubectl get tkc $1 -n $2 -o json --kubeconfig=autoscaler-supervisorsa.kubeconfig | jq -rc '.spec.topology.nodePools')

				if [[ -n $NODE_POOL_BLOCK &&  $NODE_POOL_BLOCK != "null" ]]
				then
					FIRST_NODE_POOL_BLOCK=$(echo $NODE_POOL_BLOCK | jq -c '.[0]')
					if [[ -n $FIRST_NODE_POOL_BLOCK && $FIRST_NODE_POOL_BLOCK != "null" ]]
					then
						FIRST_NODE_POOL_NAME=$(echo $FIRST_NODE_POOL_BLOCK | jq '.name' | xargs)
					fi
				fi
				if [[ -n $FIRST_NODE_POOL_NAME && $FIRST_NODE_POOL_NAME != "null" ]]
				then
					NODE_POOL_BLOCK=$(echo $NODE_POOL_BLOCK | jq -c 'del(.[0])')
					FIRST_NODE_POOL_STORAGE_CLASS=$(echo $FIRST_NODE_POOL_BLOCK | jq '.storageClass' | xargs)
					FIRST_NODE_POOL_VMCLASS=$(echo $FIRST_NODE_POOL_BLOCK | jq '.vmClass' | xargs)
					FIRST_NODE_POOL_TKR_BLOCK=$(echo $FIRST_NODE_POOL_BLOCK | jq -rc '.tkr')					
					NODE_POOL_BLOCK=$(echo $NODE_POOL_BLOCK | jq '.|= [{"name": "'$FIRST_NODE_POOL_NAME'", "replicas": '$TKC_NEW_NODE_COUNT', "storageClass": "'$FIRST_NODE_POOL_STORAGE_CLASS'", "vmClass": "'$FIRST_NODE_POOL_VMCLASS'", "tkr": '${FIRST_NODE_POOL_TKR_BLOCK}' }] + .')
					echo "Info: Cluster ${1} is being scaled up to ${TKC_NEW_NODE_COUNT} nodes..."
					kubectl patch tkc $1 -n $2 --kubeconfig=autoscaler-supervisorsa.kubeconfig --type merge --patch "{\"spec\": {\"topology\": { \"nodePools\": $NODE_POOL_BLOCK  } }}"
				else
					echo "Error: unable to extract nodepool for Cluster ${1}. Cannot scale out further..."
				fi

				
			fi
		else
			echo "Warning: Cluster ${1} has a node in pending create/delete state. Possible resize in progress. Skipping resize..."
		fi
	else
		echo "Warning: Cluster ${1} is not in Running state. Skipping resize..."
	fi
}

scale_in()
{
	CLUSTER_STATUS=$4
	NUM_WORKER_NODES=$5

	if [ ${CLUSTER_STATUS} == "running" ]
	then
		TKC_NODE_COUNT=$(kubectl get tkc $1 -n $2 -o json --kubeconfig=autoscaler-supervisorsa.kubeconfig | jq -r '.spec.topology.nodePools[].replicas' | awk '{s+=$1} END {print s}')
		# Are nodes healthy? This will indicate that tkc is not in the process of creating or deleting (although running status says it but this is 2nd level check)
		ARE_NODES_HEALTHY=$(kubectl get tkc $1 -n $2 -o json --kubeconfig=autoscaler-supervisorsa.kubeconfig | jq -r '.status.conditions[] |select(.type=="NodesHealthy") | .status')
		# make it lower case
		ARE_NODES_HEALTHY=$(echo ${ARE_NODES_HEALTHY,,})

		echo "Info: (scale in) TKC_NODE_COUNT - ${TKC_NODE_COUNT}, NUM_WORKER_NODES - ${NUM_WORKER_NODES}"
		if [[ $TKC_NODE_COUNT == $NUM_WORKER_NODES && $ARE_NODES_HEALTHY == "true" ]]
		then 
			((TKC_NEW_NODE_COUNT=TKC_NODE_COUNT-1))
			if [ ${TKC_NEW_NODE_COUNT} -lt $3 ]
			then
				echo "Warning: $1 already has minimum node count. Cannot scale in further..."
			else

				NODE_POOL_BLOCK=$(kubectl get tkc $1 -n $2 -o json --kubeconfig=autoscaler-supervisorsa.kubeconfig | jq -rc '.spec.topology.nodePools')

				if [[ -n $NODE_POOL_BLOCK &&  $NODE_POOL_BLOCK != "null" ]]
				then
					FIRST_NODE_POOL_BLOCK=$(echo $NODE_POOL_BLOCK | jq -c '.[0]')
					if [[ -n $FIRST_NODE_POOL_BLOCK && $FIRST_NODE_POOL_BLOCK != "null" ]]
					then
						FIRST_NODE_POOL_NAME=$(echo $FIRST_NODE_POOL_BLOCK | jq '.name' | xargs)
					fi
				fi
				if [[ -n $FIRST_NODE_POOL_NAME && $FIRST_NODE_POOL_NAME != "null" ]]
				then
					NODE_POOL_BLOCK=$(echo $NODE_POOL_BLOCK | jq -c 'del(.[0])')
					FIRST_NODE_POOL_STORAGE_CLASS=$(echo $FIRST_NODE_POOL_BLOCK | jq '.storageClass' | xargs)
					FIRST_NODE_POOL_VMCLASS=$(echo $FIRST_NODE_POOL_BLOCK | jq '.vmClass' | xargs)
					FIRST_NODE_POOL_TKR_BLOCK=$(echo $FIRST_NODE_POOL_BLOCK | jq -rc '.tkr')					
					NODE_POOL_BLOCK=$(echo $NODE_POOL_BLOCK | jq '.|= [{"name": "'$FIRST_NODE_POOL_NAME'", "replicas": '$TKC_NEW_NODE_COUNT', "storageClass": "'$FIRST_NODE_POOL_STORAGE_CLASS'", "vmClass": "'$FIRST_NODE_POOL_VMCLASS'", "tkr": '${FIRST_NODE_POOL_TKR_BLOCK}' }] + .')
					echo "Info: Cluster ${1} is being scaled down to ${TKC_NEW_NODE_COUNT} nodes..."
					kubectl patch tkc $1 -n $2 --kubeconfig=autoscaler-supervisorsa.kubeconfig --type merge --patch "{\"spec\": {\"topology\": { \"nodePools\": $NODE_POOL_BLOCK  } }}"
				else
					echo "Error: unable to extract nodepool for Cluster ${1}. Cannot scale out further..."
				fi
			fi
		else
			echo "Warning: Cluster ${1} has a node in pending create/delete state. Possible resize in progress. Skipping resize..."
		fi
	else
		echo "Warning: Cluster ${1} is not in Running state. Skipping resize..."
	fi
}


WORKLOAD_CLUSTERS_ARR=($(echo "$WORKLOAD_CLUSTERS" | tr ',' '\n'))
while true
do 	
	for WORKLOAD_CLUSTER in ${WORKLOAD_CLUSTERS_ARR[@]}
	do
		echo "Info: ***** Start Prpcessing for ${WORKLOAD_CLUSTER} *****"

		CLUSTER_STATUS=$(kubectl get tkc ${WORKLOAD_CLUSTER} -n ${SUPERVISOR_NAMESPACE} -o json --kubeconfig=autoscaler-supervisorsa.kubeconfig |jq -r '.status.phase')
		if [[ $CLUSTER_STATUS == "running" ]]
		then

			echo "Info: ${WORKLOAD_CLUSTER} is in running state. Continue processing..."

			SCALE_OUT_REQ=0
			SCALE_IN_REQ=0

			NODE_MEM_SUM=0
			NODE_CPU_SUM=0
			NODE_ALLOCATED_MEM_SUM=0
			NODE_ALLOCATED_CPU_SUM=0

			# Generating Workload cluster Kubeconfig
			isexist=$(ls ${WORKLOAD_CLUSTER}-kubeconfig)
			if [[ -z $isexist ]]
			then
				echo "Info: ${WORKLOAD_CLUSTER}-kubeconfig does not exists. Creating one..."
				kubectl get secrets ${WORKLOAD_CLUSTER}-kubeconfig -n ${SUPERVISOR_NAMESPACE} -o json --kubeconfig=autoscaler-supervisorsa.kubeconfig |jq -r '.data.value'|base64 -d > ${WORKLOAD_CLUSTER}-kubeconfig
				ls -la
				# /app/generatesakubeconfig.sh ${WORKLOAD_CLUSTER} ${WORKLOAD_CLUSTER_ENDPOINT} ${SA_TOKEN_NAME}
			else
				echo "Info: Found existing ${WORKLOAD_CLUSTER}-kubeconfig."
			fi
			

			NUM_WORKER_NODES=$(kubectl get nodes --kubeconfig=${WORKLOAD_CLUSTER}-kubeconfig --selector 'node-role.kubernetes.io/master!=' -o json |jq -r '.items'|jq length)
			if [[ $NUM_WORKER_NODES -lt $MAX_NODE_COUNT ]]
			then
				# Scale out code goes here
				PENDING_PODS_NS=$(kubectl get pods -A --kubeconfig=${WORKLOAD_CLUSTER}-kubeconfig --field-selector=status.phase==Pending,metadata.namespace!=vmware-system-tmc,metadata.namespace!=vmware-system-csi,metadata.namespace!=vmware-system-cloud-provider,metadata.namespace!=vmware-system-auth,metadata.namespace!=kube-system,metadata.namespace!=kube-public -o json |jq -r '.items[] | .metadata.namespace + ";" + .metadata.name')
				for ARRAY in ${PENDING_PODS_NS}
				do
					PENDING_POD_NS=(${ARRAY//;/ })
					# Check if the Pending POD is Unschedulable due to Insufficient memory of CPU.
					echo "Info: found pending for pod ${PENDING_POD_NS[1]} -n ${PENDING_POD_NS[0]}. Checking for Unschedulable due to Insufficient memory of CPU..."
					UNSCHEDULABLE_MSG=$(kubectl get pods ${PENDING_POD_NS[1]} --kubeconfig=${WORKLOAD_CLUSTER}-kubeconfig -n ${PENDING_POD_NS[0]} -o json | jq -r '.status.conditions[]|select (.reason == "Unschedulable")|.message')
					iscpumsg=$(echo $UNSCHEDULABLE_MSG | grep -i "Insufficient cpu[,.]")
					ismemmsg=$(echo $UNSCHEDULABLE_MSG | grep -i "Insufficient memory[,.]")
					if [[ -n $iscpumsg ]]
					then
						echo "Info: Cluster ${WORKLOAD_CLUSTER} failed to schedule POD(s) due to CPU pressure. Scaling required."
						SCALE_OUT_REQ=1
						break
					elif [[ -n $ismemmsg ]]
					then
						echo "Info: Cluster ${WORKLOAD_CLUSTER} failed to schedule POD(s) due to Memory pressure. Scaling required."
						SCALE_OUT_REQ=1
						break
					fi
				done
				if [ ${SCALE_OUT_REQ} -eq 1 ]
				then
					echo "Info: calling scale OUT with params === cluster ${WORKLOAD_CLUSTER} in ns ${SUPERVISOR_NAMESPACE} new nodecount ${NUM_WORKER_NODES}, max:${MAX_NODE_COUNT} "
					scale_out ${WORKLOAD_CLUSTER} ${SUPERVISOR_NAMESPACE} ${MAX_NODE_COUNT} ${CLUSTER_STATUS} ${NUM_WORKER_NODES}
					break
				fi
			fi
			
			
			
			if [[ ${SCALE_OUT_REQ} -ne 1 && ${NUM_WORKER_NODES} -gt ${MIN_NODE_COUNT} ]]
			then

				for NODE in $(kubectl get nodes --kubeconfig=${WORKLOAD_CLUSTER}-kubeconfig --selector 'node-role.kubernetes.io/master!=' -o json| jq -r '.items[].metadata.name')
				do
					echo "Info: Gathering CPU and meory allocation stats from ${NODE}"
					NODE_DETAIL=$(kubectl describe node ${NODE} --kubeconfig=${WORKLOAD_CLUSTER}-kubeconfig)
					
					NODE_MEMORY=$(echo "$NODE_DETAIL"|grep Allocatable -A 7 | grep memory|awk '{print $2}')
					NODE_CPU=$(echo "$NODE_DETAIL" | grep Allocatable -A 7 | grep cpu | awk '{print $2}')
					NODE_ALLOCATED_MEMORY=$(echo "$NODE_DETAIL" |grep Allocated -A 7 | grep memory | awk '{print $2}')
					NODE_ALLOCATED_CPU=$(echo "$NODE_DETAIL" | grep Allocated -A 7 | grep cpu | awk '{print $2}')
					
					echo "Info: ${NODE}-->NODE_MEMORY=$NODE_MEMORY, NODE_CPU=$NODE_CPU, NODE_ALLOCATED_MEMORY=$NODE_ALLOCATED_MEMORY, NODE_ALLOCATED_CPU=$NODE_ALLOCATED_CPU"

					temp1=$(convert_to_bytes ${NODE_MEMORY})
					temp2=$(convert_to_bytes ${NODE_ALLOCATED_MEMORY})
					temp3=$(convert_to_millicpu ${NODE_CPU})
					temp4=$(convert_to_millicpu ${NODE_ALLOCATED_CPU})
									
					echo "Info: ${NODE} conv -->NODE_MEMORY=$temp1, NODE_CPU=$temp3, NODE_ALLOCATED_MEMORY=$temp2, NODE_ALLOCATED_CPU=$temp4"

					NODE_MEM_SUM+="+${temp1}"
					NODE_ALLOCATED_MEM_SUM+="+${temp2}"
					NODE_CPU_SUM+="+${temp3}"
					NODE_ALLOCATED_CPU_SUM+="+${temp4}"
				done
				MAX_TOTAL_CPU=$(echo "scale=1; $MIN_AVAIL_CPU_PERCENTAGE/100" | bc)
				MAX_TOTAL_MEM=$(echo "scale=1; $MIN_AVAIL_MEM_PERCENTAGE/100" | bc)
				# Code for Scale in check goes here
				ALLOC_CPU=$(echo ${NODE_ALLOCATED_CPU_SUM} | bc)
				ALLOC_MEM=$(echo ${NODE_ALLOCATED_MEM_SUM} | bc)
				TARGET_CPU=$(echo "scale=0; (${NODE_CPU_SUM})*${MAX_TOTAL_CPU}*(${NUM_WORKER_NODES}-1)/${NUM_WORKER_NODES}" |bc)
				TARGET_MEM=$(echo "scale=0; (${NODE_MEM_SUM})*${MAX_TOTAL_MEM}*(${NUM_WORKER_NODES}-1)/${NUM_WORKER_NODES}" |bc)

				# TOTAL_CPU_USAGE_PERCENTAGE=$(kubectl top nodes --kubeconfig=${WORKLOAD_CLUSTER}-kubeconfig --selector 'node-role.kubernetes.io/master!=' --no-headers | awk '{print $3}' | awk '{s+=$1} END {print s}')
				# TOTAL_MEM_USAGE_PERCENTAGE=$(kubectl top nodes --kubeconfig=${WORKLOAD_CLUSTER}-kubeconfig --selector 'node-role.kubernetes.io/master!=' --no-headers | awk '{print $5}' | awk '{s+=$1} END {print s}')
				
				# ((TOTAL_CPU_AVAIL_PERCENTAGE=100*NUM_WORKER_NODES))
				# ((TOTAL_MEM_AVAIL_PERCENTAGE=100*NUM_WORKER_NODES))

				# ((REMAINING_CPU_PERCENTAGE=TOTAL_CPU_AVAIL_PERCENTAGE-TOTAL_CPU_USAGE_PERCENTAGE))
				# ((REMAINING_MEM_PERCENTAGE=TOTAL_MEM_AVAIL_PERCENTAGE-TOTAL_MEM_USAGE_PERCENTAGE))

				# ((CPU_THRESHOLD_PERCENTAGE=REMAINING_CPU_PERCENTAGE+MIN_AVAIL_CPU_PERCENTAGE))
				# ((MEM_THRESHOLD_PERCENTAGE=REMAINING_MEM_PERCENTAGE+MIN_AVAIL_MEM_PERCENTAGE))
				
				#if [[ ${CPU_THRESHOLD_PERCENTAGE} -lt ${TOTAL_CPU_AVAIL_PERCENTAGE} ]] && [[ ${MEM_THRESHOLD_PERCENTAGE} -lt ${TOTAL_MEM_AVAIL_PERCENTAGE} ]]
				if [[ ${ALLOC_CPU} -lt ${TARGET_CPU} ]] && [[ ${ALLOC_MEM} -lt ${TARGET_MEM} ]]
				then
					SCALE_IN_REQ=1
				fi
			fi
			if [ ${SCALE_IN_REQ} -eq 1 ]
			then
				echo "Info: calling scale IN with params === clustername: ${WORKLOAD_CLUSTER} in namespace: ${SUPERVISOR_NAMESPACE} to nodecount ${NUM_WORKER_NODES}, min: ${MIN_NODE_COUNT} "
				scale_in ${WORKLOAD_CLUSTER} ${SUPERVISOR_NAMESPACE} ${MIN_NODE_COUNT} ${CLUSTER_STATUS} ${NUM_WORKER_NODES}
				break
			fi		
		else
			echo "Warning: ${WORKLOAD_CLUSTER} is in ${CLUSTER_STATUS} state. NOT processing."	
		fi


		echo "Info: ${WORKLOAD_CLUSTER} processed. Sleep ${SCRIPT_FREQ_MIN} minutes..."
		sleep ${SCRIPT_FREQ_MIN}m
	done

	


	echo "Info: Script sleeping for ${SCRIPT_FREQ_MIN} minutes..."
	sleep ${SCRIPT_FREQ_MIN}m
done
