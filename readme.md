ARTICLE

## Prereqs

- Grok all the options of the OKE Terraform module, the architecture you choose (public, private, bastion, operator) has a huge impact on how game clients connect and how you will manage services in OCI https://oracle-terraform-modules.github.io/terraform-oci-oke/guide/topology.html. Public vs Private Clusters (administration), public vs. private worker nodes (game client), public vs. internal load balancers
- What is the OCI topology???? Do we have something that does NAT like Global Accelerator, use NLB?
    - Use private cluster
    - Use X worker nodes
    - Use X load balancer
- Install kubectl on the terraform box
- You need Tenancy admin because of the dynamic group policy created by the OKE module, other than that everything gets created in the specific compartment

## Deploy Agones

This step deploys only the Agones components and creates LoadBalancer services for the Allocator and Ping HTTP Service.  No games or game servers are deployed in this step.

- Terrafrom the infra, make sure to set the instance shape to one that is available
- Set `create_operator = false`, its not needed for public subnets

    cd infra
    terraform plan
    terraform apply

### Test Agones & Infra

- Copy the `./generated/kubeconfig` to `~/.kube/config`
- Get the running pods `kubectl get pods --namespace agones-system`

## Deploy Game Servers

Routing from client can be 5, 3 or 2 Tuple hash https://blogs.oracle.com/cloud-infrastructure/post/network-load-balancer-support-on-oracle-kubernetes-engine
This maintains session via UDP from the client to the running gameserver in OKE.

All Agones examples (except the blogged AWS with Global Accel) all permit UDP directly to the node pool from quad zero.

In OKE, Cluster mode obscures the client source IP and can cause a second hop to another node but has good overall load-spreading. The local option preserves the source IP address in the header of the packet all the way to the application pod.
  - Would want "local" ideally

### Problem To Solve

I NEED TO "RETURN" the IP of a specific game server to a game client (as a result of a mocked match making service) so the client can connect via the NLB to a specific game server vs. a random one.
???????

    I think this can be explained, that a match maker and director service would connect to the game client and negotiate over HTTPS
    *****Then, as part of the blog and testing, "mock" deploy a game server, get its IP, and connect to it from a client******


- Normally, a "match" is made and then Agones will allocate a game server (if not already existing), then return the game server IP to the client for it to connect to....and not necessisarly randomly choose (via LB routing) a running game server.
- Need a NLB https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengcreatingnetworkloadbalancers.htm#contengcreatingloadbalancer_topic_Exposing_TCP_UPD_applications
- Enalbe UDP traffic to worker nodes https://agones.dev/site/docs/installation/creating-cluster/oke/#allowing-udp-traffic
- Need gameserver
- Need gameclient

### Test Game Servers

## Deploy a Fleet

### Test Fleet