#!/usr/bin/env bash

#
# End to end scenario 2
#

source ../common.sh

../kcp.sh clean
../kcp.sh install -v ${KCP_VERSION}
../kcp.sh start

# Cluster 1 => color: green label
kind delete cluster --name cluster1
kind create cluster --name cluster1

# Cluster 2 => color: blue label
kind delete cluster --name cluster2
kind create cluster --name cluster2

tail -f _tmp/kcp-output.log | while read LOGLINE
do
   [[ "${LOGLINE}" == *"finished bootstrapping root workspace phase 1"* ]] && pkill -P $$ tail
done
echo "KCP is started :-)"

kubectl ctx kind-cluster1
../kcp.sh syncer -w my-org -c cluster1

kubectl ctx kind-cluster2
../kcp.sh syncer -w my-org -c cluster2

KUBECONFIG=${TEMP_DIR}/${KCP_CFG_PATH} k kcp ws root:my-org
KUBECONFIG=${TEMP_DIR}/${KCP_CFG_PATH} k label synctarget cluster1 color=green
KUBECONFIG=${TEMP_DIR}/${KCP_CFG_PATH} k label synctarget cluster2 color=blue

KUBECONFIG=${TEMP_DIR}/${KCP_CFG_PATH} k delete placement,location --all
KUBECONFIG=${TEMP_DIR}/${KCP_CFG_PATH} k apply -f ./k8s

note "Moving to the root:${KCP_WORKSPACE} workspace"
note ">> k kcp ws use root:${KCP_WORKSPACE}"
KUBECONFIG=${TEMP_DIR}/${KCP_CFG_PATH} k kcp ws use root:${KCP_WORKSPACE}

note "Create a quarkus app within the workspace: ${KCP_WORKSPACE}"
note ">> k create deployment quarkus --image=quay.io/rhdevelopers/quarkus-demo:v1"
KUBECONFIG=${TEMP_DIR}/${KCP_CFG_PATH} k create deployment quarkus --image=quay.io/rhdevelopers/quarkus-demo:v1
note ">> k rollout status deployment/quarkus"
KUBECONFIG=${TEMP_DIR}/${KCP_CFG_PATH} k rollout status deployment/quarkus

note "Check deployments available within the: $(KUBECONFIG=${TEMP_DIR}/${KCP_CFG_PATH} k kcp workspace .)."
note ">> k get deployments"
KUBECONFIG=${TEMP_DIR}/${KCP_CFG_PATH} k get deployments

KUBECONFIG=${KUBE_CFG} k ctx kind-cluster1
note "Current ws is: $(KUBECONFIG=${KUBE_CFG} k kcp workspace .)"
quarkus_pod=$(KUBECONFIG=${KUBE_CFG} k get po -lapp=quarkus -A -o name)
if [[ $quarkus_pod == pod* ]]; then
  ((counter+=1))
fi

KUBECONFIG=${KUBE_CFG} k ctx kind-cluster2
note "Current ws is: $(KUBECONFIG=${KUBE_CFG} k kcp workspace .)"
quarkus_pod=$(KUBECONFIG=${KUBE_CFG} k get po -lapp=quarkus -A -o name)
if [[ $quarkus_pod == pod* ]]; then
  ((counter+=1))
fi

if [[ $counter -eq 2 ]]; then
  succeeded "Check succeeded as $counter Quarkus Application were found on the physical clusters."
else
  error "Error: $counter deployments found within: $(k kcp workspace .) and not 2."
fi




