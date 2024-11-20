// Copyright 2024 Google LLC All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

terraform {
  required_version = ">= 1.2.0"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.28.0"
    }
  }
}

module "oke_cluster" {
  source  = "oracle-terraform-modules/oke/oci"
  version = ">= 5.1.8"

  region      = var.region
  home_region = var.home_region
  tenancy_id  = var.tenancy_id
  user_id     = var.user_id

  providers = {
    oci      = oci
    oci.home = oci.home
  }

  # general oci parameters
  compartment_id = var.compartment_id

  # ssh keys
  ssh_private_key_path = var.ssh_private_key_path
  ssh_public_key_path  = var.ssh_public_key_path

  # Resource creation
  assign_dns           = true
  create_vcn           = true
  create_bastion       = true
  create_cluster       = true
  create_operator      = true
  create_iam_resources = true

  # oke cluster options
  cluster_name            = var.cluster_name
  cluster_type            = var.cluster_type
  cni_type                = var.preferred_cni
  control_plane_is_public = var.oke_public_control_plane
  kubernetes_version      = var.kubernetes_version

  # security, private control plane but public nodes for game client connections
  bastion_allowed_cidrs             = ["0.0.0.0/0"]
  allow_worker_ssh_access           = false
  assign_public_ip_to_control_plane = false
  load_balancers                    = "internal"
  preferred_load_balancer           = "internal"

  # So UDP traffic can get from client into the cluster nodes (where argones will manage ingress to pod)
  worker_is_public                  = true

  # node pools
  worker_pools = {
    node_pool_1 = {
      shape            = "VM.Standard.E3.Flex",
      ocpus            = 2,
      memory           = 32,
      size             = var.node_count,
      boot_volume_size = 150,
    }
  }

  bastion_shape = {
    shape            = "VM.Standard.E3.Flex",
    ocpus            = 1,
    memory           = 4,
    boot_volume_size = 50
  }

  worker_shape = {
    shape            = "VM.Standard.E3.Flex",
    ocpus            = 1,
    memory           = 4,
    boot_volume_size = 50
  }

  operator_shape = {
    shape            = "VM.Standard.E3.Flex",
    ocpus            = 1,
    memory           = 4,
    boot_volume_size = 50
  }
}

data "oci_containerengine_cluster_kube_config" "oke_cluster_kubeconfig" {
  cluster_id = module.oke_cluster.cluster_id
}

resource "local_file" "kubeconfig" {
  content         = data.oci_containerengine_cluster_kube_config.oke_cluster_kubeconfig.content
  filename        = "${path.module}/generated/kubeconfig"
  file_permission = "0600"
}

# UDP traffic for worker nodes
resource "oci_core_network_security_group_security_rule" "worker_ingress_rule" {
  network_security_group_id = module.oke_cluster.worker_nsg_id
  description               = "Allow UDP traffic from game client internet to workers"
  direction                 = "INGRESS"
  protocol                  = "17"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"

  udp_options {
    destination_port_range {
      max = 8000
      min = 7000
    }
  }
}

resource "oci_core_network_security_group_security_rule" "worker_egress_rule" {
  network_security_group_id = module.oke_cluster.worker_nsg_id
  description               = "Allow workers testing traffic to egress to game clients"
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
}


# LOGGING FOR THE VNC
resource "oci_logging_log_group" "flow_logs_group" {
  compartment_id = var.compartment_id
  display_name   = "flow-logs-group"
}

resource "oci_logging_log" "vcn_log" {
  display_name = "vcn-logs"
  log_group_id = oci_logging_log_group.flow_logs_group.id
  log_type     = "SERVICE"
  configuration {
    source {
      category    = "vcn"
      resource    = module.oke_cluster.vcn_id
      service     = "flowlogs"
      source_type = "OCISERVICE"
    }
  }
  is_enabled         =  true
}
