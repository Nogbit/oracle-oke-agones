# Autoscaling OKE Node Pools with Agones Game Servers and Fleets

TO DO
- Check in with James
- Maybe ask why the TF install of autoscaler doesnt work, manual install is necessary
- What is the latest and great place for OCI blog articles
- Source my code somewhere for the article
- Write the article
- Publish the article

## Prereqs

- You need Tenancy admin because of the dynamic group policy created by the OKE module, other than that everything gets created in the specified compartment withint the terraform.tfvars file

## Deploy The Infra

This step deploys only the OKE Cluster.  It will create the nodes with public IP's with UDP connections permitted.  This also creates a bastion (public IP) and the operator (private IP).  Use the operator to connect to the control plane and use kubectl there.

    cd infra
    terraform init
    terraform plan
    terraform apply

## Create Agones With Helm

 Get the resulting Bastion IP, and the Operator IP.  The Operator will have kubectl and helm installed and access to the K8 control plane. You connect to the operator by jumping through the bastion.

    terraform output

Example SSH to jump to the bastion, the above `terraform output` will be more specific as to the private keys to use based on what you entered into `terraform.tfvars`

    ssh -J opc@<bastion public IP> opc@<operator private ip>

Now we need to install the argones helm chart.  Normally you want to install apps seperately from infra.  We will do this manually on the operator by jumping through the bastion. This creates Agones components and creates LoadBalancer services for the Allocator and Ping HTTP Service.  No games or game servers are deployed in this step. Note that argones respects the node labels we set in `module.tf` so the end result is the agones system pods all run on a node pool seperate from workers and seperate from the autoscaler.

    helm repo add agones https://agones.dev/chart/stable
    helm repo update

    # Installing using the values for afinity you created above
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

This step can be skipped, but its a good step to test simple connectivity from game clients without having to create an Agones Fleet.

Follow this guide here https://agones.dev/site/docs/getting-started/create-gameserver/

From the Operator after SSH

    kubectl create -f https://raw.githubusercontent.com/googleforgames/agones/release-1.45.0/examples/simple-game-server/gameserver.yaml

    kubectl get gameserver

From a terminal on the internet seperate from your SSH session

    nc -u 10.0.158.12 7003

    # Now type the following line, the line above will simply wait for input vs. acklowding a fail or success connection.
    HELLO WORLD!

After typing HELLO WORLD you will get a response, you should also see packets coming back to the client if you have this command running in a seperate shell

    sudo tcpdump -i ens3  port 7003 --direction inout

Delete the gameserver when done

    kubectl get gameserver
    kubectl delete gameserver <name of gameserver>

## Installing the OKE Autoscaler

When scaling in your OKE Terraform, if you already have a cluster created you will have to do a `mv` on some of the terraform, refer to documentation.  The Terraform here is meant for greenfield clusters.

SSH to the controller

Install addon, the OKE terraform module is not working to do that for us right now.  The file `./agones/addon.json` should be used, its format is `<min nodes>:<max nodes>:<node pool id>`.  If you have multiple nodes append another config with a comma.  Its very important here to remember that as your node pools change, if they change (renaming, changing terraform etc) then their id's will change and you will need to update the config.

    oci ce cluster install-addon --addon-name ClusterAutoscaler --from-json file://add.json --cluster-id <ocid of cluster>

## Installing the Agones Fleet

Create a file called `fleet.yaml` with the contents from `./agones/fleet.yaml`.  This was sourced from v 1.45.0. The changes made here ensure that gameservers get deployed to the matching label on our node as defined in `./infra/module.tf`.
    https://raw.githubusercontent.com/googleforgames/agones/release-1.45.0/install/yaml/install.yaml

Apply the fleet `kubectl apply -f fleet.yaml`

Get the gameservers and nodes, you should see 3 of each, you should now see three of them

    kubectl get nodes
    kubectl get gameserver

## Scaling the fleet and node pool

Scale the fleet to 300, with the nodes as configured in `./infra/module.tf` this will trigger autoscaling.

    kubectl scale fleet simple-game-server --replicas=300

After a few moments, get the gameservers and nodes, you should see a lot of gameservers in Starting or Pending state, and a new node starting up automaticly for us.  Initially you will see the node pool in the console updating as well and new compute instances being added to the node pool before they start to show in `kubectl get nodes` results.

    # grep for pods that have 0 containers running
    kubectl get nodes |grep 0/2
    kubectl get gameserver

To troubleshoot, get the status of a given pod, you may have issues with the pod not triggering autoscaling.  If so, makure sure your addon was installed to the correct node pool (see above for instructions) and that your affinity settings for the fleet.yaml is correct.

    kubectl get pod <pod name>

And scale back down

    kubectl scale fleet simple-game-server --replicas=3

We should now see nodes and gameservers automaticly start to be removed and put into Shutdown status.  Nodes wont scale down unless minimums are met, one is that the node must have been running for 10minutes, also if you have other workloads deployed they must not prevent themselves from eviction (Agones game servers by default will not be evicted unless you scale down the fleet first).

    kubectl get gameserver

After some time, we should see the nodes start to disapper according to the scale down rules of the autoscaler https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md#how-does-scale-down-work.

    kubectl get nodes

## Teardown

SSH to the operator

Delete the fleet

    kubectl delete fleets --all --all-namespaces
    kubectl delete gameservers --all --all-namespaces

    # This should be the same fleet.yaml you used to create the fleet
    kubectl delete -f fleet.yaml

    kubectl delete namespace agones-system

Delete the Agones chart, using te same name when you created it, `my-release` in this example

    helm uninstall my-release --namespace agones-system

Now from the infra, delete that

    cd infra
    terraform destroy
