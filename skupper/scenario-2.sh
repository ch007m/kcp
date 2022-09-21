#!/usr/bin/env bash

#
# End to end scenario 2
#

: ${HOST_MACHINE:=1.1.1.1.sslip.io}
: ${NAMESPACE1:=west}
: ${NAMESPACE2:=east}

# Parameters to play the scenario
TYPE_SPEED=50
NO_WAIT=true

source ../common.sh
source ../play-demo.sh

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

pe "../kcp.sh clean"
pe "../kcp.sh install -v ${KCP_VERSION}"
pe "../kcp.sh start"

for VARIABLE in 1 2
do
 pe "kind delete cluster --name cluster${i}"
 echo "${kindCfg}" | kind create cluster --config=- --name cluster${i}

 p "Installing the ingress controller using Helm within the namespace: ingress for cluster${i}"
 pe "kubectl ctx kind-cluster${i}"
 pe "helm upgrade --install ingress-nginx ingress-nginx \
     --repo https://kubernetes.github.io/ingress-nginx \
     --namespace ingress --create-namespace \
     --set controller.service.type=NodePort \
     --set controller.hostPort.enabled=true"
done

tail -f ${TEMP_DIR}/kcp-output.log | while read LOGLINE
do
   [[ "${LOGLINE}" == *"finished bootstrapping root workspace phase 1"* ]] && pkill -P $$ tail
done
p "KCP is started :-)"

pe "KUBECONFIG=${TEMP_DIR}/${KCP_CFG_PATH} k workspaces create skupper-demo --enter"

for VARIABLE in 1 2
do
  pe "KUBECONFIG=${TEMP_DIR}/${KCP_CFG_PATH} k kcp workload sync cluster-1 --syncer-image ghcr.io/kcp-dev/kcp/syncer:release-0.7 --resources=services,sites.skupper.io,requiredservices.skupper.io,providedservices.skupper.io -o cluster${i}.yml"
done


