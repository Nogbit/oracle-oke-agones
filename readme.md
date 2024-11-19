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

## PRIVATE ENDPOINTS

### Create Agones With Helm

Get the resulting Bastion IP, and the Operator IP.  The Operator will have kubectl and helm installed and access to the K8 control plane.

    terraform output

SSH and get the nodes

    ssh -J opc@<bastion public IP> opc@<operator private ip> kubectl get nodes

Now we need to install the argones helm chart.  Normally you want to install apps seperately from infra.  We will do this manually on the operator by jumping through the bastion.

    terraform output
    ssh -J opc@<bastion public IP> opc@<operator private ip>

    # Now on the operator
    helm repo add agones https://agones.dev/chart/stable
    helm repo update
    helm install my-release --namespace agones-system --create-namespace agones/agones
    helm test my-release -n agones-system

Lets get the status of all the agones pods, they should all be running (allocator, controller, extensions, ping)

    kubectl get pods --namespace agones-system

Example output...

    [opc@o-xiteaz ~]$ kubectl get pods --namespace agones-system
    NAME                                 READY   STATUS    RESTARTS   AGE
    agones-allocator-79d8dbfcbb-r5k4j    1/1     Running   0          2m23s
    agones-allocator-79d8dbfcbb-sf6bt    1/1     Running   0          2m23s
    agones-allocator-79d8dbfcbb-xk4h5    1/1     Running   0          2m23s
    agones-controller-657c48fdfd-bfl67   1/1     Running   0          2m23s
    agones-controller-657c48fdfd-gvt2m   1/1     Running   0          2m23s
    agones-extensions-7bbbf98956-bcjkk   1/1     Running   0          2m23s
    agones-extensions-7bbbf98956-tbbrx   1/1     Running   0          2m23s
    agones-ping-6848778bd7-7z76r         1/1     Running   0          2m23s
    agones-ping-6848778bd7-dg5wp         1/1     Running   0          2m23s

### Create Agones Game Server For Testing

TO DO: For some reason, flow logs that were terraformed do NOT show ACCEPTED or REJECT for port 7003 on these servers

- Follow this guide here https://agones.dev/site/docs/getting-started/create-gameserver/

    kubectl get gameserver
    nc -u 10.0.158.12 7003
    HELLO WORLD!

After typing HELLO WORLD you will get a response, you should also see packets coming back to the operator if you have this command running in a seperate shell

     sudo tcpdump -i ens3  port 7003 --direction inout

### Create the Public Network Load Balancer

This is so public game clients can connect to game servers in OKE nodes.

- Understand exactly what it is I'm having the LB create and manage if anything https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengconfiguringloadbalancersnetworkloadbalancers-subtopic.htm
- Set the correct mode https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengcreatingnetworkloadbalancers.htm
- Create LB
- Test nc from external IP, ideally we are sticky to the same gameserver???


## PUBLIC ENDPOINJTS

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