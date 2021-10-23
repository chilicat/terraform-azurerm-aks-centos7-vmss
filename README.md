# Centos VMSS Azure Module

This repo contains a Module for deploying a custom Centos7 VMSS for a existing AKS cluster.
In general there should be no need to rely on a specific OS if you use containers, however, 
sometimes reality requires to install some custom packages to make your software stack working. 

This module provides a recipe of how to add your custom centos workers to an existing AKS.

## How to use this Module

Create an AKS instance. Since this module doe not support all versions and all features of AKS you can use 
the terraform module in the [examples](examples) folder to get started.

Create the AKS cluster:
```
cd examples/aks
terraform init
terraform apply --var resource_group_name=myaks --var name=myaks --auto-approve
```

After we have an AKS instance we can apply the centos vmss module

```
cd examples/aks-centos-vmss
terraform init
terraform apply --var resource_group_name=myaks --var aks_name=myaks --var name=mycentos --auto-aprrove
```

when the deployment is done you should be able to see the new centos worker in the node list

```
kubectl get node
NAME                                 STATUS   ROLES   AGE    VERSION
aks-default-31244857-vmss000000      Ready    agent   17m    v1.20.9
aks-plain-mycentos-vmss000000        Ready    agent   5m8s   v1.20.9
```

Note: The VMSS is deployed into the reource group which also contains the AKS VMSS resources (MC_myaks_<aks_name>_<location>)

## License

This code is released under the Apache 2.0 License.