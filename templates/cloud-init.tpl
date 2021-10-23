write_files:
- encoding: b64
  content: '${base64encode(azure_json)}'
  owner: 'root:root'
  path: '/etc/kubernetes/azure.json'
  permissions: '0644'

- encoding: b64
  content: '${base64encode(kubeconfig_raw)}'
  owner: 'root:root'
  path: '/var/lib/kubelet/kubeconfig'
  permissions: '0644'

- encoding: b64
  content: '${base64encode(kubelet_env)}'
  owner: 'root:root'
  path: '/etc/default/kubelet'
  permissions: '0644'

- encoding: b64
  content: '${base64encode(kubelet_config)}'
  owner: 'root:root'
  path: '/var/lib/kubelet/kubelet-config.yaml'
  permissions: '0644'

# ========== certs 
- encoding: b64
  content: '${kubeconfig.cluster_ca_certificate}'
  owner: 'root:root'
  path: '/etc/kubernetes/certs/ca.crt'
  permissions: '0644'

- encoding: b64
  content: '${kubeconfig.client_certificate}'
  owner: 'root:root'
  path: '/etc/kubernetes/certs/client.crt'
  permissions: '0644'

- encoding: b64
  content: '${kubeconfig.client_key}'
  owner: 'root:root'
  path: '/etc/kubernetes/certs/client.key'
  permissions: '0644'

# ========== kubelet 
- encoding: b64
  content: '${kubeconfig.client_certificate}'
  owner: 'root:root'
  path: '/etc/kubernetes/certs/kubeletserver.crt'
  permissions: '0644'

- encoding: b64
  content: '${kubeconfig.client_key}'
  owner: 'root:root'
  path: '/etc/kubernetes/certs/kubeletserver.key'
  permissions: '0644'

# =========== install
- encoding: b64
  content: '${install_script}'
  owner: 'root:root'
  path: '/bin/install.sh'
  permissions: '0744'
runcmd:
- /bin/install.sh &> /var/log/install.log
- /bin/cleanup-secondary-ips
- /bin/start-and-enable-servces
