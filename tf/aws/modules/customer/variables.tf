variable "name" {
    description = "Name of resources"
}

variable "tags" {
    description = "A map of tags to add to all resources"
    default     = {}
}

variable "account_id" {
    description = "AWS Account ID"
    default = "559166403383"
}
