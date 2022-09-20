#!/usr/bin/env bash

#
# End to end scenario 3
#

source ../common.sh

if ! command -v helm &> /dev/null; then
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "Helm could not be found. To get helm: https://helm.sh/docs/intro/install/"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    exit 1
fi

HELM_VERSION=$(helm version 2>&1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+') || true
if [[ ${HELM_VERSION} < "v3.0.0" ]]; then
  echo "Please upgrade helm to v3.0.0 or higher"
  exit 1
fi

./server.sh clean
./server.sh install -v ${KCP_VERSION}
./server.sh start

# Kind cluster config template
kindCfg=$(cat <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
        authorization-mode: "AlwaysAllow"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
EOF
)

# Cluster 1 => color: green label
kind delete cluster --name cluster1
echo "${kindCfg}" | kind create cluster --config=- --name cluster1
#
# Install the ingress nginx controller using helm
# Set the Service type as: NodePort (needed for kind)
#
echo "Installing the ingress controller using Helm within the namespace: ingress"
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress --create-namespace \
  --set controller.service.type=NodePort \
  --set controller.hostPort.enabled=true

tail -f _tmp/kcp-output.log | while read LOGLINE
do
   [[ "${LOGLINE}" == *"finished bootstrapping root workspace phase 1"* ]] && pkill -P $$ tail
done
echo "KCP is started :-)"

kubectl ctx kind-cluster1
./server.sh syncer -w my-org -c cluster1 -r ingresses.networking.k8s.io,services

note "Moving to the root:${KCP_WORKSPACE} workspace"
note ">> k kcp ws use root:${KCP_WORKSPACE}"
KUBECONFIG=${TEMP_DIR}/${KCP_CFG_PATH} k kcp ws use root:${KCP_WORKSPACE}

note "Create a quarkus app within the workspace: ${KCP_WORKSPACE}"
note ">> k create deployment quarkus --image=quay.io/rhdevelopers/quarkus-demo:v1"
KUBECONFIG=${TEMP_DIR}/${KCP_CFG_PATH} k create deployment quarkus --image=quay.io/rhdevelopers/quarkus-demo:v1
KUBECONFIG=${TEMP_DIR}/${KCP_CFG_PATH} k create service clusterip quarkus --tcp 80:8080
KUBECONFIG=${TEMP_DIR}/${KCP_CFG_PATH} k create ingress quarkus --class=nginx --rule="quarkus.${HOSTNAME_IP}.sslip.io/*=quarkus:80"

note ">> k rollout status deployment/quarkus"
KUBECONFIG=${TEMP_DIR}/${KCP_CFG_PATH} k rollout status deployment/quarkus

succeeded ">> Curl the ingress route using this address: http://quarkus.${HOSTNAME_IP}.sslip.io/"



