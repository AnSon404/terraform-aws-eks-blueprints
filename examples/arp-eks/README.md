
## Prerequisites:

Ensure that you have the following tools installed locally:

1. [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
2. [kubectl](https://Kubernetes.io/docs/tasks/tools/)
3. [terraform](https://learn.hashicorp.com/tutorials/terraform/install-cli)

## Deploy

To provision this example:

```sh
terraform init

terraform apply -target aws_vpc.this -target aws_subnet.public -target aws_subnet.file -target aws_subnet.db -target aws_subnet.eks -target aws_internet_gateway.gw -target aws_route_table.public_rt -target aws_route_table_association.public_subnet_asso -target aws_eip.nat -target aws_nat_gateway.zone_a -target aws_route_table.file_rt -target aws_route_table_association.file_subnet_asso -target aws_route_table.db_rt -target aws_route_table_association.db_subnet_asso -target aws_route_table.eks_rt -target aws_route_table_association.eks_subnet_asso

terraform apply -target module.eks 
terraform apply -target aws_security_group.bastion_sg 
terraform apply -target aws_iam_instance_profile.test -target aws_iam_role.role -target aws_iam_role_policy_attachment.ssm 
terraform apply -target aws_instance.test 
terraform apply
```

Enter `yes` at command prompt to apply

## Validate

The following command will update the `kubeconfig` on your local machine and allow you to interact with your EKS Cluster using `kubectl` to validate the CoreDNS deployment for Fargate.

1. Run `update-kubeconfig` command:

```sh
aws eks --region <REGION> update-kubeconfig --name <CLUSTER_NAME>
```

2. Test by listing all the pods running currently. The CoreDNS pod should reach a status of `Running` after approximately 60 seconds:

```sh
kubectl get pods -A

# Output should look like below
NAMESPACE     NAME                                  READY   STATUS    RESTARTS   AGE
kube-system   coredns-66b965946d-gd59n              1/1     Running   0          92s
kube-system   coredns-66b965946d-tsjrm              1/1     Running   0          92s
...
```

## Destroy

To teardown and remove the resources created in this example:

```sh
terraform destroy -target="module.eks" -auto-approve
terraform destroy -target="aws_vpc.this" -auto-approve
terraform destroy -auto-approve
```
