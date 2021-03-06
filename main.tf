resource "azurerm_resource_group" "aks_resource_group" {
  location = "${var.location}"
  name     = "${var.cluster_name}"
}

resource "azurerm_kubernetes_cluster" "aks_managed_cluster" {
  name                = "${var.cluster_name}"
  location            = "${azurerm_resource_group.aks_resource_group.location}"
  resource_group_name = "${azurerm_resource_group.aks_resource_group.name}"
  kubernetes_version  = "${var.k8s_version}"
  dns_prefix          = "${var.dns_prefix}"

  agent_pool_profile {
    name            = "${var.agent_prefix}"
    vm_size         = "${var.agent_vm_sku}"
    count           = "${var.node_count}"
    os_type         = "Linux"
    os_disk_size_gb = "${var.node_os_disk_size_gb}"
  }

  linux_profile {
    admin_username = "${var.agent_admin_user}"

    ssh_key {
      key_data = "${var.public_key_data == "" ? file("~/.ssh/id_rsa.pub") : var.public_key_data}"
    }
  }

  service_principal {
    client_id     = "${var.sp_client_id}"
    client_secret = "${var.sp_client_secret}"
  }
}

data "template_file" "ingress_controller_patch" {
  template = "templates/ingres_controller_patch.yaml.tpl"

  vars {
    deployment_name = "${var.nginx_deployment_name}"
    k8snamespace    = "${var.ingress_controller_namespace}"
  }
}

resource "null_resource" "provision" {
  provisioner "local-exec" {
    command = "az aks get-credentials -n ${var.cluster_name} -g ${azurerm_resource_group.aks_resource_group.name}"
  }

  provisioner "local-exec" {
    # install tiller and wait for the container to initialise on the cluster
    command = "helm init && kubectl cluster-info"
  }

  provisioner "local-exec" {
    # update helm
    command = "helm update"
  }

  provisioner "local-exec" {
    # install ingress controller
    command = "helm install stable/ingress-nginx -n ${var.nginx_deployment_name} --namespace ${var.ingress_controller_namespace}"
  }

  provisioner "file" {
    destination = "./ingress_controller_patch.yaml"
    content     = "${data.template_file.ingress_controller_patch.rendered}"
  }

  provisioner "local-exec" {
    # patch ingress controller?
    command = "kubectl apply -f ./ingress-controller-patch.yaml"
  }

  # install cert-manager
  provisioner "local-exec" {
    command = "helm install stable/cert-manager -n ${var.nginx_deployment_name} --namespace ${var.ingress_controller_namespace}"
  }
}
