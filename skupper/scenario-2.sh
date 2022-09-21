#!/usr/bin/env bash

#
# End to end scenario 2
#

: ${HOST_MACHINE:=1.1.1.1.sslip.io}

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

#pe "../kcp.sh clean"
#pe "../kcp.sh install -v ${KCP_VERSION}"
pe "../kcp.sh start"

tail -f ${TEMP_DIR}/kcp-output.log | while read LOGLINE
do
   [[ "${LOGLINE}" == *"finished bootstrapping root workspace phase 1"* ]] && pkill -P $$ tail
done
p "KCP is started :-)"

for i in 1 2
do
 pe "kind delete cluster --name cluster${i}"

 if [ "$i" == 1 ];then
   p "Creating a kind cluster named cluster${i} where ingress is deployed"
   echo "${kindCfg}" | kind create cluster --config=- --name cluster${i}

   p "Installing the ingress controller using Helm within the namespace: ingress for cluster${i}"
   pe "k ctx kind-cluster${i}"
   pe "helm upgrade --install ingress-nginx ingress-nginx \
       --repo https://kubernetes.github.io/ingress-nginx \
       --namespace ingress --create-namespace \
       --set controller.service.type=NodePort \
       --set controller.hostPort.enabled=true"
 else
   kind create cluster --name cluster${i}
 fi

done

pe "KUBECONFIG=${TEMP_DIR}/${KCP_CFG_PATH} k workspaces create skupper-demo --enter"

for i in 1 2
do
  pe "KUBECONFIG=${TEMP_DIR}/${KCP_CFG_PATH} k kcp workload sync cluster-${i} --syncer-image ghcr.io/kcp-dev/kcp/syncer:release-0.7 --resources=services,sites.skupper.io,requiredservices.skupper.io,providedservices.skupper.io,ingresses.networking.k8s.io,services -o ${TEMP_DIR}/cluster${i}.yml"
  pe "k ctx kind-cluster${i}"
  pe "k apply -f ${TEMP_DIR}/cluster${i}.yml"
  p "Installing the Skupper CRDs & site controller"
  pe "k apply -f ./k8s/skupper-crds.yaml"
  pe "k apply -f ./k8s/skupper-site-controller.yaml"
done

p "Label the synctarget with category=one|two"
pe "KUBECONFIG=${TEMP_DIR}/${KCP_CFG_PATH} k label synctarget/cluster-1 category=one"
pe "KUBECONFIG=${TEMP_DIR}/${KCP_CFG_PATH} k label synctarget/cluster-2 category=two"

p "Deploy the location & placement able to map the sync target clusters"
pe "KUBECONFIG=${TEMP_DIR}/${KCP_CFG_PATH} k apply -f ./k8s/locations.yaml"
pe "KUBECONFIG=${TEMP_DIR}/${KCP_CFG_PATH} k apply -f ./k8s/placements.yaml"

p "Hack step"
pe "KUBECONFIG=${TEMP_DIR}/${KCP_CFG_PATH} k delete location default"
pe "KUBECONFIG=${TEMP_DIR}/${KCP_CFG_PATH} k delete placement default"

p "Install the skupper network controller"
pe "KUBECONFIG=${TEMP_DIR}/${KCP_CFG_PATH} k rollout status deployment/skupper-site-controller -n skupper-site-controller"
pe "KUBECONFIG=${TEMP_DIR}/${KCP_CFG_PATH} k apply -f ./k8s/skupper-network-controller.yaml"

p "Creating 2 namespaces: one and two"
pe "KUBECONFIG=${TEMP_DIR}/${KCP_CFG_PATH} k apply -f ./k8s/namespaces.yaml"

p "Deploying the bookinfo application: product page part"
pe "KUBECONFIG=${TEMP_DIR}/${KCP_CFG_PATH} k apply -f ./k8s/bookinfo_one.yaml -n one"
p "Deploying the bookinfo application: details page part"
pe "KUBECONFIG=${TEMP_DIR}/${KCP_CFG_PATH} k apply -f ./k8s/bookinfo_two.yaml -n two"

p "Registering the bookinfo services for details, reviews, ratings"
pe "KUBECONFIG=${TEMP_DIR}/${KCP_CFG_PATH} k apply -f ./k8s/bookinfo_one_skupper.yaml -n one"
pe "KUBECONFIG=${TEMP_DIR}/${KCP_CFG_PATH} k apply -f ./k8s/bookinfo_two_skupper.yaml -n two"

p "Expose the bookinfo as ingress route to access it externally on the cluster1"
pe "KUBECONFIG=${TEMP_DIR}/${KCP_CFG_PATH} k create ingress bookinfo --class=nginx --rule=\"bookinfo.${HOST_MACHINE}/*=productpage:9080\" -n one"