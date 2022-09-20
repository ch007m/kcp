Table of Contents
=================

* [Table of Contents](#table-of-contents)
* [Introduction](#introduction)
* [KCP scenario](#kcp-scenario)
  * [Prerequisite](#prerequisite)
  * [How to play with kcp](#how-to-play-with-kcp)
  * [Scenario 1 : One workspace](#scenario-1--one-workspace)
  * [Scenario 2 : One workspace but 2 physical clusters](#scenario-2--one-workspace-but-2-physical-clusters)
  * [Scenario 3 : One workspace with additional CRDs (ingress, service)](#scenario-3--one-workspace-with-additional-crds-ingress-service)
* [Skupper](#skupper)
  * [Scenario 1 : Getting started](#scenario-1--getting-started)

# Introduction

This project has been designed in order to evaluate [kcp](https://github.com/kcp-dev/kcp) like [skupper](https://skupper.io) and how they could be used together

In order to play with [kcp](https://github.com/kcp-dev/kcp) it is needed to install different tools: kcp, kubectl kcp plugins and launch it.
Next, you can create workspaces and start to setup logical clusters that kcp will manage on physical clusters.

# KCP scenario

This section covers different scenario which have been tested with kcp and that you could play using either the manual or the end-to-end bash script.
They gradually increase the complexity to validate a deployment across multiple clusters, using more API (ingress, service).

Remark: When you plan to use the end-to-end `scenario-*.sh` bash script in a terminal, it is possible to specify different parameters.
Use the arg `-h` to get the help: `scenario-*.sh -h`.


## Prerequisite

- [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) is installed (if you plan to use a kind k8s cluster)
- A k8s cluster is up and running (e.g `kind create cluster`, ...)
- [kubectx](https://github.com/ahmetb/kubectx)
- [helm installed](https://helm.sh/docs/intro/install/) 

## How to play with kcp

To simplify our life when we play with the kcp server, we have developed the bash script `./kcp.sh` able to support the following actions:
```bash
Usage:
  ./kcp.sh <command> [args]

Commands:
    install     Install the kcp server locally and kcp kubectl plugins
    start       Start the kcp server
    stop        Stop the kcp server
    status      Check if KCP is well started
    syncer      Generate and install the syncer component top of a k8s cluster
    clean       Clean up the temp directory and remove the kcp plugins

Arguments:
    -v          Version to be installed of the kcp server. Default: `0.8.2`
    -t          Temporary folder where kcp will be installed. Default: `_tmp`
    -c          Name of the k8s cluster where syncer is installed. Default: `kind`
    -w          Workspace to sync resources between kcp and target cluster. Default: `root:my-org`
    -r          Additional resources to be be sync with the physical cluster.
```
**Remark**: The log of the kcp server started is available at <TEMP_DIR>/kcp-output.log

## Set up

### Clean up 

If you come from an old installation, you can perform a clean up by running the following commands, otherwise jump to [next step]():

```bash
./kcp.sh clean
kind delete cluster --name cluster1
```

### Create a physical cluster and install `kcp`

We need a physical cluster backing the kcp server that we will create locally using `Kind`. 
 
```bash
kind create cluster --name cluster1
```
Then, we will instal `Kcp` itself:

```bash
./kcp.sh install -v 0.8.2
./kcp.sh start
```
You can check the status of the kcp server and verify it is started:

```bash
./kcp.sh status
```

And finally install the [syncer](https://github.com/kcp-dev/kcp/blob/main/docs/syncer.md) in order to allow kcp server to communicate with the physical Kubernetes cluster. To do so, run the following command:

```bash
./kcp.sh syncer -w $WORKSPACE -c cluster1
```
Note that the default value for $WORKSPACE is `my-org` it will be created under the `root` org level (root:my-org)

Next, you can execute one of the following scenarios described hereafter.

## Scenario 1 : One workspace

Objective: 
- Create a kcp workspace `root:my-org` and move the context to this workspace, 
- Deploy a Quarkus application within the workspace, 
- Access the application deployed on the physical cluster (e.g: kubectl proxy)
- Move the workspace one level up (e.g `root`) and verify that no deployments exist as workspaces are isolated

Make sure to use kubeconfig for your local KCP, for this use the configuration generated during the installation:

```bash
export KUBECONFIG=$TMP/.kcp/admin.kubeconfig
```
Set the $TMP according to your kcp installation.

## Step-by-Step

Verify you have a kcp server up and running
````bash
./kcp.sh status
````

### Use a kcp workspace
Be sure that you are using the correct workspace:

```bash
kubectl kcp ws use root:$WORKSPACE
```
Note that `$WORKSPACE` needs to point to the workspace used for creating the `syncer`.

### Deploy a Quarkus application

We deploy a Quarkus application from a predefined image

```bash

kubectl create deployment quarkus --image=quay.io/rhdevelopers/quarkus-demo:v1

```

### Check that deploy went well

First, inspect the status of the rollout by running:

```bash
kubectl rollout status deployment/quarkus

```

Then, check deployments availables in the current workspace, you should have the quarkus one:
```bash
kubectl get deployments
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
quarkus   1/1     1            1           16h
```

### Change to another workspace and verify that no deployments exist

You can move to the parent workspace which is `root`:
```bash
kubectl kcp ws use ..
``` 
Verify that there is no deployments in the current workspace:

```bash
kubectl get deployments                                                                                                               
error: the server doesn't have a resource type "deployments"
```

### End-to-end script

To execute the scenario end to end, launch in a terminal the following script: `./scenario-1.sh`. If it succeeds, then you will see the following messages:

![](img/kcp_demo_log.png)

## Scenario 2 : One workspace but 2 physical clusters

Objective: This scenario is an extension of the previous as we continue to use 1 workspace but where we would like to place the deployment on 2 distinct physical clusters. 
When we will deploy an application, it will be deployed on both clusters as kcp will use the [matching mechanism](https://github.com/kcp-dev/kcp/blob/main/pkg/apis/scheduling/v1alpha1/types_placement.go#L64-L67) to find for a placement,
its location and ultimately the syncTarget related to the [locations](https://github.com/kcp-dev/kcp/blob/main/pkg/apis/scheduling/v1alpha1/types_location.go#L32-L37) and used to sync the resources with the physical clusters.

**Warning**: As the command `kubectl kcp workload sync <cluster_name>` only create 1 `Placement` and 1 `Location` CRDs for the target cluster `<cluster_name>`,
it is then needed to perform some manual steps to create a 2nd placement and Location and to edit the `Synctarget` to use labels able to match the corresponding
resources

Example:

```yaml
apiVersion: scheduling.kcp.dev/v1alpha1
kind: Placement
metadata:
  annotations:
    kcp.dev/cluster: root:my-org
  name: blue
spec:
  locationResource:
    group: workload.kcp.dev
    resource: synctargets
    version: v1alpha1
  locationSelectors:
    - matchLabels:
        color: blue # Location Label to match
 ...       

apiVersion: scheduling.kcp.dev/v1alpha1
kind: Location
metadata:
  annotations:
    kcp.dev/cluster: root:my-org
  labels:
    color: blue
  name: blue
spec:
  instanceSelector:
    matchLabels:
      color: blue # Synctarget label to match
  resource:
    group: workload.kcp.dev
    resource: synctargets
    version: v1alpha1
```
### Step-by-Step
TODO

### End-to-end script

TODO

## Scenario 3 : One workspace with additional CRDs (ingress, service)

Objective: The purpose of this scenario is to create a workspace, configure kcp to be able to sync additional resources such as: Ingress, Services and finally to deploy a Quarkus application.

### Step-by-Step

TODO

The additional k8s resources are passed to the kcp.sh script using this command:
```bash
./kcp.sh syncer -w my-org -c cluster1 -r ingresses.networking.k8s.io,services
```
If the deployment succeeds, then you will be able to see these messages logged if you execute the end to end scenario `hostname_ip=<IP> ./scenario-3.sh`
```text
NOTE: >> k create deployment quarkus --image=quay.io/rhdevelopers/quarkus-demo:v1
deployment.apps/quarkus created
service/quarkus created
ingress.networking.k8s.io/quarkus created
```
And next, if you have passed to the script the IP address of the VM running the physical cluster, then you should be able to consume the ingress route using the URL
```text
curl http://quarkus.<IP>.sslip.io/
```

### End-to-end script

TODO

# Skupper

## Prerequisite

- [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation) is installed (if you plan to use a kind k8s cluster)
- [skupper client](https://skupper.io/docs/cli/index.html)
- [kcp](https://github.com/kcp-dev/kcp#download-kcp)

## Scenario 1 : Getting started

See: https://skupper.io/start/index.html

### End-to-end script

To execute the scenario top of a kind cluster, open a terminal and execute the following script
where you pass as env var the IP address of your local machine running the cluster:

`HOST_MACHINE=<IP> ./skupper/scenario-1.sh`.

**Remark**: The `HOST_NAME` will be used to configure the ingress routes to access the `skupper` console and frontend. Check the messages logged to get the URLs ;-)

![](img/skupper-scenario-1.png)

If the frontend can access the backend service, then you should be able to see such `Hello world` messages wihin yiur browser

![](img/skupper_frontend_scenario-1.png)


