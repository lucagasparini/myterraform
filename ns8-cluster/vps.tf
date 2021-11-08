
variable "images" {
  description = "Map host name code to OS image"
  default = {
    "fc" = "fedora-34-x64",
    "dn" = "debian-11-x64",
    "ub" = "ubuntu-21-04-x64"
  }
}

resource "digitalocean_vpc" "private_network" {
  for_each = tomap({ for region in distinct(values(var.nodes)) : region => region })
  name     = format("%s.%s-net.%s", terraform.workspace, each.key, var.domain)
  region   = each.key
}

resource "digitalocean_droplet" "vps" {
  for_each = var.nodes
  image    = var.images[substr(each.key, 0, 2)]
  name     = format("%s.%s", each.key, var.domain)
  region   = each.value
  size     = "s-1vcpu-1gb-intel"
  ipv6     = true
  vpc_uuid = digitalocean_vpc.private_network[each.value].id
  ssh_keys = [
    for k in var.sshkeys : data.digitalocean_ssh_key.rootpkey[k].id
  ]
  user_data = templatefile("cloud-init.yml", {
    install_cmd = "curl https://raw.githubusercontent.com/NethServer/ns8-scratchpad/main/core/install.sh | bash",
    join_cmd    = "echo DONE",
  })
}

resource "digitalocean_project_resources" "vps" {
  project   = data.digitalocean_project.default.id
  resources = [for hpx, rgn in var.nodes : digitalocean_droplet.vps[hpx].urn]
}

resource "digitalocean_record" "vps_ipv4" {
  for_each = var.nodes
  type     = "A"
  domain   = data.digitalocean_domain.default.name
  value    = digitalocean_droplet.vps[each.key].ipv4_address
  name     = each.key
  ttl      = 300
}

