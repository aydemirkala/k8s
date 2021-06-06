#!/bin/bash



if [[ $1 == "-h" ]]
then
echo "usage: $0 <option> <suboption>"
echo "options:
create: create new user authentication via certificate, it creates user key, csr request, csr, crt file, namespace, role, rolebinding, kubeconfig
<suboptions for create>
--user=user_name 
--group=group_name
--namespace=namespace for user
delete: delete user csr, role, rolebinding, kubeconfig
<suboptions for delete>
--user=user_name 
--namespace=namespace for user
you need jq tool in order to use this script. You can download snap and install via snap install jq command
"
exit 1;
fi

userarg=$(echo $2 | cut -d"=" -f1)
export userarg
user=$(echo $2 | cut -d"=" -f2)
export user

grouparg=$(echo $3 | cut -d"=" -f1)
export grouparg
group=$(echo $3 | cut -d"=" -f2)
export group

nspacearg=$(echo $4 | cut -d"=" -f1)
export nspacearg
nspace=$(echo $4 | cut -d"=" -f2)
export nspace

clustername=$(kubectl config view --raw -o json | jq -r '.clusters[].name')
export clustername

clusterendpoint=$(kubectl config view --raw -o json | jq -r '.clusters[].cluster.server')
export clusterendpoint

clustercadata=$(kubectl config view --raw -o json | jq -r '.clusters[].cluster["certificate-authority-data"]' | tr -d '\n')
export clustercadata

if [[ $# == 4 ]]
then
	if [[ $1 == "create" && $user != "" && $group != "" && $nspace != "" && $userarg == "--user" && $grouparg == "--group" && $nspacearg == "--namespace" ]]
	then
	echo "Info: starting user authentication and authorization process...."

	echo "Info: Checking $user key file..."
		if [[ ! -e $user.key ]]
        	then
			echo "Info: Creating $user.key file..."
			openssl genrsa -out  $user.key 2048
		else
		echo "Info: $user.key file already exists"
		fi

		clientkeydata=$(cat $user.key | base64 | tr -d '\n')
		export clientkeydata

		echo "Info: Checking $user-csr.cnf file..."
		if [[ ! -e $user-csr.cnf ]]
		then
			echo "Info: Creating $user-csr.cnf file..."
			echo "
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
[ dn ]
CN = $user
O = $group
[ v3_ext ]
authorityKeyIdentifier=keyid,issuer:always
basicConstraints=CA:FALSE
keyUsage=keyEncipherment,dataEncipherment
extendedKeyUsage=serverAuth,clientAuth
" > $user-csr.cnf
		else
			echo "Info: $user-csr.cnf file already exists"
		fi

		echo "Info: Checking $user.csr file..."
		if [[ ! -e $user.csr ]]
		then
			echo "Info: Creating $user.csr file..."
			openssl req -config ./$user-csr.cnf -new -key $user.key -nodes -out $user.csr
		else
			echo "Info: $user.csr file already exists"
		fi
	
        	clientcsrdata=$(cat ./$user.csr | base64 | tr -d '\n')
		export clientcsrdata


		echo "Info: Checking $user-csr.yml..."
		if [[ ! -e $user-csr.yml ]]
		then
			echo "Info: Creating $user-csr.yml..."
			echo "
apiVersion: certificates.k8s.io/v1beta1
kind: CertificateSigningRequest
metadata:
  name: $user-csr
spec:
  groups:
  - system:authenticated
  request: ${clientcsrdata}
  usages:
  - digital signature
  - key encipherment
  - server auth
  - client auth
" > $user-csr.yml
		else
			echo "Info: $user-csr.yml already exists..."
		fi

		echo "Info: Checking $user-csr in kubernetes."
		kubectl get csr $user-csr > /dev/null 2>&1
		if [[ $? == 0 ]]
		then
			echo "Info: $user-csr exist in kubernetes cluster"
		else
			echo "Info: $user-csr doesn't exists in kubernetes cluster. Creating one..."
			kubectl create -f $user-csr.yml > /dev/null
		fi

		echo "Info: Checking $user-csr condition..."
       		 chk=$(kubectl get csr $user-csr | awk NR==2'{print $5}')
		if [[ $chk == "Pending" ]]
		then
			echo "Info: $user-csr condition is Pending. Approving it now ..."
			kubectl certificate approve $user-csr
		elif [[ $chk == "Approved,Issued" ]]
		then
			echo "Info: $user-csr condition is Approved,Issued"
		else
			exit 1;
		fi

		echo "Info: Checking $user.crt file..."
		if [[ ! -e $user.crt ]]
		then
			echo "Info: $user.crt file doesn't exists. Creating one.."
			kubectl get csr $user-csr -o jsonpath='{.status.certificate}' | base64 --decode > $user.crt
		else
			echo "Info: $user.crt file already exists"	
		fi
	
		clientcrtdata=$(cat ./$user.crt | base64 | tr -d '\n')
		export clientcrtdata


		echo "Info: Checking $nspace in kubernetes cluster"
		kubectl get namespaces $nspace > /dev/null
		if [[ $? == 0 ]]
		then
			echo "Info: $nspace already exists..."
		else
			echo "Info: Creating $nspace for $user..."
			kubectl create ns $nspace /dev/null
		fi

		echo "Info: Checking $user-role in cluster"
        	kubectl get roles --all-namespaces | awk '{print $2}' | grep $user-role	> /dev/null
		if [[ $? == 0 ]]
		then
			echo "Info: This role already exists. You may check it manually"
		else
			echo "Info: Creating $user-role.yml...."
			echo "
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
 namespace: $nspace
 name: $user-role
rules:
- apiGroups: [\"\"]
  resources: [\"pods\", \"services\",\"deployments\"]
  verbs: [\"create\", \"get\", \"update\", \"list\", \"delete\"]
" > $user-role.yml
			if [[ ! -e $user-role.yml ]]
			then
				echo "Error: $user-role.yml file is not accessible. Check it manually"
			else
				kubectl create -f $user-role.yml
			fi
			
		fi	

		echo "Info: Checking $user-rb in cluster"
		kubectl get rolebindings --all-namespaces | awk '{print $2}' | grep $user-rb > /dev/null
        	if [[ $? == 0 ]]
        	then
     	          	 echo "Info: This rolebinding already exists. You may check it manually"
       		else
                	echo "Info: Creating $user-rolebinding.yml...."
			echo "
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
 name: $user-rb
 namespace: $nspace
subjects:
- kind: User
  name: $user
  apiGroup: rbac.authorization.k8s.io
roleRef:
 kind: Role
 name: $user-role
 apiGroup: rbac.authorization.k8s.io
" > $user-rolebinding.yml
			if [[ ! -e $user-rolebinding.yml ]]
			then
				echo "Error: $user-rolebinding.yml file is not accessible. Check it manually"
			else
				kubectl create -f $user-rolebinding.yml
			fi

		fi
		echo "Info: Checking kubeconfig file..."
		if [[ ! -e kubeconfig ]]
		then
			echo "Info: kubeconfig file doesn't exists. Creating one..."
			echo "
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${clustercadata}
    server: ${clusterendpoint}
  name: ${clustername}
users:
- name: ${user}
  user:
    client-certificate-data: ${clientcrtdata}
    client-key-data: ${clientkeydata}
contexts:
- context:
    cluster: ${clustername}
    user: $user
    namespace: $nspace
  name: ${user}-${clustername}
current-context: ${user}-${clustername}
" > kubeconfig
		else
			echo "Info: kubeconfig file already exists.."
		fi

echo "############################################################"
echo "USER CONFIG FILE IS READY. YOU CAN COPY IT TO /home/$user/.kube/config"
echo "DONE"

	fi


elif [[ $# == 3 ]]
then
	echo "I am in delete"
	if [[ $1 == "delete" && $user != "" && $userarg == "--user" ]]
	then
		nspace=$(echo $3 | cut -d"=" -f2)
		nspacearg=$(echo $3 | cut -d"=" -f1)

		if [[ $nspace == "" && $nspacearg == "--namespace" ]]
		then
			echo "Error: namespace can not be empty"
			exit 1;
		else
			echo "Info: starting user delete process..."
			kubectl delete csr $user-csr > /dev/null 2>&1
			kubectl delete roles $user-role -n $nspace > /dev/null 2>&1
			kubectl delete rolebindings $user-rb -n $nspace  > /dev/null 2>&1
			rm -rf $user.key $user-csr.yml $user.csr $user.crt $user-csr.cnf kubeconfig $user-role.yml $user-rolebinding.yml
			echo "Info: Delete operatation completed..."
		fi
	fi
else
	echo "Error: Wrong input arguments"
fi
