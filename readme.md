ARTICLE

## Prereqs

- Grok all the options of the OKE Terraform module, the architecture you choose (public, private, bastion, operator) has a huge impact on how game clients connect and how you will manage services in OCI https://oracle-terraform-modules.github.io/terraform-oci-oke/guide/topology.html. Public vs Private Clusters (administration), public vs. private worker nodes (game client), public vs. internal load balancers
- What is the OCI topology???? Do we have something that does NAT like Global Accelerator, use NLB?
    - Use private cluster
    - Use X worker nodes
    - Use X load balancer
- You need Tenancy admin because of the dynamic group policy created by the OKE module, other than that everything gets created in the specific compartment

## Deploy The Infra

This step deploys only the OKE Cluster.  It will create the nodes with public IP's with UDP connections permitted.  This also creates a bastion (public IP) and the operator (private IP).  Use the operator to connect to the control plane and use kubectl there.

    cd infra
    terraform plan
    terraform apply

## Create Agones With Helm

This creates Agones components and creates LoadBalancer services for the Allocator and Ping HTTP Service.  No games or game servers are deployed in this step. Get the resulting Bastion IP, and the Operator IP.  The Operator will have kubectl and helm installed and access to the K8 control plane.

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

## Create Agones Game Server For Testing

Follow this guide here https://agones.dev/site/docs/getting-started/create-gameserver/

From the Operator after SSH

    kubectl create -f https://raw.githubusercontent.com/googleforgames/agones/release-1.45.0/examples/simple-game-server/gameserver.yaml

    kubectl get gameserver

From a terminal on the internet

    nc -u 10.0.158.12 7003
    HELLO WORLD!

After typing HELLO WORLD you will get a response, you should also see packets coming back to the client if you have this command running in a seperate shell

     sudo tcpdump -i ens3  port 7003 --direction inout

## Scaling the Cluster and Agones


