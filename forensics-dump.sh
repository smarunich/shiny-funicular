#!/bin/bash -x
set -euo pipefail

RED='\e[31m'
GREEN='\e[32m'
RESET='\e[0m'

namespace=default
action=""
_kubectl="${KUBECTL_BINARY:-oc}"
timeout=5
timestamp=$(date +%Y%m%d-%H%M%S)

options=$(getopt -o n: --long pause,dump,list,copy,unpause -- "$@")
[ $? -eq 0 ] || {
    echo "Incorrect options provided"
    exit 1
}
eval set -- "$options"
while true; do
    case "$1" in
    --pause)
        action="pause"
        ;;
    --dump)
        action="dump"
        ;;
    --copy)
        action="copy"
        filename=$1
        ;;
    --list)
        action="list"
        ;;
    --unpause)
        action="unpause"
        ;;
    -n)
        shift; # The arg is next in position args
        namespace=$1
        ;;
    --)
        shift
        break
        ;;
    esac
    shift
done
shift $(expr $OPTIND - 1 )

vm=$1

if [[ -z "$vm" || -z "$action" ]]; then
    echo "Usage: script <vm> [-n <namespace>]  --pause|--dump|--copy|--unpause".
    exit 1
fi

UUID=$(${_kubectl} get vmis ${vm} -n ${namespace} --no-headers -o custom-columns=METATADA:.metadata.uid) 
POD=$(${_kubectl} get pods -n ${namespace} -l kubevirt.io/created-by=${UUID} --no-headers -o custom-columns=NAME:.metadata.name)
_exec="${_kubectl} exec  ${POD} -n ${namespace} -c compute --"
_virtctl="virtctl --namespace ${namespace}"

 if [ "${action}" == "pause" ]; then
    ${_virtctl} pause vm ${vm}
    sleep ${timeout}
elif [ "${action}" == "dump" ]; then
    ${_exec} mkdir -p /var/run/libvirtt
    ${_exec} sed -i 's[#unix_sock_dir = "/run/libvirt"[unix_sock_dir = "/var/run/libvirtt"[' /etc/libvirt/libvirtd.conf 
    LIBVIRT_PID=$(${_exec} bash -c 'pidof -s libvirtd')
    ${_exec} kill ${LIBVIRT_PID}
    _virsh="${_exec} virsh -c qemu+unix:///system?socket=/var/run/libvirtt/libvirt-sock"
    sleep ${timeout}
    ${_exec} mkdir -p /var/run/kubevirt/dumps/${namespace}_${vm}/
    #${_virsh} dump-create-as ${namespace}_${vm} --memspec file=/var/run/kubevirt/dumps/${namespace}_${vm}/memory --live
    ${_virsh} dump ${namespace}_${vm} /var/run/kubevirt/dumps/${namespace}_${vm}/${namespace}_${vm}-${timestamp}.dump
elif [ "${action}" == "list" ]; then
     ${_exec} ls /var/run/kubevirt/dumps/${namespace}_${vm}/
elif [ "${action}" == "copy" ]; then
    ${_kubectl} cp ${POD}:/var/run/kubevirt/dumps/${namespace}_${vm}/${filename} ${filename}
elif [ "${action}" == "unpause" ]; then
    ${_exec} sed -i 's[unix_sock_dir = "/var/run/libvirtt"[#unix_sock_dir = "/var/run/libvirt"[' /etc/libvirt/libvirtd.conf
    LIBVIRT_PID=$(${_exec} bash -c 'pidof -s libvirtd')
    ${_exec} kill ${LIBVIRT_PID}
    _virsh="${_exec} virsh" 
    ${_exec} rm -rf /var/run/libvirtt
    sleep ${timeout}
    ${_virtctl} unpause vm ${vm}
fi

