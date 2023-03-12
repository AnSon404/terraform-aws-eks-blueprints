variable "public_subnet_cidrs" {
 type        = list(string)
 description = "Public Subnet CIDR values"
 default     = ["172.16.0.0/24"]
}
 
variable "file_subnet_cidrs" {
 type        = list(string)
 description = "Private Subnet CIDR values"
 default     = ["172.16.3.0/24", "172.16.4.0/24", "172.16.5.0/24"]
}
 
variable "db_subnet_cidrs" {
 type        = list(string)
 description = "Private Subnet CIDR values"
 default     = ["172.16.6.0/24", "172.16.7.0/24", "172.16.8.0/24"]
}

variable "eks_subnet_cidrs" {
 type        = list(string)
 description = "Private Subnet CIDR values"
 default     = ["172.16.32.0/19", "172.16.64.0/19", "172.16.96.0/19"]
}