#!/bin/bash -x
set -euo pipefail

namespace=default
action=""
_kubectl="${KUBECTL_BINARY:-oc}"
timeout=3

options=$(getopt -o n: --long suspend,resume,snapshot -- "$@")
[ $? -eq 0 ] || {
    echo "Incorrect options provided"
    exit 1
}
eval set -- "$options"
while true; do
    case "$1" in
    --suspend)
        action="suspend"
        ;;
    --resume)
        action="resume"
        ;;
    --snapshot)
        action="snapshot"
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
    echo "Usage: script <vm> [-n <namespace>]  --resume|--suspend".
    exit 1
fi

UUID=$(${_kubectl} get vmis ${vm} -n ${namespace} --no-headers -o custom-columns=METATADA:.metadata.uid) 
POD=$(${_kubectl} get pods -n ${namespace} -l kubevirt.io/created-by=${UUID} --no-headers -o custom-columns=NAME:.metadata.name)
_exec="${_kubectl} exec  ${POD} -n ${namespace} -c compute --"

 if [ "${action}" == "suspend" ]; then
    ${_exec} mkdir -p /var/run/libvirtt
    ${_exec} sed -i 's[#unix_sock_dir = "/run/libvirt"[unix_sock_dir = "/var/run/libvirtt"[' /etc/libvirt/libvirtd.conf 
    LIBVIRT_PID=$(${_exec} bash -c 'pidof -s libvirtd')
    ${_exec} kill ${LIBVIRT_PID}
    _virsh="${_exec} virsh -c qemu+unix:///system?socket=/var/run/libvirtt/libvirt-sock"
    sleep ${timeout}
    ${_virsh} suspend ${namespace}_${vm}
elif [ "${action}" == "snapshot" ]; then
    _virsh="${_exec} virsh -c qemu+unix:///system?socket=/var/run/libvirtt/libvirt-sock"
    ${_exec} mkdir -p /var/run/kubevirt/snapshots/${namespace}_${vm}/
    #${_virsh} snapshot-create-as ${namespace}_${vm} --memspec file=/var/run/kubevirt/snapshots/${namespace}_${vm}/memory --live
    ${_virsh} dump ${namespace}_${vm} /var/run/kubevirt/snapshots/${namespace}_${vm}/${namespace}_${vm}
elif [ "${action}" == "resume" ]; then
    ${_exec} sed -i 's[unix_sock_dir = "/var/run/libvirtt"[#unix_sock_dir = "/var/run/libvirt"[' /etc/libvirt/libvirtd.conf
    LIBVIRT_PID=$(${_exec} bash -c 'pidof -s libvirtd')
    ${_exec} kill ${LIBVIRT_PID}
    _virsh="${_exec} virsh"
    ${_exec} rm -rf /var/run/libvirtt
    sleep ${timeout}
    ${_virsh} resume ${namespace}_${vm}
fi

