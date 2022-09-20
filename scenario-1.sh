#!/usr/bin/env bash

#
# End to end scenario 1
#

source common.sh

./kcp.sh clean
./kcp.sh install -v ${KCP_VERSION}
./kcp.sh start

note "Deleting and re-creating a kind k8s cluster"
kind delete cluster --name cluster1
kind create cluster --name cluster1

note "Waiting till kcp is started ...."
tail -f ${TEMP_DIR}/kcp-output.log | while read LOGLINE
do
   [[ "${LOGLINE}" == *"finished bootstrapping root workspace phase 1"* ]] && pkill -P $$ tail
done
echo "KCP is started :-)"

kubectl ctx kind-cluster1
./kcp.sh syncer -w my-org -c cluster1

note "Scenario 1: Create a workspace, deploy an application, move one level up and verify that no deployments exist as workspaces are isolated"

pushd $TEMP_DIR
note "Exporting the KCP KUBECONFIG: ${KCP_CFG_PATH}"
export KUBECONFIG=${KCP_CFG_PATH}

# tag::MovingToTheRoot[]
note "Moving to the root:${KCP_WORKSPACE} workspace"
note ">> k kcp ws use root:${KCP_WORKSPACE}"
k kcp ws use root:${KCP_WORKSPACE}
# end::MovingToTheRoot[]

note "Create a quarkus app within the workspace: ${KCP_WORKSPACE}"
note ">> k create deployment quarkus --image=quay.io/rhdevelopers/quarkus-demo:v1"
k create deployment quarkus --image=quay.io/rhdevelopers/quarkus-demo:v1
note ">> k rollout status deployment/quarkus"
k rollout status deployment/quarkus

note "Check deployments available within the: $(k kcp workspace .)."
note ">> k get deployments"
k get deployments

note "Moving to the parent workspace which is root"
note ">> k kcp ws use .."
k kcp ws use ..

check_deployment="error: the server doesn't have a resource type \"deployments\""
if [ "$check_deployment" == "$(k get deployments 2>&1)" ];then
  succeeded "Check succeeded as no deployments were found within the: $(k kcp workspace .)"
else
  error "Error: deployments found within: $(k kcp workspace .)"
fi

popd




