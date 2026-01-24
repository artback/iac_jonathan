variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "instance_count" {
  description = "Number of nodes"
  type        = number
  default     = 3
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "ami_id" {
  description = "AMI ID (Ubuntu 22.04 recommended)"
  type        = string
  # No default to force user to choose, or provide a recent one for us-east-1
  default     = "ami-0c7217cdde317cfec" # Ubuntu 22.04 LTS us-east-1 (Example)
}

variable "ssh_key_name" {
  description = "Name of existing SSH key pair in AWS"
  type        = string
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "nomad-consul"
}
