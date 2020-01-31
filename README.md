USER ACCESS TO K8S CLUSTER WITH CERTIFICATION 

  As you know kubernetes doesn't manage user. If you want a user to access the kubernetes cluster with appropriate privileges you can do it by several approaches. This script provide a user to access kubernetes cluster with certification method. Also this script creates the namespace if not exist. The only things must be done is copying kubeconfig file as user ~/.kube/config. 

REQUIREMENTS:
* You must run this script as admin of k8s cluster
* You must have jq tool installed. You can install jq by 'snap install jq'

NOTES: You can develop this script to create group rolebinding 

Good lock
