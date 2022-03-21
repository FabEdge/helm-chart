#!/bin/bash

set -e

function usage() {
    echo "Deploy fabedge."
    echo ""
    echo "examples:"
    echo "curl 116.62.127.76/installer/latest/install.sh  | bash -s -- --cluster-name beijing  --cluster-role host --cluster-zone beijing  --cluster-region haidian --connectors node1 --connector-public-addresses 10.22.46.32 --chart http://116.62.127.76/fabedge-0.5.0.tgz"
    echo "curl 116.62.127.76/installer/latest/install.sh  | bash -s -- --cluster-name openyurt2 --cluster-role member --cluster-zone beijing  --cluster-region haidian --connectors node1 --chart http://116.62.127.76/fabedge-0.5.0.tgz --server-serviceHub-api-server https://10.22.46.47:30304 --host-operator-api-server https://10.22.46.47:30303 --connector-public-addresses 10.22.46.26 --init-token ey...Jh"
    echo ""
    echo "common options:"
    echo "  --cluster-name <string>: The cluster name must be unique."
    echo "  --cluster-role [host|member]: The first cluster in FabEdge scope must be host cluster."
    echo "  --cluster-region <string>: service-hub region"
    echo "  --cluster-zone <string>: service-hub zone"
    echo "  --cluster-cidr <string>: kubernetes --cluster-cidr"
    echo "  --service-cluster-ip-range <string>: kubernetes --service-cluster-ip-range"
    echo "  --edge-labels []: To label all edge node. default: node-role.kubernetes.io/edge="
    echo "  --connectors []: node name"
    echo "  --connector-labels []: To label all connector node. default: node-role.kubernetes.io/connector="
    echo "  --connector-public-addresses []"
    echo "  --chart <string>"
    echo "host options:"
    echo "  --operator-nodeport <int>: default: 30303"
    echo "  --servicehub-nodeport <int>: default: 30304"
    echo "member options:"
    echo "  --host-operator-api-server <string>"
    echo "  --server-serviceHub-api-server <string>"
    echo "  --init-token <string>"
    echo "  --namespace <string>: default: fabedge"
    exit 1
}

KUBERNETES_PROVIDER="$(test -f /etc/systemd/system/k3s.service && echo k3s || echo kubernetes)"

initArch() {
  ARCH=$(uname -m)
  case $ARCH in
    armv5*) ARCH="armv5";;
    armv6*) ARCH="armv6";;
    armv7*) ARCH="arm";;
    aarch64) ARCH="arm64";;
    x86) ARCH="386";;
    x86_64) ARCH="amd64";;
    i686) ARCH="386";;
    i386) ARCH="386";;
  esac
}

# initOS discovers the operating system for this system.
initOS() {
  OS=$(echo `uname`|tr '[:upper:]' '[:lower:]')

  case "$OS" in
    # Minimalist GNU for Windows
    mingw*|cygwin*) OS='windows';;
  esac
}


function getKubernetesInfo() {
    clusterCIDR=$(grep -r cluster-cidr /etc/kubernetes/ | awk -F '=' 'END{print $NF}')
    serviceClusterIPRange=$(grep -r service-cluster-ip-range /etc/kubernetes/ | awk -F '=' 'END{print $NF}')

    if [ x"$clusterCIDR" = x"" -o x"$serviceClusterIPRange" = x"" ]; then
        while read line
        do
            if [[ "$line" =~ \"--cluster-cidr=.* ]];
            then
                clusterCIDR=`awk -F '["=]' '{print $3}' <<< $line`
            elif [[ "$line" =~ \"--service-cluster-ip-range=.* ]];
            then
                serviceClusterIPRange=`awk -F '["=]' '{print $3}' <<< $line`
            fi
        done <<< "`kubectl cluster-info dump | awk '(/cluster-cidr/ || /service-cluster-ip-range/) && !a[$0]++{print}'`"
    fi
}


function getK3sInfo() {
    # k3s server --help
    clusterCIDR=10.42.0.0/16
    serviceClusterIPRange=10.43.0.0/16

    while read line
    do
       if [[ $line == ExecStart=* ]];
       then
           args=($line)
           for i in "${!args[@]}";
           do
               key=$(echo ${args[$i]} | sed 's/\"//g' | sed $'s/\'//g')
               if [[ $key == --cluster-cidr ]];
               then
                   let i++
                   clusterCIDR=$(echo ${args[$i]} | sed 's/\"//g' | sed $'s/\'//g')
               fi
               if [[ $key == --service-cidr ]];
               then
                   let i++
                   serviceClusterIPRange=$(echo ${args[$i]} | sed 's/\"//g' | sed $'s/\'//g')
               fi
           done
       fi
    done < /etc/systemd/system/k3s.service
}

function setDefaultArgs() {
    if [ x"$clusterRole" == xhost ]; then
        clusterMode=server
    else
        clusterMode=client
    fi
    if [ x"$clusterCIDR" = x"" -o x"$serviceClusterIPRange" = x"" ]; then
        if [ "${KUBERNETES_PROVIDER}" == "k3s" ]; then
            getK3sInfo
        else
            getKubernetesInfo
        fi
    fi
    if [ x"$namespace" == x ]; then
        namespace="fabedge"
    fi
    if [ x"$edgeLabels" == x ]; then
        edgeLabels=(node-role.kubernetes.io/edge=)
    fi
    if [ x"$connectorLabels" == x ]; then
        connectorLabels=(node-role.kubernetes.io/connector=)
    fi
    if [ x"$operatorNodePort" == x ]; then
        operatorNodePort=30303
    fi
    if [ x"$serviceHubNodePort" == x ]; then
        serviceHubNodePort=30304
    fi
}

function validateArgs() {
    error=0
    if [ x"$clusterName" == x ]; then
        error=1
        echo 'required option "--cluster-name" not set'
    fi
    if [ x"$clusterRole" == x ]; then
        error=1
        echo 'required option "--cluster-role" not set'
    elif [ x"$clusterRole" != x"member" -a x"$clusterRole" != x"host" ]; then
        error=1
        echo "invalid option value: --cluster-role $clusterRole: must be one of 'host' and 'member'"
    fi
    if [ x"$clusterRegion" == x ]; then
        error=1
        echo 'required option "--cluster-region" not set'
    fi
    if [ x"$clusterZone" == x ]; then
        error=1
        echo 'required option "--cluster-zone" not set'
    fi
    if [ x"$clusterCIDR" = x"" ]; then
        error=1
        echo 'required option "--cluster-cidr" not set'
    fi
    if [ x"$serviceClusterIPRange" = x"" ]; then
        error=1
        echo 'required option "--service-cluster-ip-range" not set'
    fi
    if [ x"$connectors" == x ]; then
        error=1
        echo 'required option "--connectors" not set'
    fi
    if [ x"$connectorPublicAddresses" == x ]; then
        error=1
        echo 'required option "--connector-public-addresses" not set'
    fi
    if [ x"$chart" == x ]; then
        error=1
        echo 'required option "--chart" not set'
    fi
    if [ x"$clusterRole" == xmember ]; then
        if [ x"$hostOperatorAPIServer" == x ]; then
            error=1
            echo 'required option "--host-operator-api-server" not set'
        fi
        if [ x"$serverServiceHubAPIServer" == x ]; then
            error=1
            echo 'required option "--server-serviceHub-api-server" not set'
        fi
        if [ x"$initToken" == x ]; then
            error=1
            echo 'required option "--init-token" not set'
        fi
    elif [ x"$clusterRole" == xhost ]; then
        if [ x"$operatorNodePort" == x ]; then
            error=1
            echo 'required option "--operator-nodeport" not set'
        fi
        if [ x"$serviceHubNodePort" == x ]; then
            error=1
            echo 'required option "--servicehub-nodeport" not set'
        fi
    fi
    if [ $error == 1 ]; then
        exit
    fi
}

function parseArgs() {
    if [ $# == 0 ]; then
        usage
    fi

    while [ $# -gt 0 ]; do
        case $1 in
            -h|--help)
                usage
                ;;
            --cluster-name)
                clusterName=$2
                shift 2
                ;;
            --namespace)
                namespace=$2
                shift 2
                ;;
            --cluster-role)
                clusterRole=$2
                shift 2
                ;;
            --cluster-region)
                clusterRegion=$2
                shift 2
                ;;
            --cluster-zone)
                clusterZone=$2
                shift 2
                ;;
            --cluster-cidr)
                clusterCIDR=$2
                shift 2
                ;;
            --service-cluster-ip-range)
                serviceClusterIPRange=$2
                shift 2
                ;;
            --edge-labels)
                edgeLabels=($(echo $2 | sed 's/,/ /g'))
                shift 2
                ;;
            --connector-labels)
                connectorLabels=($(echo $2 | sed 's/,/ /g'))
                shift 2
                ;;
            --connectors)
                connectors=($(echo $2 | sed 's/,/ /g'))
                shift 2
                ;;
            --connector-public-addresses)
                connectorPublicAddresses=($(echo $2 | sed 's/,/ /g'))
                shift 2
                ;;
            --host-operator-api-server)
                hostOperatorAPIServer=$2
                shift 2
                ;;
            --server-serviceHub-api-server)
                serverServiceHubAPIServer=$2
                shift 2
                ;;
            --init-token)
                initToken=$2
                shift 2
                ;;
            --operator-nodeport)
                operatorNodePort=$2
                shift 2
                ;;
            --servicehub-nodeport)
                serviceHubNodePort=$2
                shift 2
                ;;
            --chart)
                chart=$2
                shift 2
                ;;
            *)
		echo "unknown option: $1"
		exit 3
                ;;
        esac
    done
}

function installHelm() {
    #curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash -
    TAG=v3.8.0
    HAS_CURL="$(type "curl" &> /dev/null && echo true || echo false)"
    HAS_WGET="$(type "wget" &> /dev/null && echo true || echo false)"
    if ! helm version > /dev/null 2>&1; then
        if [ "${HAS_CURL}" == "true" ]; then
            curl -o /tmp/helm-${TAG}-${OS}-${ARCH}.tar.gz https://get.helm.sh/helm-${TAG}-${OS}-${ARCH}.tar.gz
        elif [ "${HAS_WGET}" == "true" ]; then
            wget -O /tmp/helm-${TAG}-${OS}-${ARCH}.tar.gz https://get.helm.sh/helm-${TAG}-${OS}-${ARCH}.tar.gz
        else
            echo "Either curl or wget is required"
            exit 1
        fi

        tar fx /tmp/helm-${TAG}-${OS}-${ARCH}.tar.gz -C /tmp/
        cp -f /tmp/${OS}-${ARCH}/helm /usr/local/bin/helm

    fi
}

function labelNodes() {
    for connector in ${connectors[*]}; do
        for label in ${connectorLabels[*]}; do
            kubectl label node --overwrite=true $connector $label
        done
    done
}

function patchCNINodeAffinity() {
    if  [ "${KUBERNETES_PROVIDER}" == "k3s" ]; then
        return
    fi

cat > /tmp/cni-ds.patch.yaml << EOF
spec:
  template:
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.io/os
                operator: In
                values:
                - linux
EOF
    for label in ${edgeLabels[*]}; do
        echo "              - key: $(awk -F '=' '{print $1}' <<< $label)" >> /tmp/cni-ds.patch.yaml
        echo "                operator: DoesNotExist" >> /tmp/cni-ds.patch.yaml
    done

    while read line; do
        if [[ $line =~ flannel ]]; then
            kubectl patch ds -n kube-system kube-flannel-ds --patch "$(cat /tmp/cni-ds.patch.yaml)"
            return
        elif [[ $line =~ calico ]]; then
            kubectl patch ds -n kube-system calico-node --patch "$(cat /tmp/cni-ds.patch.yaml)"
            return
        fi
    done <<< $(kubectl get pods -A)

    echo 'Could not find calico or flannel pod'
    exit 2
}

deployFabEdge() {
    # convert shell list (label1, label2, label3) to "{label1, label2, label3}"
    valuesEdgeLabels=$(echo "${edgeLabels[*]}" | awk 'BEGIN{printf "{"}{for(i=1; i<=NF; i++){if(i == NF)printf $i; else printf $i", "}}END{printf "}"}')
    valuesConnectorLabels=$(echo "${connectorLabels[*]}" | awk 'BEGIN{printf "{"}{for(i=1; i<=NF; i++){if(i == NF)printf $i; else printf $i", "}}END{printf "}"}')
    valuesConnectorPublicAddresses=$(echo "${connectorPublicAddresses[*]}" | awk 'BEGIN{printf "{"}{for(i=1; i<=NF; i++){if(i == NF)printf $i; else printf $i", "}}END{printf "}"}')
    # helm get values <release-name>

    if [ x"$clusterRole" == x"host" ]; then
        helm install fabedge --create-namespace -n $namespace --set cluster.name=$clusterName,cluster.role=$clusterRole,cluster.region=$clusterRegion,cluster.zone=$clusterZone,cluster.cidr=$clusterCIDR,cluster.serviceClusterIPRange=$serviceClusterIPRange,cluster.connectorPublicAddresses=$valuesConnectorPublicAddresses,cluster.edgeLabels=$valuesEdgeLabels,cluster.connectorLabels=$valuesConnectorLabels,serviceHub.service.nodePort=$serviceHubNodePort,operator.service.nodePort=$operatorNodePort,serviceHub.mode=$clusterMode $chart
    elif [ x"$clusterRole" == x"member" ]; then
        helm install fabedge --create-namespace -n $namespace --set cluster.name=$clusterName,cluster.role=$clusterRole,cluster.region=$clusterRegion,cluster.zone=$clusterZone,cluster.cidr=$clusterCIDR,cluster.serviceClusterIPRange=$serviceClusterIPRange,cluster.connectorPublicAddresses=$valuesConnectorPublicAddresses,cluster.edgeLabels=$valuesEdgeLabels,cluster.connectorLabels=$valuesConnectorLabels,cluster.hostOperatorAPIServer=$hostOperatorAPIServer,cluster.serverServiceHubAPIServer=$serverServiceHubAPIServer,cluster.initToken=$initToken,serviceHub.mode=$clusterMode $chart
    fi
}

parseArgs $*
setDefaultArgs
validateArgs

initArch
initOS
installHelm
labelNodes
patchCNINodeAffinity
deployFabEdge
