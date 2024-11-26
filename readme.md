ARTICLE

# TO DO

1. Put the "gameserver" in its own pool, and have that pool with a label and affinity match
nodeAffinityPolicy

By default Agones prefers to be scheduled on nodes labeled with agones.dev/agones-system=true and tolerates node taint agones.dev/agones-system=true:NoExecute.

    Match antiaffinity with label
        oke.oraclecloud.com/cluster_autoscaler=allowed

    Manually add a taint to the autoscaling pool

        agones.dev/agones-system=true:NoExecute

2. Make sure scale down happens and the autoscaling node pool doesnt go offline

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

Make sure Agones does not run pods on the cluster autoscaler node. We do this by creating a new file `agones-afinity.yaml` and paste the contents from `./agones/agones-afinity.yaml`.  We will then use these yaml helm values during the install of the agones chart.

Now we need to install the argones helm chart.  Normally you want to install apps seperately from infra.  We will do this manually on the operator by jumping through the bastion.

    helm repo add agones https://agones.dev/chart/stable
    helm repo update

    # Installing using the values for afinity you created above
    helm install my-release --namespace agones-system --create-namespace agones/agones -f agones-afinity.yaml
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

Delete the gameserver when done

    kubectl delete gameserver <name of gameserver>

## Scaling the Cluster and Agones

### TO DO

Why is the node_pool_1-autoscaler in "not ready" state
Run this again, but check why a scale up of 600 killed the other pool instance, or did it?
TRY AND REPRODUCE....READ DOCS ABOUT SCALING RAPIDLY????


Steps...

When setting scalin in your OKE Terraform, if you already have a cluster created you will have to do a `mv` on some of the terraform, refer to documentation.  The Terraform here is mean for greenfield clusters.

SSH to the controller

Install addon, OKE module is not working to do that for us

    oci ce cluster install-addon --addon-name ClusterAutoscaler --from-json file://add.json --cluster-id ocid1.cluster.oc1.iad.aaaaaaaazl3bh6n5dbdiokikytzk3m2yw3maoswbyl6s7vlypcagitlbvz5a


Create a file called `fleet.yaml` with the contents from `agones/fleet.yaml`

Apply the fleet `kubectl apply -f fleet.yaml`

Get the gameservers and nodes, you should see 3 of each, you should now see three of them

    kubectl get nodes
    kubectl get gameserver

Scale the fleet to 600

    kubectl scale fleet simple-game-server --replicas=300

After a few moments, get the gameservers and nodes, you should see a lot of gameservers in Starting or Pending state, and a new node starting up automaticly for us.  Initially you will see the node pool in the console updating as well and new compute instances being added to the node pool before they start to show in `kubectl get nodes` results.

    # grep for pods that have 0 containers running
    kubectl get nodes |grep 0/2
    kubectl get gameserver

To troubleshoot, get the logs of a given pod, you may have issues with the pod not triggering autoscaling.  If so, makure your addon was installed to the correct node pool (see above for instructions) and that your affinity settings for the fleet.yaml is correct.

    kubectl get pod <pod name>

And scale back down

    kubectl scale fleet simple-game-server --replicas=3

We should now see nodes and gameservers automaticly start to be removed and put into Shutdown status.

    kubectl get gameserver

After some time, we should see the nodes start to disapper according to the scale down rules of the autoscaler https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md#how-does-scale-down-work.

    kubectl get nodes

Some of the system pods will have `scale-down-delay-after-add=10m` which means you will have to wait at least 10min after the initial scale up before any scaling down will take place.