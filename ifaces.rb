#!/usr/bin/env ruby
require 'fileutils'
require 'hashie'
require 'ipaddress'
require 'netaddr'
require 'yaml'

CONFIG_FILE = 'min-config.yml'

def die(msg)
  STDERR.puts msg
  exit 1
end

def assert(msg)
  die(msg) unless yield
end

module IPAddress
  class IPv4
    # return the "n-th" ip in a subnet
    def nth(n)
      self.class.parse_u32(network_u32+n, @prefix)
    end
  end
end

# return an /etc/network/interfaces file for a compute-only node
def compute_ifaces(int_ip)
  return <<-eos
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
  address #{int_ip.address}
  netmask #{int_ip.netmask}
  gateway #{int_ip.first}
  mtu 9216

auto eth1
iface eth1 inet manual
  pre-up ip link set dev $IFACE up mtu 9216
  post-down ip link set dev $IFACE down

  eos
end

# return an /etc/network/interfaces file for a controller node
def controller_ifaces(pub_vlan, pub_ip, pub_ha_ip, int_ip, int_ha_ip)
  return <<-eos
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
  address #{int_ip.address}
  ucarp-vid 1
  ucarp-vip #{int_ha_ip.address}
  ucarp-master no
  ucarp-password TODO
  mtu 9216

iface eth0:ucarp inet static
  address #{int_ha_ip.address}
  netmask 255.255.255.255
  mtu 9216

auto eth0.#{pub_vlan}
iface eth0.#{pub_vlan} inet manual
  vlan-raw-device eth0
  mtu 9216

auto eth1
iface eth1 inet manual
  pre-up ip link set dev $IFACE up mtu 9216
  post-down ip link set dev $IFACE down

auto br-ex
iface br-ex inet static
  address #{pub_ip.address}
  netmask #{pub_ip.netmask}
  gateway #{pub_ip.first}
  up ip link set dev #{pub_vlan} up
  ucarp-vid 2
  ucarp-vip #{pub_ha_ip.address}
  ucarp-master no
  ucarp-password TODO
  mtu 9216

iface br-ex:ucarp
  address #{pub_ha_ip.address}
  netmask 255.255.255.255
  mtu 9216

  eos
end

def mkdirs(env_name)
  envs_root = "/tmp/" # TODO
  FileUtils.mkdir_p "#{envs_root}/#{env_name}/group_vars"
  FileUtils.mkdir_p "#{envs_root}/#{env_name}/host_vars"
end




def main(cfg)
  mkdirs cfg.name
end




cfg = Hashie::Mash.new( YAML.load File.read(CONFIG_FILE) )

pub = cfg.networks.public

assert "'networks.public.vlan' must be present." do
  pub and pub.vlan
end

assert "'networks.public.ip' must conatain three IPs." do
  pub.ips and pub.ips.length == 3
end

priv = cfg.networks.private
priv_subnet = IPAddress(priv.subnet)
priv_gateway = priv_subnet.first

pub.ips.map! { |ip| IPAddress(ip) }

first_controller  = controller_ifaces pub.vlan, pub.ips[1], pub.ips[0], priv_subnet.nth(2), priv_subnet.first
second_controller = controller_ifaces pub.vlan, pub.ips[2], pub.ips[0], priv_subnet.nth(3), priv_subnet.first

puts first_controller
puts "x"*80
puts second_controller
puts "x"*80

