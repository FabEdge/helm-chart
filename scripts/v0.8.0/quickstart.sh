#!/bin/bash

set -e

function usage() {
    echo "Deploy fabedge."
    echo ""
    echo "examples:"
    echo "curl quickstart.sh  | bash -s -- --cluster-name beijing  --cluster-role host --cluster-zone beijing  --cluster-region haidian --connectors node1 --connector-public-addresses 10.22.46.32 --chart http://116.62.127.76/fabedge-0.5.0.tgz"
    echo "curl quickstart.sh  | bash -s -- --cluster-name openyurt2 --cluster-role member --cluster-zone beijing  --cluster-region haidian --connectors node1 --chart http://116.62.127.76/fabedge-0.5.0.tgz --server-serviceHub-api-server https://10.22.46.47:30304 --host-operator-api-server https://10.22.46.47:30303 --connector-public-addresses 10.22.46.26 --init-token ey...Jh"
    echo ""
    echo "common options:"
    echo "  --cluster-name <string>: The name of cluster, must be unique among all clusters and be a valid dns name(RFC 1123)"
    echo "  --cluster-role [host|member]: The role of cluster, possible values are: host, member. The first cluster in FabEdge must be host cluster"
    echo "  --cluster-region <string>: The region where the cluster is located, a region name may contain the letters ‘a-z’ or ’A-Z’ or digits 0-9"
    echo "  --cluster-zone <string>: The zone where the cluster is located, a zone name may contain the letters ‘a-z’ or ’A-Z’ or digits 0-9"
    echo "  --cni-type <string>: Specify the CNI used in your cluster, only flannel and calico is supported at present"
    echo "  --edge-pod-cidr <string>: Specify range of IPv4 addresses for the edge pod. If set, fabedge-operator will automatically allocate CIDRs for every edge node, configure this when you use calico and want to use IPv4"
    echo "  --edge-cidr-mask-size <string>: Set the mask size for IPv4 edge node cidr in dual-stack cluster, default: 24"
    echo "  --cluster-cidr <string>: The value of cluster-cidr parameter of kubernetes cluster"
    echo "  --service-cluster-ip-range <string>: The value of service-cluster-ip-range parameter of kubernetes cluster"
    echo "  --edges []: The name list of edge nodes, comma seperated, e.g. edge1,edge2"
    echo "  --connectors []: The name of node on which connection will run, comma seperated, e.g. node1,node2"
    echo "  --connector-public-addresses []: public IP addresses of connector which should be accessible by the edge nodes"
    echo "  --connector-public-port: public port of connector which used by edge nodes to establish tunnel"
    echo "  --connector-as-mediator: whether use connector as mediator for hole punching"
    echo "  --connector-node-addresses []: the internal IP addresses of connector nodes, prefer IPv4."
    echo "  --enable-proxy <bool>: whether use kube-proxy on edge node, if the cluster has kubeedge, it's better set it to true"
    echo "  --enable-dns <bool>: whether use coredns on edge node, if the cluster has kubeedge, it's better set it to true"
    echo "  --enable-fabdns <bool>: whether use fabDNS, set it to true if you need it. Default: true."
    echo "  --auto-keep-ippools <bool>: whether let fabedge-operator to keep ippools, this will save you from manually configuring ippools of CIDRs of other clusters. Default: true"
    echo "  --chart <string>"
    echo "host options:"
    echo "  --operator-nodeport <int>: default: 30303"
    echo "  --servicehub-nodeport <int>: default: 30304"
    echo "member options:"
    echo "  --operator-api-server <string>"
    echo "  --service-hub-api-server <string>"
    echo "  --init-token <string>"
    echo "  --namespace <string>: default: fabedge"
    exit 1
}

KUBERNETES_PROVIDER="$(test -f /etc/systemd/system/k3s.service && echo k3s || echo kubernetes)"

function getCNIType() {
  echo "finding cni in use..."
  for name in $(kubectl get ds -A | awk '{ print $2 }')
  do
    if [[ $name =~ "flannel" ]]; then
      cniType=flannel
    elif [[  $name =~ "calico"  ]]; then
      cniType=calico
    fi
  done
}

function getClusterCIDR() {
  if [ "${KUBERNETES_PROVIDER}" == "k3s" ]; then
      getK3sClusterCIDR
  else
      clusterCIDR=$(grep -r "cluster-cidr=" /etc/kubernetes/ | awk -F '=' 'END{print $NF}')
  fi
}

function getK3sClusterCIDR() {
    # 10.42.0.0/16 is the default cluster-cidr of k3s
    clusterCIDR=10.42.0.0/16
    while read line
    do
       if [[ $line == ExecStart=* ]];
       then
           args=($line)
           for i in "${!args[@]}";
           do
               key=$(echo ${args[$i]} | sed 's/\"//g' | sed $'s/\'//g')
               if [[ $key == "--cluster-cidr" ]];
               then
                   let i++
                   clusterCIDR=$(echo ${args[$i]} | sed 's/\"//g' | sed $'s/\'//g')
               fi
           done
       fi
    done < /etc/systemd/system/k3s.service
}

function getServiceClusterIPRange() {
  if [ "${KUBERNETES_PROVIDER}" == "k3s" ]; then
      getK3sServiceClusterIPRange
  else
      serviceClusterIPRange=$(grep -r "service-cluster-ip-range=" /etc/kubernetes/ | awk -F '=' 'END{print $NF}')
  fi
}

function getK3sServiceClusterIPRange() {
    # 10.43.0.0/16 is the default service-cluster-ip-range of k3s
    serviceClusterIPRange=10.43.0.0/16
    while read line
    do
       if [[ $line == ExecStart=* ]];
       then
           args=($line)
           for i in "${!args[@]}";
           do
               key=$(echo ${args[$i]} | sed 's/\"//g' | sed $'s/\'//g')
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
    namespace=${namespace:-fabedge}
    edgeCIDRMaskSize=${edgeCIDRMaskSize:-24}
    operatorNodePort=${operatorNodePort:-30303}
    serviceHubNodePort=${serviceHubNodePort:-30304}
    enableFabDNS=${enableFabDNS:-true}
    autoKeepIPPools=${autoKeepIPPools:-true}
    if [ x"$cniType" == x ]; then
      getCNIType
    fi

    if [ x"$connectorNodeAddresses" == x ]; then
        connectorNodeAddresses=()
    fi

    if [ x"$connectorPublicPort" == x ]; then
        connectorPublicPort=500
    fi

    if [ x"$connectorAsMediator" == x ]; then
        connectorAsMediator=false
    fi

    if [ x"$enableProxy" == x ]; then
      name=$(kubectl get ns kubeedge 2>/dev/null | grep kubeedge | awk '{ print $1 }')
      if [ x"$name" == x"kubeedge" ]; then
        enableProxy=true
      else
        enableProxy=false
      fi
    fi

    if [ x"$enableDNS" == x ]; then
      name=$(kubectl get ns kubeedge 2>/dev/null | grep kubeedge | awk '{ print $1 }')
      if [ x"$name" == x"kubeedge" ]; then
        enableDNS=true
      else
        enableDNS=false
      fi
    fi

    if [ x"$clusterCIDR" = x"" ]; then
        getClusterCIDR
    fi

    if [ x"$serviceClusterIPRange" = x"" ]; then
        getServiceClusterIPRange
    fi
}

function validateArgs() {
    error=0
    if [ x"$clusterName" == x ]; then
        error=1
        echo 'required option "--cluster-name" not set'
    fi

    if [ x"$cniType" == x ]; then
        error=1
        echo "couldn't recognize CNI in current cluster, please provide cni using --cni-type your-cni-type"
    elif [ x"$cniType" == x"calico" ] && [ x"$edgePodCIDR" == x ]; then
        error=1
        echo 'required option "--edge-pod-cidr" not set'
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
        if [ x"$operatorAPIServer" == x ]; then
            error=1
            echo 'required option "--operator-api-server" not set'
        fi
        if [ x"$serviceHubAPIServer" == x ]; then
            error=1
            echo 'required option "--service-hub-api-server" not set'
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
            --namespace)
                namespace=$2
                shift 2
                ;;
            --cluster-name)
                clusterName=$2
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
            --cni-type)
                cniType=$2
                shift 2
                ;;
            --edge-pod-cidr)
                edgePodCIDR=$2
                shift 2
                ;;
            --edge-cidr-mask-size)
                edgeCIDRMaskSize=$2
                shift 2
                ;;
            --cluster-cidr)
                clusterCIDR=($(echo $2 | sed 's/,/ /g'))
                shift 2
                ;;
            --service-cluster-ip-range)
                serviceClusterIPRange=($(echo $2 | sed 's/,/ /g'))
                shift 2
                ;;
            --edges)
                edges=($(echo $2 | sed 's/,/ /g'))
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
            --connector-public-port)
                connectorPublicPort=$2
                shift 2
                ;;
            --connector-node-addresses)
                connectorNodeAddresses=($(echo $2 | sed 's/,/ /g'))
                shift 2
                ;;
            --connector-as-mediator)
                connectorAsMediator=$2
                shift 2
                ;;
            --enable-proxy)
                enableProxy=$2
                shift 2
                ;;
            --enable-dns)
                enableDNS=$2
                shift 2
                ;;
            --enable-fabdns)
                enableFabDNS=$2
                shift 2
                ;;
            --auto-keep-ippools)
                autoKeepIPPools=$2
                shift 2
                ;;
            --operator-api-server)
                operatorAPIServer=$2
                shift 2
                ;;
            --service-hub-api-server)
                serviceHubAPIServer=$2
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

getArch() {
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
getOS() {
  OS=$(echo `uname`|tr '[:upper:]' '[:lower:]')

  case "$OS" in
    # Minimalist GNU for Windows
    mingw*|cygwin*) OS='windows';;
  esac
}

function installHelm() {
    getArch
    getOS
    #curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash -
    TAG=v3.8.0
    HAS_CURL="$(type "curl" &> /dev/null && echo true || echo false)"
    HAS_WGET="$(type "wget" &> /dev/null && echo true || echo false)"
    if ! helm version > /dev/null 2>&1; then
        echo "installing helm $TAG..."
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

function labelConnectorNodes() {
    echo "labeling connector nodes..."
    for connector in ${connectors[*]}; do
      kubectl label node --overwrite=true $connector node-role.kubernetes.io/connector=
    done
}

function labelEdgeNodes() {
    echo "labeling edge nodes..."
    for edge in ${edges[*]}; do
      kubectl label node --overwrite=true $edge node-role.kubernetes.io/edge=
    done
}

generatePatchFile() {
    filename=$(mktemp)
    if [ x$arch == x ]; then
        cat > $filename << EOF
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
              - key: node-role.kubernetes.io/edge
                operator: DoesNotExist
EOF
    else
        cat > $filename << EOF
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
              - key: kubernetes.io/arch
                operator: In
                values:
                - ${arch}
              - key: node-role.kubernetes.io/edge
                operator: DoesNotExist
EOF
 fi
 echo $filename
}

function patchKubeProxyIfKubeEdgeExists() {
    name=$(kubectl get ns kubeedge 2>/dev/null | grep kubeedge | awk '{ print $1 }')
    if [ x"$name" == x"kubeedge" ]; then
        echo "patching edge node affinity to kube-system/kube-proxy daemonset" 
        filename=$(mktemp)
        cat > $filename << EOF
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
              - key: node-role.kubernetes.io/edge
                operator: DoesNotExist
EOF
        kubectl patch ds kube-proxy -n kube-system --patch "$(cat $filename)"
    fi
}

function patchCNINodeAffinity() {
    echo "patching edge node affinity to $cniType work nodes..."
    if  [ "${KUBERNETES_PROVIDER}" == "k3s" ]; then
        return
    fi

    cniNamespace=$(kubectl get ds -A | grep $cniType | awk '{ print $1 }' | uniq)
    if [ x"$cniNamespace" == x ]; then
      cniNamespace=kube-system
    fi

    found="false"
    for name in $(kubectl get ds -n $cniNamespace | awk '{ print $1 }')
    do
      if [[ $name =~ ^(kube-flannel(-ds(-[a-zA-Z0-9]+)?)?|calico-node)$ ]]; then
          arch=${name:16:10}
          filename=$(generatePatchFile $arch)
          kubectl patch ds -n $cniNamespace $name --patch "$(cat $filename)"
          found="true"
      fi
    done

    if [[ "$found" == "false" ]]; then
      echo 'Could not find calico or flannel pod'
      exit 2
    fi
}

# change shell array value to helm array value
# eg. (val1 val2 val3) => {va1,val2,va3)
helmArray() {
    if [[ $# -gt 0 ]]; then
      echo "$*" | awk 'BEGIN{printf "{"}{for(i=1; i<=NF; i++){if(i == NF)printf $i; else printf $i","}}END{printf "}"}'
    fi
}

deployFabEdge() {
    echo "installing fabedge..."
    # convert shell list (label1, label2, label3) to "{label1,label2,label3}"
    valuesConnectorPublicAddresses=$(helmArray ${connectorPublicAddresses[*]})
    valuesConnectorNodeAddresses=$(helmArray ${connectorNodeAddresses[*]})
    valuesServiceClusterIPRange=$(helmArray ${serviceClusterIPRange[*]})
    valuesClusterCIDR=$(helmArray ${clusterCIDR[*]})

    if [ x"$clusterRole" == x"host" ]; then
        helm install fabedge $chart \
          --create-namespace \
          -n $namespace \
          --set cluster.name=$clusterName\
          --set cluster.role=$clusterRole \
          --set cluster.region=$clusterRegion \
          --set cluster.zone=$clusterZone \
          --set cluster.cniType=$cniType \
          --set cluster.edgePodCIDR=$edgePodCIDR \
          --set cluster.edgeCIDRMaskSize=$edgeCIDRMaskSize \
          --set cluster.clusterCIDR=$valuesClusterCIDR \
          --set cluster.serviceClusterIPRange=$valuesServiceClusterIPRange \
          --set cluster.connectorPublicAddresses=$valuesConnectorPublicAddresses \
          --set cluster.connectorPublicPort=$connectorPublicPort \
          --set cluster.connectorNodeAddresses=$valuesConnectorNodeAddresses \
          --set cluster.connectorAsMediator=$connectorAsMediator \
          --set operator.service.nodePort=$operatorNodePort \
          --set operator.autoKeepIPPools=$autoKeepIPPools \
          --set serviceHub.service.nodePort=$serviceHubNodePort \
          --set agent.args.ENABLE_PROXY=$enableProxy \
          --set agent.args.ENABLE_DNS=$enableDNS \
          --set fabDNS.create=$enableFabDNS
    elif [ x"$clusterRole" == x"member" ]; then
        helm install fabedge $chart \
          --create-namespace \
          -n $namespace \
          --set cluster.name=$clusterName \
          --set cluster.role=$clusterRole \
          --set cluster.region=$clusterRegion \
          --set cluster.zone=$clusterZone \
          --set cluster.cniType=$cniType \
          --set cluster.edgePodCIDR=$edgePodCIDR \
          --set cluster.edgeCIDRMaskSize=$edgeCIDRMaskSize \
          --set cluster.clusterCIDR=$valuesClusterCIDR \
          --set cluster.serviceClusterIPRange=$valuesServiceClusterIPRange \
          --set cluster.connectorPublicAddresses=$valuesConnectorPublicAddresses \
          --set cluster.connectorPublicPort=$connectorPublicPort \
          --set cluster.connectorNodeAddresses=$valuesConnectorNodeAddresses \
          --set cluster.connectorAsMediator=$connectorAsMediator \
          --set cluster.operatorAPIServer=$operatorAPIServer \
          --set operator.autoKeepIPPools=$autoKeepIPPools \
          --set cluster.serviceHubAPIServer=$serviceHubAPIServer \
          --set cluster.initToken=$initToken \
          --set agent.args.ENABLE_PROXY=$enableProxy \
          --set agent.args.ENABLE_DNS=$enableDNS \
          --set fabDNS.create=$enableFabDNS
    fi
}

parseArgs $*
setDefaultArgs
validateArgs

installHelm
labelEdgeNodes
labelConnectorNodes
patchCNINodeAffinity
patchKubeProxyIfKubeEdgeExists
deployFabEdge