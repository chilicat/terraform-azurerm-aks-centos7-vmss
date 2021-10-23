#!/bin/bash -e

yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
yum -y install monit

#####
# Install some common tools:
#####
yum install -y cifs-utils conntrack cracklib ebtables ethtool fuse git iotop iproute ipset iptables pigz socat sysfsutils sysstat traceroute util-linux xz zip

# =================================
# Monit
# =================================

cat > /etc/monit.d/kubelet << EOM
check process kubelet matching "/bin/kubelet"
  group kubernetes
  start program = "/usr/bin/systemctl start kubelet"
  stop  program = "/usr/bin/systemctl stop kubelet"
  restart program  = "/usr/bin/systemctl restart kubelet"
  if failed (url http://localhost:10248/healthz and content == "ok") for 2 cycles then restart
  if cpu is greater than 90% for 10 cycles then restart
EOM

cat > /bin/cleanup-secondary-ips  << EOM
#!/bin/bash
# Hotfix: Centos attaches all available IP addreses to eth0
# We must remove the IPs from interface in order to make Azure Pod network (cni) working
for i in \$(ip addr show  eth0 | grep ine | grep secondary | awk '{print \$2}'); do 
  ip addr del \$i dev eth0
done
EOM

chmod +x /bin/cleanup-secondary-ips

cat > /etc/monit.d/cleanup-inet << EOM
check program cleanup-inet with path /bin/cleanup-secondary-ips
  every 10 cycles
  if status != 0 then exec "/bin/echo 'Cleanup network interfaces failed' >> /var/log/cleanup-inet.log"
EOM

cat > /etc/sysctl.d/99-kubernetes-cri.conf << EOM
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.ipv4.conf.all.forwarding        = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOM

cat > /etc/sysctl.d/60-CIS.conf << EOM
-----------------------------------
# 3.1.2 Ensure packet redirect sending is disabled
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
# 3.2.1 Ensure source routed packets are not accepted 
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
# 3.2.2 Ensure ICMP redirects are not accepted
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
# 3.2.3 Ensure secure ICMP redirects are not accepted
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
# 3.2.4 Ensure suspicious packets are logged
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
# 3.3.1 Ensure IPv6 router advertisements are not accepted
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0
# 3.3.2 Ensure IPv6 redirects are not accepted
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
# refer to https://github.com/kubernetes/kubernetes/blob/75d45bdfc9eeda15fb550e00da662c12d7d37985/pkg/kubelet/cm/container_manager_linux.go#L359-L397
vm.overcommit_memory = 1
kernel.panic = 10
kernel.panic_on_oops = 1
# https://github.com/Azure/AKS/issues/772
fs.inotify.max_user_watches = 1048576
EOM

cat > /etc/sysctl.d/999-sysctl-aks.conf << EOM
# This is a partial workaround to this upstream Kubernetes issue:
# https://github.com/kubernetes/kubernetes/issues/41916#issuecomment-312428731
net.ipv4.tcp_retries2=8
net.core.message_burst=80
net.core.message_cost=40
net.core.somaxconn=16384
net.ipv4.tcp_max_syn_backlog=16384
net.ipv4.neigh.default.gc_thresh1=4096
net.ipv4.neigh.default.gc_thresh2=8192
net.ipv4.neigh.default.gc_thresh3=16384
EOM

sysctl --system ||:
sysctl -p ||:

mkdir -p /root/.kube/
ln -s /var/lib/kubelet/kubeconfig /root/.kube/config 

yum install -y yum-utils
yum-config-manager  -y --add-repo   https://download.docker.com/linux/centos/docker-ce.repo

yum install -y containerd.io container-selinux fuse-overlayfs fuse3-libs slirp4netns

systemctl stop containerd

cat > /etc/containerd/config.toml << EOM
version = 2
subreaper = false
oom_score = 0
[plugins."io.containerd.grpc.v1.cri"]
  sandbox_image = "mcr.microsoft.com/oss/kubernetes/pause:3.5"
  [plugins."io.containerd.grpc.v1.cri".containerd]
    
    [plugins."io.containerd.grpc.v1.cri".containerd.untrusted_workload_runtime]
      runtime_type = "io.containerd.runtime.v1.linux"
      runtime_engine = "/usr/bin/runc"
    [plugins."io.containerd.grpc.v1.cri".containerd.default_runtime]
      runtime_type = "io.containerd.runtime.v1.linux"
      runtime_engine = "/usr/bin/runc"
  
  [plugins."io.containerd.grpc.v1.cri".registry.headers]
    X-Meta-Source-Client = ["azure/aks"]
[metrics]
  address = "0.0.0.0:10257"
EOM

# Overwrite containerd with "azure" variant.
# TODO: download?
#curl -sLo /bin/containerd https://.../containerd-1.4.9+azure
#chmod +x /bin/containerd 

curl -sL https://github.com/kubernetes-sigs/cri-tools/releases/download/v1.20.0/crictl-v1.20.0-linux-amd64.tar.gz | tar -C /usr/bin -xzf -
curl -sLo /usr/bin/kubectl  https://storage.googleapis.com/kubernetes-release/release/v1.20.9/bin/linux/amd64/kubectl
curl -sLo /usr/bin/kubelet https://storage.googleapis.com/kubernetes-release/release/v1.20.9/bin/linux/amd64/kubelet

chmod +x  /usr/bin/kubectl
chmod +x /usr/bin/kubelet 

#####
# CNI install / config
#####
mkdir -p /opt/cni/bin/
mkdir cni 
cd cni

curl -sLo cni.tgz https://acs-mirror.azureedge.net/cni/cni-plugins-amd64-v0.7.6.tgz 

tar -xf cni.tgz
rm -f cni.tgz
mv * /opt/cni/bin/

curl -sLo cni.tgz https://github.com/Azure/azure-container-networking/releases/download/v1.2.7/azure-vnet-cni-linux-amd64-v1.2.7.tgz
tar -xf cni.tgz

mv azure-* /opt/cni/bin/

mkdir -p /etc/cni/net.d/
rm -rf /etc/cni/net.d/*.conf
rm -rf /etc/cni/net.d/*.conflist
# The default config uses a azure-bridge which does not work as expected.
rm 10-azure.conflist

#####
# The azure network configuration must be written by cloud-init:
# https://github.com/Azure/azure-container-networking/blob/master/docs/cni.md
#####
cat > /etc/cni/net.d/10-azure.conflist << EOM
{
   "cniVersion":"0.3.0",
   "name":"azure",
   "plugins":[
      {
         "type":"azure-vnet",
         "mode":"transparent",
         "ipsToRouteViaHost":["169.254.20.10"],
         "ipam":{
            "type":"azure-vnet-ipam"
         }
      },
      {
         "type":"portmap",
         "capabilities":{
            "portMappings":true
         },
         "snat":true
      }
   ]
}
EOM

mkdir -p /opt/azure/containers/
mkdir -p /etc/kubernetes/certs
mkdir -p /etc/kubernetes/volumeplugins
mkdir -p /etc/kubernetes/manifests
mkdir -p /var/lib/kubelet

cat > /opt/azure/containers/kubelet-cert-config.sh << EOM
#/bin/bash
# This script creates a new key/cert for the kubelet node.
# It must be executed before kubelet is started
[[ -f /etc/kubernetes/certs/kubeletserver.key ]] || {
  openssl genrsa -out /etc/kubernetes/certs/kubeletserver.key 2048
}
[[ -f /etc/kubernetes/certs/kubeletserver.crt ]] || {
  # Note: How do we rotate it?
  openssl req -new -x509 -days 7300 -key /etc/kubernetes/certs/kubeletserver.key -out /etc/kubernetes/certs/kubeletserver.crt -subj "/CN=\$(hostname -s)"
}
EOM

chmod +x /opt/azure/containers/kubelet-cert-config.sh

cat > /opt/azure/containers/kubelet.sh << EOM
#!/bin/bash
# Disallow container from reaching out to the special IP address 168.63.129.16
# for TCP protocol (which http uses)
#
# 168.63.129.16 contains protected settings that have priviledged info.
#
# The host can still reach 168.63.129.16 because it goes through the OUTPUT chain, not FORWARD.
#
# Note: we should not block all traffic to 168.63.129.16. For example UDP traffic is still needed
# for DNS.
iptables -I FORWARD -d 168.63.129.16 -p tcp --dport 80 -j DROP
EOM

chmod +x /opt/azure/containers/kubelet.sh

cat > /etc/systemd/system/kubelet.service << EOM
[Unit]
Description=Kubelet
ConditionPathExists=/bin/kubelet

[Service]
Restart=always
EnvironmentFile=/etc/default/kubelet
SuccessExitStatus=143
ExecStartPre=/bin/bash /opt/azure/containers/kubelet.sh
ExecStartPre=/bin/bash /opt/azure/containers/kubelet-cert-config.sh

ExecStartPre=/bin/mkdir -p /var/lib/kubelet
ExecStartPre=/bin/mkdir -p /var/lib/cni

ExecStartPre=-/sbin/ebtables -t nat --list
ExecStartPre=-/sbin/iptables -t nat --numeric --list

ExecStart=/bin/kubelet --v=2 \\
    --config=/var/lib/kubelet/kubelet-config.yaml \\
    --kubeconfig=/var/lib/kubelet/kubeconfig \\
    --register-node=true \\
    --network-plugin=cni \\
    --cloud-config=/etc/kubernetes/azure.json \\
    --cloud-provider=azure \\
    --container-runtime=remote \\
    --container-runtime-endpoint=unix:///var/run/containerd/containerd.sock \\
    --image-pull-progress-deadline=2m \\
    --azure-container-registry-config=/etc/kubernetes/azure.json \\
    --pod-infra-container-image=mcr.microsoft.com/oss/kubernetes/pause:3.5 \\
    --node-labels \$KUBELET_NODE_LABELS

[Install]
WantedBy=multi-user.target

EOM

#####
# Must be provided via cloud-init custom data
#####
touch /etc/kubernetes/azure.json 

#####
# Must be provided via cloud-init custom data
#####
touch /var/lib/kubelet/kubeconfig 

#####
# kubernetes certificate files
# Must be provided via cloud-init custom data
#####
touch /etc/kubernetes/certs/ca.crt 
touch /etc/kubernetes/certs/client.crt
touch /etc/kubernetes/certs/client.key

#####
# Must be replaced by cloud-init
#####
touch /etc/default/kubelet

#####
# Kubelet Configuration - must be overwritten by cloud-init
# https://kubernetes.io/docs/tasks/administer-cluster/kubelet-config-file/
#####
touch /var/lib/kubelet/kubelet-config.yaml 

echo -n "br_netfilter" > /etc/modules-load.d/br_netfilter.conf
modprobe br_netfilter ||:

cat > /bin/start-and-enable-servces << EOM
#!/bin/bash
systemctl enable monit
systemctl enable containerd
systemctl enable kubelet

systemctl start monit
systemctl start containerd
systemctl start kubelet
EOM
chmod +x /bin/start-and-enable-servces

# Hotfix: Docker memory issues with old Centos Kernel
# Configure kernel params
#source /etc/default/grub
#NEW_VAL="$GRUB_CMDLINE_LINUX cgroup.memory=nokmem"
#sed -i "s|GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"$NEW_VAL\"|g" /etc/default/grub 
#grub2-mkconfig -o /boot/grub2/grub.cfg
#grubby --args=cgroup.memory=nokmem --update-kernel $(ls /boot/ | grep vmlinuz-3.10 | head -n 1)
