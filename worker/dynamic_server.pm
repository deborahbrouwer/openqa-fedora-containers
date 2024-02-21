sub get_dynamic_server_ip {
    my ($test) = @_;

    if ($test eq "podman") {
        `sudo iptables -t nat -A POSTROUTING -p tcp -d 172.16.2.114 -j MASQUERADE`;
        `sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination 172.16.2.114:80`;
        return undef;
    }

    if ($test eq "podman_client") {
        my $gateway_ip = `ip route show default | grep -m1 '^default' | grep 'dev eth0' | awk '{print \$3}'`;
        chomp $gateway_ip;
        my $eth0_ip = `ip addr show eth0 | grep 'inet ' | awk '{print \$2}' | cut -d/ -f1`;
        chomp $eth0_ip;
        my $subnet = $eth0_ip;
        $subnet =~ s/\.[0-9]+$/\.0\/24/;
        my @nmap_output = `nmap -sn $subnet`;

        foreach my $line (@nmap_output) {
            if ($line =~ /Nmap scan report for/) {
                my ($ip) = $line =~ /\(([^)]+)\)/;
                next unless defined $ip;
                next if $ip eq $gateway_ip || $ip eq $eth0_ip;
                return $ip; #only works for single client-server
            }
        }
        return undef;
    }
    return undef;
}
