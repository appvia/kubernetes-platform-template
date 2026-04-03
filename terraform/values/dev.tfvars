## Path to the cluster definition
cluster_path = "../clusters/dev.yaml"

## Tags to apply to the EKS cluster
tags = {
  Environment = "Testing"
  GitRepo     = "https://github.com/appvia/kubernetes-platform-template"
  Owner       = "Engineering"
  Product     = "Hosting"
}
