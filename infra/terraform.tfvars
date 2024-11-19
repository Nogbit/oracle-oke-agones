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

# OCI provider
api_fingerprint      = "78:3e:c8:be:10:8c:4f:5e:15:6a:83:c3:69:67:36:8d"
api_private_key_path = "~/.oci/myten.pem"
region               = "us-ashburn-1"
home_region          = "us-ashburn-1"
tenancy_id           = "ocid1.tenancy.oc1..aaaaaaaag6m7iofeofzt7jvn3w5o57wavjpzi3ptlug7tiwe6673hjimaldq"
user_id              = "ocid1.user.oc1..aaaaaaaao72reaoq4ybpixyay4n6ujqyzon75lgiir6an7fnlotwqmezgsoq"
compartment_id       = "ocid1.compartment.oc1..aaaaaaaary4ed75bklxmi2qpza4ajqnzb2z4lvzadwlatamolky2hldtipuq"

# SSH keys
ssh_private_key_path = "~/.ssh/id_rsa"
ssh_public_key_path  = "~/.ssh/id_rsa.pub"

# OKE cluster
cluster_name       = "agones-cluster"
cluster_type       = "basic"
kubernetes_version = "v1.30.1"
