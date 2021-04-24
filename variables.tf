variable "info" {
  type =  map(string)
  default = {
    location  = "eastus"
    name      = "it-rg"
    type      = "B1ms"
  }
}